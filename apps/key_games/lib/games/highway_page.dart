// Note Highway screen: a song's notes fall down lanes and are hit as they
// reach the line, Guitar Hero style. A hit plays the song's own note, so the
// tune comes out even when a small child plays it on five keys. A wrong key
// plays itself and then the right note (that note counts as missed); a key
// with nothing due just plays. Streaks raise a score multiplier.
//
// Notes are never made up: the song notes that are not the player's (too
// fast, or off the level's keys) are played by the game.
//
// Difficulty (see highway_rules.dart): Easy three wide lanes, the low,
// middle and high part of the keyboard, slow, the next part glows on the
// keyboard picture; Medium the song's notes on five white keys (C to G for
// most songs), slow, the next key glows, and the picture shows only those
// keys in the octave last played; Hard every letter with sharps and flats on
// a plain picture; Expert exact keys, letters only.
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
import '../widgets/zones.dart';
import 'color_keys_rules.dart';
import 'difficulty.dart';
import 'highway_rules.dart';

const _countdownStepMs = 700;
const _flashMs = 260;

const highwayLevelsText = {
  Difficulty.easy: 'Low, middle or high, slow; the next part glows',
  Difficulty.medium: '5 keys, slow, the next key glows',
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
  // Best scores per song and level. Medium keeps the key it had when it was
  // Easy, so those scores carry over.
  String get _bestKey => 'highway.${_bestNames[_level]}.${widget.song.title}';
  static const _bestNames = {
    Difficulty.easy: 'zones',
    Difficulty.medium: 'easy',
    Difficulty.hard: 'hard',
    Difficulty.expert: 'expert',
  };

  bool get _zones => _chart.zones;

  // What a key means here: itself, or on Easy the part of the keyboard.
  int _answer(int note) =>
      _zones ? zoneOf(note, pictureKeys(context, _base), highwayZoneCount) : note;
  Color _laneColor(int lane) =>
      _zones ? zoneColors(highwayZoneCount)[lane] : pitchColor(_chart.lanes[lane].pc);

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
    final step = _run.press(_answer(event.note), now);
    final index = step.index;
    switch (step.result) {
      case HighwayResult.perfect || HighwayResult.good:
        final n = _chart.notes[index!];
        _synth.blip(n.sound, velocity: 100, lengthMs: n.lengthMs.clamp(120, 900));
        _hitAt[n.lane] = now;
        _show(step.result == HighwayResult.perfect ? 'Great!' : 'Good!');
        _sparksKey.currentState?.burst(
          _laneCenter(n.lane),
          [_colored ? _laneColor(n.lane) : Colors.white, AppColors.starGold],
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
    final geometry = _Geometry(box.size, _chart.lanes.length, uiScale(context), wide: _zones);
    return sparks.globalToLocal(box.localToGlobal(geometry.button(lane)));
  }

  // The next note's lane, while playing.
  int? get _nextLane {
    if (_phase != _Phase.playing) return null;
    for (var i = 0; i < _run.total; i++) {
      if (_run.marks[i] == NoteMark.waiting) return _chart.notes[i].lane;
    }
    return null;
  }

  // The keyboard picture glows the next note's key on Medium.
  int? get _nextKey {
    final lane = _nextLane;
    if (_level != Difficulty.medium || lane == null) return null;
    return _chart.lanes[lane].pc;
  }

  // Medium pictures just the keys from the lowest lane to the highest (lanes
  // are letters there, all within one octave).
  ({int low, int high})? _span(List<int> lanePcs) {
    // Expert's lanes are exact keys: with no keyboard, the picture shows
    // just them, so every one can be touched.
    if (_level == Difficulty.expert && !AppServices.hasKeyboard(context)) {
      final keys = [for (final lane in _chart.lanes) lane.key];
      return keys.isEmpty ? null : whiteSpan(keys.reduce(min), keys.reduce(max));
    }
    if (_zones || _level.atLeast(Difficulty.hard) || lanePcs.isEmpty) return null;
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
                      scale: uiScale(context),
                      held: {for (final note in _held) _answer(note)},
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
        if (_phase == _Phase.playing && _zones)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            child: ZoneBar(
              count: highwayZoneCount,
              picture: pictureKeys(context, _base),
              lit: _nextLane,
            ),
          ),
        if (_phase == _Phase.playing)
          Padding(
            padding: EdgeInsets.fromLTRB(8, _zones ? 4 : 8, 8, 8),
            child: SizedBox(
              height: pianoStripHeight(context, design: 140, share: 0.18),
              child: PianoStrip(
                base: _base,
                span: _span(lanePcs),
                target: _nextKey,
                plain: _plain,
                choices: _zones || _level == Difficulty.expert ? null : lanePcs,
                zones: _zones ? highwayZoneCount : null,
                litZone: _zones ? _nextLane : null,
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
      Icon(Icons.star_rounded, color: AppColors.starGold, size: 36 * uiScale(context)),
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

  // The countdown, the popups and the end panel are chrome: phone-sized
  // text grown with the screen.
  Widget _buildCountdown() {
    return ValueListenableBuilder<int>(
      valueListenable: _now,
      builder: (context, now, _) {
        if (now >= 0 || now < -3 * _countdownStepMs) return const SizedBox.shrink();
        final count = (-now / _countdownStepMs).ceil();
        return IgnorePointer(
          child: ScaledChrome(
            scale: uiScale(context),
            child: Center(
              child: Text('$count',
                  style: const TextStyle(
                      fontSize: 140, fontWeight: FontWeight.w900, color: AppColors.starGold)),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPopup() {
    if (_popup.isEmpty) return const SizedBox.shrink();
    final oops = _popup == 'Oops';
    return IgnorePointer(
      child: ScaledChrome(
        scale: uiScale(context),
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
      ),
    );
  }

  Widget _buildEnd() {
    final best = _settings.best(_bestKey);
    final s = uiScale(context);
    return ScaledChrome(
      scale: s,
      child: SingleChildScrollView(
        padding: EdgeInsets.all(16 * s),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_run.stars > 0 ? 'Song done!' : 'Nice try!',
                style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w900)),
            SizedBox(height: 8 * s),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < 3; i++)
                  Icon(Icons.star_rounded,
                      size: 64 * s, color: i < _run.stars ? AppColors.starGold : Colors.white24),
              ],
            ),
            Text('${_run.hits} of ${_run.total} notes',
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
            Text('Score ${_run.score}   Best streak ${_run.bestStreak}',
                style: const TextStyle(fontSize: 18, color: Colors.white70)),
            Text(_newBest ? 'New best!' : 'Best: $best',
                style: const TextStyle(fontSize: 18, color: Colors.white70)),
            SizedBox(height: 20 * s),
            Wrap(
              spacing: 16 * s,
              runSpacing: 12 * s,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: _restart,
                  style: keyButtonStyle(s),
                  icon: KeyBadge(pc: 0, size: 30 * s),
                  label: const Text('Play again'),
                ),
                OutlinedButton.icon(
                  onPressed: () => Navigator.maybePop(context),
                  style: keyButtonStyle(s),
                  icon: KeyBadge(pc: 4, size: 30 * s),
                  label: const Text('Songs'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// Where the lanes and the hit line are. The phone-sized caps on the lane
// width and the buttons grow with [scale] (uiScale), so a TV gets wide lanes.
class _Geometry {
  // [wide] lanes share the whole width (Easy's parts of the keyboard).
  _Geometry(this.size, this.laneCount, this.scale, {bool wide = false}) {
    laneWidth = wide
        ? size.width / max(1, laneCount)
        : min(150.0 * scale, size.width / max(1, laneCount));
    left = (size.width - laneWidth * laneCount) / 2;
    buttonRadius = min(laneWidth * 0.4, 44 * scale);
    lineY = size.height - buttonRadius - 16 * scale;
  }

  final Size size;
  final int laneCount;
  final double scale;
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

// Easy's lanes are parts of the keyboard, named on their buttons only.
const _zoneButtonNames = ['Low', 'Mid', 'High'];

class _HighwayPainter extends CustomPainter {
  _HighwayPainter({
    required this.chart,
    required this.marks,
    required this.now,
    required this.lookAheadMs,
    required this.colored,
    required this.scale,
    required this.held,
    required this.hitAt,
    required this.missAt,
  });

  final Chart chart;
  final List<NoteMark> marks;
  final int now;
  final int lookAheadMs;
  final bool colored;
  final double scale;
  final Set<int> held;
  final Map<int, int> hitAt;
  final Map<int, int> missAt;

  Color _laneColor(int lane) => !colored
      ? AppColors.plain
      : chart.zones
          ? zoneColors(highwayZoneCount)[lane]
          : pitchColor(chart.lanes[lane].pc);

  @override
  void paint(Canvas canvas, Size size) {
    final g = _Geometry(size, chart.lanes.length, scale, wide: chart.zones);
    final fill = Paint();
    // Notes past the line must not spill onto the keyboard picture.
    canvas.clipRect(Offset.zero & size);

    // Lanes: dark columns tinted with their color, a line between them.
    for (var i = 0; i < chart.lanes.length; i++) {
      final x = g.left + g.laneWidth * i;
      fill.color = Color.lerp(_laneColor(i), AppColors.background, 0.88)!;
      canvas.drawRect(Rect.fromLTWH(x + 1, 0, g.laneWidth - 2, size.height), fill);
    }
    fill.color = Colors.white24;
    canvas.drawRect(Rect.fromLTWH(g.left, g.lineY - 2, g.laneWidth * chart.lanes.length, 4), fill);

    // Notes: a head on the line at the note's time, a tail for its length.
    // Wide lanes keep a gem a gem, not a bar.
    final gemWidth = min(g.laneWidth * 0.72, 160 * scale);
    final gemHeight = min(g.laneWidth * 0.42, 34.0 * scale);
    for (var i = 0; i < chart.notes.length; i++) {
      final n = chart.notes[i];
      if (marks[i] == NoteMark.hit) continue;
      final y = g.yAt(n.timeMs - now, lookAheadMs);
      // Not on screen yet, or gone past the bottom.
      if (y < -gemHeight || y - gemHeight > size.height) continue;
      final tailTop = g.yAt(n.timeMs + n.lengthMs - now, lookAheadMs);
      final lane = chart.lanes[n.lane];
      final missed = marks[i] == NoteMark.missed;
      final color = missed ? Colors.white12 : _laneColor(n.lane);
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
      if (!missed && !chart.zones) {
        _text(canvas, _laneLabel(lane), Offset(x, y), gemHeight * 0.62, color);
      }
    }

    // Buttons on the line: brighter while a key of the lane is held, a ring
    // flash on a hit, red on a miss.
    for (var i = 0; i < chart.lanes.length; i++) {
      final lane = chart.lanes[i];
      final center = g.button(i);
      final color = _laneColor(i);
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
      if (chart.zones) {
        _text(canvas, _zoneButtonNames[i], center, g.buttonRadius * 0.48, down ? color : null);
      } else {
        _text(canvas, _laneLabel(lane), center, g.buttonRadius * 0.8, down ? color : null);
      }
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
          fontFamily: fontFamily,
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
