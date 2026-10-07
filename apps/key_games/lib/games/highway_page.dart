// Note Highway screen: a song's notes fall down lanes and are hit as they
// reach the line, Guitar Hero style. A hit plays the song's own note, so the
// tune comes out even when a small child plays it on four keys. A wrong key
// plays itself and then the right note (that note counts as missed); a key
// with nothing due just plays. Streaks raise a score multiplier.
//
// Difficulty (see highway_rules.dart): Easy 4 lanes, slow, the next key glows
// on the keyboard picture; Medium white keys; Hard the real letters with
// sharps and flats on a plain picture; Expert exact keys, letters only.
//
// Keys at the end: C plays again, E goes back to the songs.

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../audio/synth.dart';
import '../midi/computer_keys.dart';
import '../midi/midi_input.dart';
import '../songs/song.dart';
import '../widgets/key_nav.dart';
import '../widgets/keyboard_status.dart';
import '../widgets/piano_strip.dart';
import '../widgets/sparks.dart';
import 'color_keys_rules.dart';
import 'difficulty.dart';
import 'highway_rules.dart';

const _background = Color(0xFF14111C);
const _letterOnly = Color(0xFF4A4360);
const _starGold = Color(0xFFFFD84A);
const _countdownStepMs = 700;
const _flashMs = 260;

const highwayLevelsText = {
  Difficulty.easy: '4 keys, slow, the next key glows',
  Difficulty.medium: 'White keys, a bit faster',
  Difficulty.hard: 'Real letters with sharps and flats',
  Difficulty.expert: 'Exact keys, full speed',
};

enum _Phase { playing, done }

class HighwayPage extends StatefulWidget {
  const HighwayPage({
    super.key,
    required this.song,
    required this.synth,
    required this.midi,
    this.difficulty = Difficulty.easy,
  });

  final Song song;
  final Synth synth;
  final MidiInput midi;
  final Difficulty difficulty;

  @override
  State<HighwayPage> createState() => _HighwayPageState();
}

class _HighwayPageState extends State<HighwayPage> with SingleTickerProviderStateMixin {
  late final HighwayLevel _settings = highwayLevels[widget.difficulty]!;
  late final Chart _chart = buildChart(widget.song, widget.difficulty);
  late HighwayRun _run = HighwayRun(_chart, _settings.windowMs);
  late final Ticker _ticker = createTicker(_onFrame);
  final ValueNotifier<int> _now = ValueNotifier(0);
  final GlobalKey<SparksState> _sparksKey = GlobalKey();
  final GlobalKey _highwayKey = GlobalKey();
  final List<Timer> _timers = [];
  StreamSubscription<NoteEvent>? _noteSub;

  _Phase _phase = _Phase.playing;
  bool _canPick = false;
  int _base = 48;
  final Set<int> _held = {};

  // Lane -> time of its last hit or miss, for the flash at the line.
  final Map<int, int> _hitAt = {};
  final Map<int, int> _missAt = {};
  String _popup = '';
  int _popupId = 0;

  Difficulty get _level => widget.difficulty;
  bool get _colored => _level != Difficulty.expert;
  bool get _plain => _level.atLeast(Difficulty.hard);
  int get _leadInMs => max(_settings.lookAheadMs, 3 * _countdownStepMs) + 600;

  @override
  void initState() {
    super.initState();
    _noteSub = widget.midi.notes.listen(_onNote);
    HardwareKeyboard.instance.addHandler(_onKey);
    _now.value = -_leadInMs;
    unawaited(_ticker.start());
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    unawaited(_noteSub?.cancel());
    _ticker.dispose();
    _now.dispose();
    _cancelTimers();
    for (final note in _held) {
      widget.synth.noteOff(note);
    }
    super.dispose();
  }

  bool _onKey(KeyEvent event) => handleComputerKey(event, _onNote);

  void _cancelTimers() {
    for (final timer in _timers) {
      timer.cancel();
    }
    _timers.clear();
  }

  void _later(Duration delay, void Function() action) {
    _timers.add(Timer(delay, () {
      if (mounted) action();
    }));
  }

  void _restart() {
    _ticker.stop();
    _cancelTimers();
    setState(() {
      _run = HighwayRun(_chart, _settings.windowMs);
      _phase = _Phase.playing;
      _canPick = false;
      _hitAt.clear();
      _missAt.clear();
      _popup = '';
    });
    _now.value = -_leadInMs;
    unawaited(_ticker.start());
  }

  void _onFrame(Duration elapsed) {
    final before = _now.value;
    final now = elapsed.inMilliseconds - _leadInMs;
    _now.value = now;
    // 3, 2, 1 beeps while the first notes come down.
    for (var i = 3; i >= 1; i--) {
      final at = -i * _countdownStepMs;
      if (before < at && now >= at) widget.synth.blip(72, velocity: 70, lengthMs: 150);
    }
    final missed = _run.advance(now);
    if (missed.isNotEmpty) {
      setState(() {
        for (final i in missed) {
          _missAt[_chart.notes[i].lane] = now;
        }
      });
    }
    if (_run.finishedAt(now)) _finish();
  }

  void _finish() {
    _ticker.stop();
    setState(() => _phase = _Phase.done);
    if (_run.stars > 0) widget.synth.tune([72, 76, 79, 84], stepMs: 120, lengthMs: 220);
    _later(const Duration(milliseconds: 1500), () => setState(() => _canPick = true));
  }

  void _onNote(NoteEvent event) {
    if (!isGameNote(event.note)) return;
    if (!event.on) {
      widget.synth.noteOff(event.note);
      setState(() => _held.remove(event.note));
      return;
    }
    setState(() {
      _held.add(event.note);
      _base = fitBase(_base, event.note);
    });
    final now = _now.value;
    if (_phase != _Phase.playing || now < -_settings.windowMs) {
      widget.synth.noteOn(event.note, event.velocity);
      return;
    }
    final step = _run.press(event.note, now);
    final index = step.index;
    switch (step.result) {
      case HighwayResult.perfect || HighwayResult.good:
        final n = _chart.notes[index!];
        widget.synth.blip(n.sound, velocity: 100, lengthMs: n.lengthMs.clamp(120, 900));
        _hitAt[n.lane] = now;
        _show(step.result == HighwayResult.perfect ? 'Great!' : 'Good!');
        final lane = _chart.lanes[n.lane];
        _sparksKey.currentState?.burst(
          _laneCenter(n.lane),
          [_colored ? Color(pitchClasses[lane.pc].argb) : Colors.white, _starGold],
          count: 14,
          speed: 300,
        );
      case HighwayResult.wrong:
        // Your note, then the right one.
        final n = _chart.notes[index!];
        widget.synth.blip(event.note, velocity: 55, lengthMs: 150);
        _later(const Duration(milliseconds: 200),
            () => widget.synth.blip(n.sound, velocity: 85, lengthMs: 260));
        _missAt[n.lane] = now;
        _show('Oops');
      case HighwayResult.stray:
        widget.synth.blip(event.note, velocity: 50, lengthMs: 150);
    }
  }

  void _show(String text) {
    setState(() {
      _popup = text;
      _popupId++;
    });
  }

  // Middle of a lane's button at the line, in the sparks layer's coordinates.
  Offset _laneCenter(int lane) {
    final box = _highwayKey.currentContext?.findRenderObject() as RenderBox?;
    final sparks = _sparksKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || sparks == null) return Offset.zero;
    final geometry = _Geometry(box.size, _chart.lanes.length);
    return sparks.globalToLocal(box.localToGlobal(geometry.button(lane)));
  }

  // The keyboard picture glows the next note's key on Easy.
  int? get _nextKey {
    if (_level != Difficulty.easy || _phase != _Phase.playing) return null;
    for (var i = 0; i < _run.total; i++) {
      if (_run.marks[i] == NoteMark.waiting) return _chart.lanes[_chart.notes[i].lane].pc;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final lanePcs = {for (final lane in _chart.lanes) lane.pc}.toList();
    return Scaffold(
      backgroundColor: _background,
      body: KeyNav(
        midi: widget.midi,
        picks: _phase == _Phase.done && _canPick
            ? {0: _restart, 4: () => Navigator.maybePop(context)}
            : const {},
        child: Stack(
          fit: StackFit.expand,
          children: [
            SafeArea(
              child: Column(
                children: [
                  _buildTop(),
                  Expanded(
                    child: _phase == _Phase.done
                        ? Center(child: _buildEnd())
                        : Stack(
                            fit: StackFit.expand,
                            children: [
                              ValueListenableBuilder<int>(
                                valueListenable: _now,
                                builder: (context, now, _) => CustomPaint(
                                  key: _highwayKey,
                                  painter: _HighwayPainter(
                                    chart: _chart,
                                    marks: _run.marks,
                                    now: now,
                                    lookAheadMs: _settings.lookAheadMs,
                                    colored: _colored,
                                    held: _held,
                                    hitAt: _hitAt,
                                    missAt: _missAt,
                                  ),
                                ),
                              ),
                              _buildCountdown(),
                              _buildPopup(),
                            ],
                          ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: SizedBox(
                      height: min(140, MediaQuery.sizeOf(context).height * 0.18),
                      child: PianoStrip(
                        base: _base,
                        target: _nextKey,
                        plain: _plain,
                        choices: _level == Difficulty.expert ? null : lanePcs,
                        held: _held,
                        onNoteOn: (note) => _onNote(NoteEvent(note, 100, on: true)),
                        onNoteOff: (note) => _onNote(NoteEvent(note, 0, on: false)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Positioned.fill(child: IgnorePointer(child: Sparks(key: _sparksKey))),
          ],
        ),
      ),
    );
  }

  Widget _buildTop() {
    final multiplier = multiplierFor(_run.streak);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 4),
      child: Row(
        children: [
          if (Navigator.canPop(context)) const BackButton(),
          const Icon(Icons.star_rounded, color: _starGold, size: 36),
          const SizedBox(width: 4),
          Text('${_run.score}', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
          const SizedBox(width: 10),
          if (multiplier > 1)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              decoration: BoxDecoration(
                color: _starGold,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text('x$multiplier',
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF2A2233))),
            ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(widget.song.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 18, color: Colors.white70)),
          ),
          Flexible(child: KeyboardStatus(midi: widget.midi)),
        ],
      ),
    );
  }

  Widget _buildCountdown() {
    return ValueListenableBuilder<int>(
      valueListenable: _now,
      builder: (context, now, _) {
        if (now >= 0 || now < -3 * _countdownStepMs) return const SizedBox.shrink();
        final count = (-now / _countdownStepMs).ceil();
        return IgnorePointer(
          child: Center(
            child: Text('$count',
                style: const TextStyle(fontSize: 140, fontWeight: FontWeight.w900, color: _starGold)),
          ),
        );
      },
    );
  }

  Widget _buildPopup() {
    if (_popup.isEmpty) return const SizedBox.shrink();
    final oops = _popup == 'Oops';
    return IgnorePointer(
      child: Align(
        alignment: const Alignment(0, 0.25),
        child: TweenAnimationBuilder<double>(
          key: ValueKey(_popupId),
          tween: Tween(begin: 1, end: 0),
          duration: const Duration(milliseconds: 700),
          builder: (context, t, child) => Opacity(
            opacity: t,
            child: Transform.translate(offset: Offset(0, -30 * (1 - t)), child: child),
          ),
          child: Text(
            _popup,
            style: TextStyle(
              fontSize: 40,
              fontWeight: FontWeight.w900,
              color: oops ? Colors.white54 : _starGold,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEnd() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_run.stars > 0 ? 'Song done!' : 'Nice try!',
              style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < 3; i++)
                Icon(Icons.star_rounded,
                    size: 64, color: i < _run.stars ? _starGold : Colors.white24),
            ],
          ),
          Text('${_run.hits} of ${_run.total} notes',
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
          Text('Score ${_run.score}   Best streak ${_run.bestStreak}',
              style: const TextStyle(fontSize: 18, color: Colors.white70)),
          const SizedBox(height: 20),
          Wrap(
            spacing: 16,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: _restart,
                icon: const KeyBadge(pc: 0, size: 30),
                label: const Text('Play again'),
              ),
              OutlinedButton.icon(
                onPressed: () => Navigator.maybePop(context),
                icon: const KeyBadge(pc: 4, size: 30),
                label: const Text('Songs'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// Where the lanes and the hit line are.
class _Geometry {
  _Geometry(this.size, this.laneCount) {
    laneWidth = min(150.0, size.width / max(1, laneCount));
    left = (size.width - laneWidth * laneCount) / 2;
    buttonRadius = min(laneWidth * 0.4, 44);
    lineY = size.height - buttonRadius - 10;
  }

  final Size size;
  final int laneCount;
  late final double laneWidth;
  late final double left;
  late final double buttonRadius;
  late final double lineY;

  double laneX(int lane) => left + laneWidth * (lane + 0.5);
  Offset button(int lane) => Offset(laneX(lane), lineY);

  // Height of a note [ms] before it reaches the line.
  double yAt(int ms, int lookAheadMs) => lineY - ms / lookAheadMs * lineY;
}

String _laneLabel(Lane lane) =>
    lane.exact ? '${pitchClasses[lane.pc].name}${lane.key ~/ 12 - 1}' : pitchClasses[lane.pc].name;

class _HighwayPainter extends CustomPainter {
  _HighwayPainter({
    required this.chart,
    required this.marks,
    required this.now,
    required this.lookAheadMs,
    required this.colored,
    required this.held,
    required this.hitAt,
    required this.missAt,
  });

  final Chart chart;
  final List<NoteMark> marks;
  final int now;
  final int lookAheadMs;
  final bool colored;
  final Set<int> held;
  final Map<int, int> hitAt;
  final Map<int, int> missAt;

  Color _laneColor(Lane lane) => colored ? Color(pitchClasses[lane.pc].argb) : _letterOnly;

  @override
  void paint(Canvas canvas, Size size) {
    final g = _Geometry(size, chart.lanes.length);
    final fill = Paint();

    // Lanes: dark columns tinted with their color, a line between them.
    for (var i = 0; i < chart.lanes.length; i++) {
      final x = g.left + g.laneWidth * i;
      fill.color = Color.lerp(_laneColor(chart.lanes[i]), _background, 0.88)!;
      canvas.drawRect(Rect.fromLTWH(x + 1, 0, g.laneWidth - 2, size.height), fill);
    }
    fill.color = Colors.white24;
    canvas.drawRect(Rect.fromLTWH(g.left, g.lineY - 2, g.laneWidth * chart.lanes.length, 4), fill);

    // Notes: a head on the line at the note's time, a tail for its length.
    final gemWidth = g.laneWidth * 0.72;
    final gemHeight = min(g.laneWidth * 0.42, 34.0);
    for (var i = 0; i < chart.notes.length; i++) {
      final n = chart.notes[i];
      if (marks[i] == NoteMark.hit) continue;
      final y = g.yAt(n.timeMs - now, lookAheadMs);
      // Not on screen yet, or gone past the bottom.
      if (y < -gemHeight || y - gemHeight > size.height) continue;
      final tailTop = g.yAt(n.timeMs + n.lengthMs - now, lookAheadMs);
      final lane = chart.lanes[n.lane];
      final missed = marks[i] == NoteMark.missed;
      final color = missed ? Colors.white12 : _laneColor(lane);
      final x = g.laneX(n.lane);
      fill.color = color.withValues(alpha: missed ? 0.15 : 0.35);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(x - gemWidth * 0.18, tailTop, x + gemWidth * 0.18, y),
          const Radius.circular(6),
        ),
        fill,
      );
      final gem = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(x, y), width: gemWidth, height: gemHeight),
        Radius.circular(gemHeight / 2),
      );
      fill.color = color;
      canvas.drawRRect(gem, fill);
      if (!missed) _text(canvas, _laneLabel(lane), Offset(x, y), gemHeight * 0.62, color);
    }

    // Buttons on the line: brighter while a key of the lane is held, a ring
    // flash on a hit, red on a miss.
    for (var i = 0; i < chart.lanes.length; i++) {
      final lane = chart.lanes[i];
      final center = g.button(i);
      final color = _laneColor(lane);
      final down = held.any(lane.matches);
      fill.color = down ? color : Color.lerp(color, _background, 0.55)!;
      canvas.drawCircle(center, g.buttonRadius, fill);
      final hit = _flash(hitAt[i]);
      final miss = _flash(missAt[i]);
      final ring = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3 + 5 * max(hit, miss)
        ..color = miss > hit
            ? const Color(0xFFFF3B3B).withValues(alpha: 0.4 + 0.6 * miss)
            : Colors.white.withValues(alpha: 0.5 + 0.5 * hit);
      canvas.drawCircle(center, g.buttonRadius * (1 + 0.2 * hit), ring);
      _text(canvas, _laneLabel(lane), center, g.buttonRadius * 0.8, down ? color : null);
    }
  }

  // 1 right after [at], fading to 0.
  double _flash(int? at) {
    if (at == null) return 0;
    final t = (now - at) / _flashMs;
    return t < 0 || t > 1 ? 0 : 1 - t;
  }

  void _text(Canvas canvas, String text, Offset center, double size, Color? on) {
    final dark = on != null && on.computeLuminance() > 0.5;
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: size,
          fontWeight: FontWeight.w900,
          color: dark ? const Color(0xFF2A2233) : Colors.white,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, center - Offset(painter.width / 2, painter.height / 2));
  }

  @override
  bool shouldRepaint(_HighwayPainter old) => true;
}
