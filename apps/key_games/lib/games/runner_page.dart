// Key Runner screen (Temple Run style): the road comes toward the runner,
// keys pick a lane to dodge rocks and grab coins. Each coin plays the next
// note of a song (song smash), so a good run makes the melody come out. The
// keys work as buttons here; see runner_rules.dart for what each level uses.
//
// Keys at the end: C plays again, E goes back to the menu.

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
import 'runner_rules.dart';

const _background = Color(0xFF14111C);
const _letterOnly = Color(0xFF4A4360);
const _starGold = Color(0xFFFFD84A);
const _countdownStepMs = 700;

// Easy lanes: low, middle and high part of the keyboard.
const _zoneColors = [Color(0xFF22C9A0), Color(0xFFFFD84A), Color(0xFFFF5EC8)];
const _zoneNames = ['Low', 'Middle', 'High'];

const runnerLevelsText = {
  Difficulty.easy: 'Low, middle or high keys; one minute',
  Difficulty.medium: 'C E G pick the lane, 3 hearts',
  Difficulty.hard: 'The letters change, sharps too',
  Difficulty.expert: 'Fast, letters only, they change often',
};

// Best coins per difficulty, for this session.
final Map<Difficulty, int> _best = {};

enum _Phase { countdown, playing, done }

class RunnerPage extends StatefulWidget {
  const RunnerPage({
    super.key,
    required this.synth,
    required this.midi,
    this.difficulty = Difficulty.easy,
    this.random,
    this.songs,
  });

  final Synth synth;
  final MidiInput midi;
  final Difficulty difficulty;

  // Fixed in tests.
  final Random? random;
  final List<Song>? songs;

  @override
  State<RunnerPage> createState() => _RunnerPageState();
}

class _RunnerPageState extends State<RunnerPage> with SingleTickerProviderStateMixin {
  late final Random _random = widget.random ?? Random();
  late final RunnerLevel _settings = runnerLevels[widget.difficulty]!;
  late RunnerRun _run = RunnerRun(_settings, _random);
  late final Ticker _ticker = createTicker(_onFrame);
  final ValueNotifier<int> _frame = ValueNotifier(0);
  final GlobalKey<SparksState> _sparksKey = GlobalKey();
  final GlobalKey _roadKey = GlobalKey();
  final List<Timer> _timers = [];
  StreamSubscription<NoteEvent>? _noteSub;

  _Phase _phase = _Phase.countdown;
  int _count = 3;
  bool _canPick = false;
  bool _newBest = false;
  int _base = 48;
  final Set<int> _held = {};

  // Lane letters (not used on Easy) and which change of letters they are.
  late List<int> _keys = _startKeys();
  int _signs = 0;

  // Where the runner is drawn, sliding toward its lane.
  double _drawnLane = 1;
  int _lastFrameMs = 0;

  String _popup = '';
  int _popupId = 0;

  List<Song> _songs = const [];
  Song _song = scaleSong;
  int _songIndex = 0;

  Difficulty get _level => widget.difficulty;
  bool get _zones => _level == Difficulty.easy;
  bool get _colored => _level != Difficulty.expert;

  List<int> _startKeys() => switch (_level) {
        Difficulty.easy || Difficulty.medium => runnerMediumKeys,
        _ => pickLaneKeys(_random, allPitchClasses),
      };

  @override
  void initState() {
    super.initState();
    _noteSub = widget.midi.notes.listen(_onNote);
    HardwareKeyboard.instance.addHandler(_onKey);
    final given = widget.songs;
    if (given != null) {
      _songs = given;
    } else {
      unawaited(loadSongs(rootBundle).then((songs) {
        if (mounted) _songs = songs;
      }, onError: (Object _) {}));
    }
    _countdown();
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    unawaited(_noteSub?.cancel());
    _ticker.dispose();
    _frame.dispose();
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
      _run = RunnerRun(_settings, _random);
      _phase = _Phase.countdown;
      _count = 3;
      _canPick = false;
      _newBest = false;
      _keys = _startKeys();
      _signs = 0;
      _drawnLane = 1;
      _popup = '';
      _songIndex = 0;
    });
    _countdown();
  }

  // 3, 2, 1 with a beep each, then GO and the road starts moving.
  void _countdown() {
    for (var i = 0; i < 3; i++) {
      _later(Duration(milliseconds: 400 + i * _countdownStepMs), () {
        setState(() => _count = 3 - i);
        widget.synth.blip(72, velocity: 70, lengthMs: 150);
      });
    }
    _later(const Duration(milliseconds: 400 + 3 * _countdownStepMs), _go);
  }

  void _go() {
    widget.synth.blip(84, velocity: 90, lengthMs: 300);
    setState(() {
      _phase = _Phase.playing;
      // Picked now, not at the start, so the songs have finished loading.
      _song = _songs.isEmpty ? scaleSong : _songs[_random.nextInt(_songs.length)];
    });
    _lastFrameMs = 0;
    unawaited(_ticker.start());
  }

  void _onFrame(Duration elapsed) {
    final now = elapsed.inMilliseconds;
    final dt = now - _lastFrameMs;
    _lastFrameMs = now;
    final events = _run.advance(now);
    // Slide toward the lane, quickly but not instantly.
    final step = 1 - exp(-dt / 45);
    _drawnLane += (_run.lane - _drawnLane) * step.clamp(0, 1);
    for (final event in events) {
      switch (event) {
        case RunnerEvent.coin:
          _smash();
          _sparksKey.currentState?.burst(_runnerCenter(), const [_starGold, Colors.white],
              count: 10, speed: 260);
        case RunnerEvent.crash:
          widget.synth.blip(40, velocity: 110, lengthMs: 220);
          widget.synth.blip(41, velocity: 110, lengthMs: 220);
          _show('Ouch!');
      }
    }
    if (_run.signs != _signs) _changeSigns();
    _frame.value++;
    if (events.isNotEmpty) setState(() {});
    if (_run.over) _finish();
  }

  // New lane letters: play them low to high so they can be heard too.
  void _changeSigns() {
    _signs = _run.signs;
    setState(() => _keys = pickLaneKeys(_random, allPitchClasses, _keys));
    widget.synth.tune([for (final pc in _keys) 60 + pc], stepMs: 160, lengthMs: 200);
    _show('New letters!');
  }

  // Song smash: each coin plays the next note of the song.
  void _smash() {
    final notes = _song.notes;
    final n = notes[_songIndex % notes.length];
    _songIndex++;
    widget.synth.blip(n.note, velocity: 100, lengthMs: n.lengthMs.clamp(150, 600));
  }

  void _finish() {
    _ticker.stop();
    final best = _best[_level] ?? 0;
    setState(() {
      _phase = _Phase.done;
      _newBest = _run.coins > best;
      if (_newBest) _best[_level] = _run.coins;
    });
    widget.synth.tune([72, 76, 79, 84], stepMs: 120, lengthMs: 220);
    _later(const Duration(milliseconds: 1500), () => setState(() => _canPick = true));
  }

  void _show(String text) {
    setState(() {
      _popup = text;
      _popupId++;
    });
  }

  int? _laneFor(int note) => _zones ? zoneLane(note, _base) : letterLane(note, _keys);

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
    if (_phase != _Phase.playing) {
      widget.synth.noteOn(event.note, event.velocity);
      return;
    }
    // A quiet click of the key; coins carry the tune.
    widget.synth.blip(event.note, velocity: 40, lengthMs: 90);
    final lane = _laneFor(event.note);
    if (lane != null) setState(() => _run.moveTo(lane));
  }

  Offset _runnerCenter() {
    final road = _roadKey.currentContext?.findRenderObject() as RenderBox?;
    final sparks = _sparksKey.currentContext?.findRenderObject() as RenderBox?;
    if (road == null || sparks == null) return Offset.zero;
    final g = _Road(road.size);
    return sparks.globalToLocal(road.localToGlobal(Offset(g.laneX(_drawnLane, 1), g.runnerY)));
  }

  List<String> get _labels => _zones
      ? _zoneNames
      : [for (final pc in _keys) pitchClasses[pc].name];

  List<Color> get _laneColors => _zones
      ? _zoneColors
      : [for (final pc in _keys) _colored ? Color(pitchClasses[pc].argb) : _letterOnly];

  @override
  Widget build(BuildContext context) {
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
                                valueListenable: _frame,
                                builder: (context, frame, child) => CustomPaint(
                                  key: _roadKey,
                                  painter: _RoadPainter(
                                    run: _run,
                                    lane: _drawnLane,
                                    labels: _labels,
                                    colors: _laneColors,
                                    moving: _phase == _Phase.playing,
                                  ),
                                ),
                              ),
                              if (_phase == _Phase.countdown) _buildCountdown(),
                              _buildPopup(),
                            ],
                          ),
                  ),
                  // Hidden at the end, so the end choices fit a landscape phone.
                  if (_phase != _Phase.done) ..._buildKeyboard(context),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 4),
      child: Row(
        children: [
          if (Navigator.canPop(context)) const BackButton(),
          const Icon(Icons.monetization_on_rounded, color: _starGold, size: 34),
          const SizedBox(width: 4),
          Text('${_run.coins}', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
          const SizedBox(width: 14),
          if (_run.timed)
            Expanded(
              child: ValueListenableBuilder<int>(
                valueListenable: _frame,
                builder: (context, frame, child) => ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: _run.timeLeft,
                    minHeight: 12,
                    color: _starGold,
                    backgroundColor: Colors.white12,
                  ),
                ),
              ),
            )
          else ...[
            for (var i = 0; i < _settings.hearts; i++)
              Icon(Icons.favorite_rounded,
                  size: 30, color: i < _run.hearts ? const Color(0xFFFF3B3B) : Colors.white24),
            const Spacer(),
          ],
          const SizedBox(width: 12),
          Flexible(child: KeyboardStatus(midi: widget.midi)),
        ],
      ),
    );
  }

  List<Widget> _buildKeyboard(BuildContext context) {
    final height = min(130.0, MediaQuery.sizeOf(context).height * 0.17);
    return [
      // Easy: which part of the keyboard is which lane. The thirds are 7, 7
      // and 8 white keys of the 37-key picture.
      if (_zones)
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
          child: Row(
            children: [
              for (var i = 0; i < laneCount; i++)
                Expanded(
                  flex: i == laneCount - 1 ? 8 : 7,
                  child: Container(
                    height: 22,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _zoneColors[i],
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(_zoneNames[i],
                        style: const TextStyle(
                            fontWeight: FontWeight.w900, color: Color(0xFF2A2233))),
                  ),
                ),
            ],
          ),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        child: SizedBox(
          height: height,
          child: PianoStrip(
            base: _base,
            plain: _zones || _level.atLeast(Difficulty.hard),
            choices: _zones ? null : _keys,
            held: _held,
            onNoteOn: (note) => _onNote(NoteEvent(note, 100, on: true)),
            onNoteOff: (note) => _onNote(NoteEvent(note, 0, on: false)),
          ),
        ),
      ),
    ];
  }

  Widget _buildCountdown() {
    return IgnorePointer(
      child: Center(
        child: TweenAnimationBuilder<double>(
          key: ValueKey(_count),
          tween: Tween(begin: 1.6, end: 1),
          duration: const Duration(milliseconds: 300),
          builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
          child: Text('$_count',
              style: const TextStyle(fontSize: 140, fontWeight: FontWeight.w900, color: _starGold)),
        ),
      ),
    );
  }

  Widget _buildPopup() {
    if (_popup.isEmpty) return const SizedBox.shrink();
    return IgnorePointer(
      child: Align(
        alignment: const Alignment(0, -0.35),
        child: TweenAnimationBuilder<double>(
          key: ValueKey(_popupId),
          tween: Tween(begin: 1, end: 0),
          duration: const Duration(milliseconds: 900),
          builder: (context, t, child) => Opacity(
            opacity: t,
            child: Transform.translate(offset: Offset(0, -30 * (1 - t)), child: child),
          ),
          child: Text(_popup,
              style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w900, color: Colors.white)),
        ),
      ),
    );
  }

  Widget _buildEnd() {
    final best = _best[_level] ?? 0;
    final seconds = _run.nowMs ~/ 1000;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_run.timed ? "Time's up!" : 'Out of hearts!',
              style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Text('${_run.coins} coins',
              style: const TextStyle(fontSize: 52, fontWeight: FontWeight.w900, color: _starGold)),
          Text(
            '${_newBest ? 'New best!' : 'Best: $best'}   Ran $seconds seconds',
            style: const TextStyle(fontSize: 20, color: Colors.white70),
          ),
          const SizedBox(height: 4),
          Text('Your coins played ${_song.title}!',
              textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, color: Colors.white70)),
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
                label: const Text('Menu'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// The road in perspective: narrow at the horizon, full width at the runner.
class _Road {
  _Road(this.size) {
    signRadius = min(size.height * 0.09, 40);
    signY = size.height - signRadius - 6;
    runnerY = signY - signRadius - size.height * 0.1;
    horizonY = size.height * 0.1;
    width = min(size.width * 0.92, 3 * 220.0);
  }

  final Size size;
  late final double signRadius;
  late final double signY;
  late final double runnerY;
  late final double horizonY;
  late final double width;

  static const _far = 0.16;

  // 0 at the horizon, 1 at the runner, for a thing [ahead] (0..1 of the
  // look-ahead) away. Things speed up as they come closer.
  static double nearness(double ahead) {
    final s = 1 / (1 + 3 * ahead.clamp(0, 1));
    return (s - 0.25) / 0.75;
  }

  double y(double t) => horizonY + (runnerY - horizonY) * t;
  double widthAt(double t) => width * (_far + (1 - _far) * t);

  // Below the runner the road keeps its full width (signs row).
  double laneX(double lane, double t) => size.width / 2 + (lane - 1) * widthAt(t) / 3;
}

class _RoadPainter extends CustomPainter {
  _RoadPainter({
    required this.run,
    required this.lane,
    required this.labels,
    required this.colors,
    required this.moving,
  });

  final RunnerRun run;
  final double lane;
  final List<String> labels;
  final List<Color> colors;
  final bool moving;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    final g = _Road(size);
    final fill = Paint();
    final now = run.nowMs;
    final lookAhead = run.lookAheadMs;

    // Sky and ground.
    fill.shader = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFF241A3A), Color(0xFF14111C)],
    ).createShader(Rect.fromLTWH(0, 0, size.width, g.horizonY));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, g.horizonY), fill);
    fill.shader = null;
    fill.color = const Color(0xFF173024);
    canvas.drawRect(Rect.fromLTWH(0, g.horizonY, size.width, size.height), fill);

    // Road, tinted per lane, from the horizon down to the bottom.
    for (var i = 0; i < laneCount; i++) {
      final path = Path()
        ..moveTo(g.laneX(i - 0.5, 0), g.y(0))
        ..lineTo(g.laneX(i + 0.5, 0), g.y(0))
        ..lineTo(g.laneX(i + 0.5, 1), g.runnerY)
        ..lineTo(g.laneX(i + 0.5, 1), size.height)
        ..lineTo(g.laneX(i - 0.5, 1), size.height)
        ..lineTo(g.laneX(i - 0.5, 1), g.runnerY)
        ..close();
      fill.color = Color.lerp(colors[i], const Color(0xFF2A2436), 0.82)!;
      canvas.drawPath(path, fill);
    }

    // Dashes on the lane lines, moving toward the runner.
    final dash = Paint()
      ..color = Colors.white30
      ..strokeCap = StrokeCap.round;
    const dashEvery = 450;
    for (var k = 0; k < 12; k++) {
      final at = (now ~/ dashEvery + k) * dashEvery;
      final a = (at - now) / lookAhead;
      if (a > 1) break;
      final t1 = _Road.nearness(a);
      final t2 = _Road.nearness(a + 0.06);
      for (final line in [0.5, 1.5]) {
        dash.strokeWidth = 2 + 4 * t1;
        canvas.drawLine(Offset(g.laneX(line, t1), g.y(t1)), Offset(g.laneX(line, t2), g.y(t2)), dash);
      }
    }

    // Things, far ones first.
    for (final thing in run.things.reversed) {
      final a = (thing.atMs - now) / lookAhead;
      if (a > 1 || a < 0) continue;
      final t = _Road.nearness(a);
      final center = Offset(g.laneX(thing.lane.toDouble(), t), g.y(t));
      final unit = g.widthAt(t) / 3;
      if (thing.kind == ThingKind.rock) {
        _rock(canvas, center, unit * 0.62);
      } else {
        _coin(canvas, center, unit * 0.22, now);
      }
    }

    _runner(canvas, Offset(g.laneX(lane, 1), g.runnerY), g.width / 3 * 0.26, now);

    // Lane signs under the runner: the key that picks each lane.
    for (var i = 0; i < laneCount; i++) {
      final center = Offset(g.laneX(i.toDouble(), 1), g.signY);
      final here = run.lane == i;
      fill.color = here ? colors[i] : Color.lerp(colors[i], _background, 0.5)!;
      final wide = labels[i].length > 2;
      final rect = Rect.fromCenter(
          center: center, width: g.signRadius * (wide ? 3.4 : 2), height: g.signRadius * 2);
      canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(g.signRadius)), fill);
      if (here) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, Radius.circular(g.signRadius)),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..color = Colors.white,
        );
      }
      _text(canvas, labels[i], center, g.signRadius * (wide ? 0.62 : 1.0), here ? colors[i] : null);
    }
  }

  void _rock(Canvas canvas, Offset bottomCenter, double w) {
    final rect = Rect.fromCenter(center: bottomCenter.translate(0, -w * 0.3), width: w, height: w * 0.75);
    canvas.drawOval(rect.translate(0, w * 0.32).inflate(w * 0.02), Paint()..color = Colors.black38);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(w * 0.32)),
      Paint()..color = const Color(0xFF7D7590),
    );
    canvas.drawOval(
      Rect.fromCenter(center: rect.center.translate(-w * 0.12, -w * 0.14), width: w * 0.4, height: w * 0.2),
      Paint()..color = const Color(0xFFA59DB8),
    );
  }

  void _coin(Canvas canvas, Offset center, double r, int now) {
    // Spins: the width goes in and out.
    final squash = 0.35 + 0.65 * cos(now / 180).abs();
    final rect = Rect.fromCenter(center: center.translate(0, -r * 1.4), width: r * 2 * squash, height: r * 2);
    canvas.drawOval(rect, Paint()..color = const Color(0xFFE0A800));
    canvas.drawOval(rect.deflate(r * 0.25), Paint()..color = _starGold);
  }

  // A round little runner with eyes and running feet.
  void _runner(Canvas canvas, Offset feet, double r, int now) {
    final stumbling = run.stumbling;
    final step = moving ? sin(now / 70) : 0.0;
    final bounce = moving ? -(sin(now / 140).abs()) * r * 0.25 : 0.0;
    final body = feet.translate(0, -r * 1.25 + bounce);
    final foot = Paint()..color = const Color(0xFFE07A00);
    canvas.drawOval(
        Rect.fromCenter(center: feet.translate(-r * 0.45, -r * 0.15 + step * r * 0.18), width: r * 0.6, height: r * 0.34),
        foot);
    canvas.drawOval(
        Rect.fromCenter(center: feet.translate(r * 0.45, -r * 0.15 - step * r * 0.18), width: r * 0.6, height: r * 0.34),
        foot);
    final blink = stumbling && (now ~/ 100).isEven;
    canvas.drawCircle(body, r, Paint()..color = blink ? const Color(0xFFFF6A6A) : _starGold);
    final eye = Paint()..color = const Color(0xFF2A2233);
    canvas.drawCircle(body.translate(-r * 0.32, -r * 0.2), r * 0.13, eye);
    canvas.drawCircle(body.translate(r * 0.32, -r * 0.2), r * 0.13, eye);
    canvas.drawArc(
      Rect.fromCenter(center: body.translate(0, r * 0.15), width: r * 0.6, height: r * 0.4),
      stumbling ? pi : 0,
      pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.09
        ..color = const Color(0xFF2A2233),
    );
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
  bool shouldRepaint(_RoadPainter old) => true;
}
