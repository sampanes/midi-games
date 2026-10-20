// Note Highway screen: a song's notes fall down lanes and are hit as they
// reach the line, Guitar Hero style. A hit plays the song's own note, so the
// tune comes out even when a small child plays it on five keys. A wrong key
// plays itself and then the right note (that note counts as missed); a key
// with nothing due just plays. Streaks raise a score multiplier.
//
// Notes are never made up: the song notes that are not the player's (too
// fast, or off the level's keys) are played by the game.
//
// Difficulty (see highway_rules.dart): Easy the song's notes on five white
// keys (C to G for most songs), slow, the next key glows on the keyboard
// picture; Medium all white keys; Hard every letter with sharps and flats on
// a plain picture; Expert exact keys, letters only. Easy and Medium show
// only the keys the song uses on the keyboard picture, in the octave last
// played.
//
// Keys at the end: C plays again, E goes back to the songs. The best score
// per song and level is kept on the device.

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../app/services.dart';
import '../app/settings.dart';
import '../app/theme.dart';
import '../audio/synth.dart';
import '../midi/midi_input.dart';
import '../songs/song.dart';
import '../widgets/game_page.dart';
import '../widgets/key_badge.dart';
import '../widgets/piano_strip.dart';
import '../widgets/sparks.dart';
import 'color_keys_rules.dart';
import 'difficulty.dart';
import 'highway_rules.dart';

const _countdownStepMs = 700;
const _flashMs = 260;

const highwayLevelsText = {
  Difficulty.easy: '5 keys, slow, the next key glows',
  Difficulty.medium: 'White keys, a bit faster',
  Difficulty.hard: 'Real letters with sharps and flats',
  Difficulty.expert: 'Exact keys, full speed',
};

enum _Phase { playing, done }

class HighwayPage extends StatefulWidget {
  const HighwayPage({
    super.key,
    required this.song,
    this.difficulty = Difficulty.easy,
  });

  final Song song;
  final Difficulty difficulty;

  @override
  State<HighwayPage> createState() => _HighwayPageState();
}

class _HighwayPageState extends State<HighwayPage> with SingleTickerProviderStateMixin {
  late final Synth _synth = AppServices.of(context).synth;
  late final Settings _settings = AppServices.of(context).settings;
  late final HighwayLevel _rules = highwayLevels[widget.difficulty]!;
  late final Chart _chart = buildChart(widget.song, widget.difficulty);
  late HighwayRun _run = HighwayRun(_chart, _rules.windowMs);
  late final Ticker _ticker = createTicker(_onFrame);
  final ValueNotifier<int> _now = ValueNotifier(0);
  final GlobalKey<SparksState> _sparksKey = GlobalKey();
  final GlobalKey _highwayKey = GlobalKey();
  final List<Timer> _timers = [];

  _Phase _phase = _Phase.playing;
  bool _canPick = false;
  bool _newBest = false;
  int _base = 48;
  // The octave (its C) of the last key played, for the small picture.
  int _octave = 60;
  final Set<int> _held = {};

  // Next of the song notes the game plays itself.
  int _autoNext = 0;

  // Lane -> time of its last hit or miss, for the flash at the line.
  final Map<int, int> _hitAt = {};
  final Map<int, int> _missAt = {};
  String _popup = '';
  int _popupId = 0;

  Difficulty get _level => widget.difficulty;
  bool get _colored => _level != Difficulty.expert;
  bool get _plain => _level.atLeast(Difficulty.hard);
  int get _leadInMs => max(_rules.lookAheadMs, 3 * _countdownStepMs) + 600;
  String get _bestKey => 'highway.${_level.name}.${widget.song.title}';

  @override
  void initState() {
    super.initState();
    _now.value = -_leadInMs;
    unawaited(_ticker.start());
  }

  @override
  void dispose() {
    _ticker.dispose();
    _now.dispose();
    _cancelTimers();
    for (final note in _held) {
      _synth.noteOff(note);
    }
    super.dispose();
  }

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
      _run = HighwayRun(_chart, _rules.windowMs);
      _phase = _Phase.playing;
      _canPick = false;
      _newBest = false;
      _autoNext = 0;
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
      if (before < at && now >= at) _synth.blip(72, velocity: 70, lengthMs: 150);
    }
    // The song notes that are not the player's play on their own.
    final autos = _chart.autoNotes;
    while (_autoNext < autos.length && autos[_autoNext].timeMs <= now) {
      final n = autos[_autoNext++];
      if (n.timeMs >= now - 200) {
        _synth.blip(n.sound, velocity: 80, lengthMs: n.lengthMs.clamp(100, 900));
      }
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
    setState(() {
      _phase = _Phase.done;
      _newBest = _settings.recordBest(_bestKey, _run.score);
    });
    if (_run.stars > 0) _synth.tune([72, 76, 79, 84], stepMs: 120, lengthMs: 220);
    _later(const Duration(milliseconds: 1500), () => setState(() => _canPick = true));
  }

  void _onNote(NoteEvent event) {
    if (!isGameNote(event.note)) return;
    if (!event.on) {
      _synth.noteOff(event.note);
      setState(() => _held.remove(event.note));
      return;
    }
    setState(() {
      _held.add(event.note);
      _base = fitBase(_base, event.note);
      _octave = event.note - pitchClass(event.note);
    });
    final now = _now.value;
    if (_phase != _Phase.playing || now < -_rules.windowMs) {
      _synth.noteOn(event.note, event.velocity);
      return;
    }
    final step = _run.press(event.note, now);
    final index = step.index;
    switch (step.result) {
      case HighwayResult.perfect || HighwayResult.good:
        final n = _chart.notes[index!];
        _synth.blip(n.sound, velocity: 100, lengthMs: n.lengthMs.clamp(120, 900));
        _hitAt[n.lane] = now;
        _show(step.result == HighwayResult.perfect ? 'Great!' : 'Good!');
        final lane = _chart.lanes[n.lane];
        _sparksKey.currentState?.burst(
          _laneCenter(n.lane),
          [_colored ? pitchColor(lane.pc) : Colors.white, AppColors.starGold],
          count: 14,
          speed: 300,
        );
      case HighwayResult.wrong:
        // Your note, then the right one.
        final n = _chart.notes[index!];
        _synth.blip(event.note, velocity: 55, lengthMs: 150);
        _later(const Duration(milliseconds: 200),
            () => _synth.blip(n.sound, velocity: 85, lengthMs: 260));
        _missAt[n.lane] = now;
        _show('Oops');
      case HighwayResult.stray:
        _synth.blip(event.note, velocity: 50, lengthMs: 150);
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

  // Easy and Medium picture just the keys from the lowest lane to the
  // highest (lanes are letters there, all within one octave).
  ({int low, int high})? _span(List<int> lanePcs) {
    if (_level.atLeast(Difficulty.hard) || lanePcs.isEmpty) return null;
    return whiteSpan(_octave + lanePcs.reduce(min), _octave + lanePcs.reduce(max));
  }

  @override
  Widget build(BuildContext context) {
    final lanePcs = {for (final lane in _chart.lanes) lane.pc}.toList();
    return GamePage(
      picks: _phase == _Phase.done && _canPick
          ? {0: _restart, 4: () => Navigator.maybePop(context)}
          : const {},
      onNote: _onNote,
      header: _header(),
      body: _phase == _Phase.done
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
                      lookAheadMs: _rules.lookAheadMs,
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
      footer: [
        // Hidden at the end, so the end choices fit a landscape phone.
        if (_phase == _Phase.playing)
          Padding(
            padding: const EdgeInsets.all(8),
            child: SizedBox(
              height: min(140, MediaQuery.sizeOf(context).height * 0.18),
              child: PianoStrip(
                base: _base,
                span: _span(lanePcs),
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
      overlays: [
        Positioned.fill(child: IgnorePointer(child: Sparks(key: _sparksKey))),
      ],
    );
  }

  List<Widget> _header() {
    final multiplier = multiplierFor(_run.streak);
    return [
      const Icon(Icons.star_rounded, color: AppColors.starGold, size: 36),
      const SizedBox(width: 4),
      Text('${_run.score}', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
      const SizedBox(width: 10),
      if (multiplier > 1)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.starGold,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text('x$multiplier',
              style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.ink)),
        ),
      const SizedBox(width: 10),
      Expanded(
        child: Text(widget.song.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 18, color: Colors.white70)),
      ),
    ];
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
                style: const TextStyle(
                    fontSize: 140, fontWeight: FontWeight.w900, color: AppColors.starGold)),
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
              color: oops ? Colors.white54 : AppColors.starGold,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEnd() {
    final best = _settings.best(_bestKey);
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
                    size: 64, color: i < _run.stars ? AppColors.starGold : Colors.white24),
            ],
          ),
          Text('${_run.hits} of ${_run.total} notes',
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
          Text('Score ${_run.score}   Best streak ${_run.bestStreak}',
              style: const TextStyle(fontSize: 18, color: Colors.white70)),
          Text(_newBest ? 'New best!' : 'Best: $best',
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
    lineY = size.height - buttonRadius - 16;
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

  Color _laneColor(Lane lane) => colored ? pitchColor(lane.pc) : AppColors.plain;

  @override
  void paint(Canvas canvas, Size size) {
    final g = _Geometry(size, chart.lanes.length);
    final fill = Paint();
    // Notes past the line must not spill onto the keyboard picture.
    canvas.clipRect(Offset.zero & size);

    // Lanes: dark columns tinted with their color, a line between them.
    for (var i = 0; i < chart.lanes.length; i++) {
      final x = g.left + g.laneWidth * i;
      fill.color = Color.lerp(_laneColor(chart.lanes[i]), AppColors.background, 0.88)!;
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
      fill.color = down ? color : Color.lerp(color, AppColors.background, 0.55)!;
      canvas.drawCircle(center, g.buttonRadius, fill);
      final hit = _flash(hitAt[i]);
      final miss = _flash(missAt[i]);
      final ring = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3 + 5 * max(hit, miss)
        ..color = miss > hit
            ? AppColors.red.withValues(alpha: 0.4 + 0.6 * miss)
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
          color: dark ? AppColors.ink : Colors.white,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, center - Offset(painter.width / 2, painter.height / 2));
  }

  @override
  bool shouldRepaint(_HighwayPainter old) => true;
}
