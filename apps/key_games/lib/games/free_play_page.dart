// Free Play: no rules and nothing to get wrong. Every key plays its note and
// sends a glowing ball of its color up from its place on the keyboard
// picture; the ball carries the note's letter and bursts into sparks at the
// top of its flight. A harder press flies higher. For the smallest players,
// and for anyone who just wants to play.
//
// Input: the keyboard and the computer keys, through the key router, plus
// touching the keyboard picture.

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../app/services.dart';
import '../app/theme.dart';
import '../audio/synth.dart';
import '../midi/midi_input.dart';
import '../widgets/game_page.dart';
import '../widgets/piano_strip.dart';
import '../widgets/sparks.dart';
import 'color_keys_rules.dart';

const _flightMs = 900;

// Balls in the air at once; a new one past this bursts the oldest early.
const _maxBalls = 40;

// The keyboard picture's margin, as in every game.
const _stripMargin = 8.0;

// How high a ball flies, as a share of the sky: a soft press gets about
// halfway, a hard one near the top.
double flightHeight(int velocity) => 0.45 + 0.45 * (velocity.clamp(1, 127) / 127);

class _Ball {
  _Ball(this.note, this.bornMs, this.height, this.drift);

  final int note;
  final int bornMs;

  // Share of the sky it climbs, and a small sideways lean (in ball widths)
  // so the same key pressed twice does not draw one ball on another.
  final double height;
  final double drift;
}

class FreePlayPage extends StatefulWidget {
  const FreePlayPage({super.key, this.random});

  // Fixed in tests.
  final Random? random;

  @override
  State<FreePlayPage> createState() => _FreePlayPageState();
}

class _FreePlayPageState extends State<FreePlayPage> with SingleTickerProviderStateMixin {
  // Looked up when the page opens: a page left before it made a sound must
  // not look it up while it closes.
  late final Synth _synth;
  late final Random _random = widget.random ?? Random();
  late final Ticker _ticker = createTicker(_onFrame);
  final ValueNotifier<int> _now = ValueNotifier(0);
  final GlobalKey<SparksState> _sparksKey = GlobalKey();
  final List<_Ball> _balls = [];
  final Set<int> _held = {};
  int _base = 48;
  int? _last;
  bool _played = false;
  Size _sky = Size.zero;

  @override
  void initState() {
    super.initState();
    _synth = AppServices.of(context).synth;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _now.dispose();
    for (final note in _held) {
      _synth.noteOff(note);
    }
    super.dispose();
  }

  void _onNote(NoteEvent event) {
    if (!isGameNote(event.note)) return;
    if (!event.on) {
      _synth.noteOff(event.note);
      setState(() => _held.remove(event.note));
      return;
    }
    _synth.noteOn(event.note, event.velocity);
    setState(() {
      _base = fitBase(_base, event.note);
      _held.add(event.note);
      _last = event.note;
      _played = true;
    });
    // A stopped ticker starts again from zero, so the balls' clock does too.
    if (!_ticker.isActive) _now.value = 0;
    if (_balls.length >= _maxBalls) _burst(_balls.removeAt(0), _now.value);
    _balls.add(_Ball(
      event.note,
      _now.value,
      flightHeight(event.velocity) + 0.06 * (_random.nextDouble() - 0.5),
      _random.nextDouble() - 0.5,
    ));
    if (!_ticker.isActive) _ticker.start();
  }

  void _onFrame(Duration elapsed) {
    final now = elapsed.inMilliseconds;
    _balls.removeWhere((ball) {
      if (now - ball.bornMs < _flightMs) return false;
      _burst(ball, now);
      return true;
    });
    _now.value = now;
    if (_balls.isEmpty) _ticker.stop();
  }

  void _burst(_Ball ball, int now) {
    final color = noteColor(ball.note);
    _sparksKey.currentState?.burst(
      _place(ball, now),
      [color, Colors.white, AppColors.starGold],
      count: 26,
      speed: 300 * uiScale(context),
    );
  }

  double get _radius => min(_sky.height * 0.09, 44 * uiScale(context));

  // Where [ball] is at [now]: straight up from its key, slowing as it climbs.
  Offset _place(_Ball ball, int now) {
    final keys = pictureKeys(context, _base);
    var note = ball.note;
    while (note < keys.low) {
      note += 12;
    }
    while (note > keys.high) {
      note -= 12;
    }
    final column = keyColumn(keys.low, keys.high, _sky.width - 2 * _stripMargin, note);
    final t = ((now - ball.bornMs) / _flightMs).clamp(0.0, 1.0);
    final climbed = Curves.easeOutCubic.transform(t) * ball.height * _sky.height;
    return Offset(
      _stripMargin + column.left + column.width / 2 + ball.drift * _radius * t,
      _sky.height - climbed,
    );
  }

  @override
  Widget build(BuildContext context) {
    final last = _last;
    final tint = last == null ? AppColors.plain : noteColor(last);
    return GamePage(
      title: 'Free Play',
      onNote: _onNote,
      backdrop: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        decoration: BoxDecoration(
          gradient: RadialGradient(
            colors: [tint.withValues(alpha: 0.3), AppColors.background],
            radius: 0.9,
          ),
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          _sky = constraints.biggest;
          return Stack(
            fit: StackFit.expand,
            children: [
              AnimatedOpacity(
                opacity: _played ? 0 : 1,
                duration: const Duration(milliseconds: 500),
                child: Center(
                  child: Text(
                    'Press any key!',
                    style: TextStyle(
                      fontSize: 40 * uiScale(context),
                      fontWeight: FontWeight.w900,
                      color: Colors.white54,
                    ),
                  ),
                ),
              ),
              ValueListenableBuilder<int>(
                valueListenable: _now,
                builder: (context, now, _) => CustomPaint(
                  painter: _BallPainter(
                    places: [for (final ball in _balls) _place(ball, now)],
                    notes: [for (final ball in _balls) ball.note],
                    radius: _radius,
                  ),
                ),
              ),
              Sparks(key: _sparksKey),
            ],
          );
        },
      ),
      footer: [
        Padding(
          padding: const EdgeInsets.all(_stripMargin),
          child: SizedBox(
            height: pianoStripHeight(context),
            child: PianoStrip(
              base: _base,
              held: _held,
              onNoteOn: (note) => _onNote(NoteEvent(note, 100, on: true)),
              onNoteOff: (note) => _onNote(NoteEvent(note, 0, on: false)),
            ),
          ),
        ),
      ],
    );
  }
}

class _BallPainter extends CustomPainter {
  _BallPainter({required this.places, required this.notes, required this.radius});

  final List<Offset> places;
  final List<int> notes;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final glow = Paint()..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.6);
    final fill = Paint();
    for (var i = 0; i < places.length; i++) {
      final color = noteColor(notes[i]);
      glow.color = color.withValues(alpha: 0.6);
      canvas.drawCircle(places[i], radius * 1.25, glow);
      fill.color = color;
      canvas.drawCircle(places[i], radius, fill);
      final text = TextPainter(
        text: TextSpan(
          text: pitchClasses[pitchClass(notes[i])].name,
          style: TextStyle(
            fontFamily: fontFamily,
            fontSize: radius * 0.9,
            fontWeight: FontWeight.w900,
            color: color.computeLuminance() > 0.5 ? AppColors.ink : Colors.white,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      text.paint(canvas, places[i] - Offset(text.width / 2, text.height / 2));
    }
  }

  @override
  bool shouldRepaint(_BallPainter old) => true;
}
