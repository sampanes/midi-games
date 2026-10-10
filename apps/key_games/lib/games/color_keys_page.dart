// Color Keys screen: a big circle shows a note letter in its color, the child
// presses a key of that note and it plays. Hits earn a star and sparks; 8 stars win a
// round. Wrong keys still make music, sparkle, and gently wiggle the circle;
// then the right note plays once as a correction.
//
// The real keys have no colors, so a picture of the keyboard along the bottom
// shows the colors and makes every key of the target color glow.
//
// Difficulty: Easy glows the keys; Medium shows only the colors on the
// picture; Hard adds the black keys on a plain picture (read the letter);
// Expert shows the letter alone, with no color and no sound hint.
//
// Input: any connected MIDI keyboard (auto-connected), touching the keyboard
// picture, and the computer keys A S D F G H J K.

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../audio/miss_echo.dart';
import '../audio/synth.dart';
import '../midi/computer_keys.dart';
import '../midi/midi_input.dart';
import '../widgets/key_nav.dart';
import '../widgets/keyboard_status.dart';
import '../widgets/piano_strip.dart';
import '../widgets/sparks.dart';
import '../widgets/win_banner.dart';
import 'color_keys_rules.dart';
import 'difficulty.dart';

const _background = Color(0xFF14111C);
const _starGold = Color(0xFFFFD84A);
const _hitDelay = Duration(milliseconds: 650);
const _winDelay = Duration(milliseconds: 2800);
const _chordWindow = Duration(milliseconds: 250);
const _chordResetDelay = Duration(seconds: 1);
const _letterOnly = Color(0xFF4A4360);

const colorKeysLevels = {
  Difficulty.easy: 'The right keys glow',
  Difficulty.medium: 'Match the color',
  Difficulty.hard: 'Read the letter, black keys too',
  Difficulty.expert: 'Letter only, no hints',
};

Color pitchColor(int pc) => Color(pitchClasses[pc].argb);

class ColorKeysPage extends StatefulWidget {
  const ColorKeysPage({
    super.key,
    required this.synth,
    required this.midi,
    this.difficulty = Difficulty.easy,
    this.random,
  });

  final Synth synth;
  final MidiInput midi;
  final Difficulty difficulty;
  final Random? random;

  @override
  State<ColorKeysPage> createState() => _ColorKeysPageState();
}

class _ColorKeysPageState extends State<ColorKeysPage>
    with TickerProviderStateMixin {
  late final Random _random = widget.random ?? Random();
  final GlobalKey<SparksState> _sparksKey = GlobalKey();
  final GlobalKey _circleKey = GlobalKey();
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  );
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  Difficulty get _level => widget.difficulty;
  bool get _glow => _level == Difficulty.easy;
  bool get _plain => _level.atLeast(Difficulty.hard);
  bool get _colored => _level != Difficulty.expert;
  List<int> get _choices => _plain ? allPitchClasses : whitePitchClasses;
  late ColorKeysState _state = ColorKeysState.start(_random, _choices);
  late final MissEcho _echo = MissEcho(widget.synth);
  StreamSubscription<NoteEvent>? _noteSub;
  Timer? _advanceTimer;
  Timer? _attemptTimer;
  Timer? _chordResetTimer;
  Timer? _hintOffTimer;
  int? _hintNote;
  bool _celebrating = false;
  // Lowest C of the keyboard picture, and notes currently held down.
  int _base = 48;
  final Set<int> _held = {};
  final List<int> _attemptNotes = [];
  final Set<int> _mutedUntilRelease = {};
  final Set<int> _chordHeld = {};

  @override
  void initState() {
    super.initState();
    _noteSub = widget.midi.notes.listen(_onNote);
    HardwareKeyboard.instance.addHandler(_onKey);
    // Play the first color's note once the synth has had time to load.
    _advanceTimer = Timer(const Duration(milliseconds: 1200), _playTarget);
  }

  // Each new color plays its own note, so the colors and sounds go together.
  void _playTarget() {
    if (mounted && _colored) {
      _stopHint();
      final note = 72 + _state.target;
      _hintNote = note;
      widget.synth.noteOn(note, 70);
      _hintOffTimer = Timer(const Duration(milliseconds: 350), () {
        if (_hintNote != note) return;
        widget.synth.noteOff(note);
        _hintOffTimer = Timer(Synth.releaseLength, () {
          if (_hintNote != note) return;
          _hintNote = null;
          _hintOffTimer = null;
        });
      });
    }
  }

  void _stopHint() {
    _hintOffTimer?.cancel();
    _hintOffTimer = null;
    final note = _hintNote;
    _hintNote = null;
    if (note != null) widget.synth.noteOffNow(note);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    unawaited(_noteSub?.cancel());
    _advanceTimer?.cancel();
    _attemptTimer?.cancel();
    _chordResetTimer?.cancel();
    _stopHint();
    _echo.cancel();
    for (final note in _held) {
      widget.synth.noteOff(note);
    }
    _pulse.dispose();
    _shake.dispose();
    super.dispose();
  }

  bool _onKey(KeyEvent event) => handleComputerKey(event, _onNote);

  void _onNote(NoteEvent event) {
    if (!isGameNote(event.note)) return;
    if (!event.on) {
      final muted = _mutedUntilRelease.remove(event.note);
      if (!muted) widget.synth.noteOff(event.note);
      setState(() {
        _held.remove(event.note);
        _chordHeld.remove(event.note);
      });
      if (_chordHeld.isEmpty) {
        _chordResetTimer?.cancel();
        _chordResetTimer = null;
      }
      return;
    }

    // Once a chord has been rejected, keep its correction tone solo until all
    // participating keys are released. Any extra rolled-in keys join that same
    // rejected chord rather than becoming another attempt.
    if (_chordHeld.isNotEmpty) {
      setState(() {
        _held.add(event.note);
        _chordHeld.add(event.note);
        _mutedUntilRelease.add(event.note);
      });
      _armChordReset();
      return;
    }

    // Stop an earlier correction before starting a new physical note. This
    // also prevents its stop timer from cutting off the new press later.
    _stopHint();
    _echo.cancel();
    _mutedUntilRelease.remove(event.note);
    widget.synth.noteOn(event.note, event.velocity);
    setState(() {
      _base = fitBase(_base, event.note);
      _held.add(event.note);
    });
    if (_state.locked) return;

    if (_attemptNotes.isEmpty) {
      // The player has begun answering, so a delayed startup hint must not
      // overlap the attempt or its correction.
      _advanceTimer?.cancel();
      _advanceTimer = null;
      _attemptNotes.add(event.note);
      _attemptTimer = Timer(_chordWindow, _resolveAttempt);
      return;
    }
    if (_attemptNotes.contains(event.note)) return;

    _attemptNotes.add(event.note);
    _resolveAttempt();
  }

  void _resolveAttempt() {
    _attemptTimer?.cancel();
    _attemptTimer = null;
    if (!mounted || _attemptNotes.isEmpty) return;

    final notes = List<int>.of(_attemptNotes);
    _attemptNotes.clear();
    final result = pressColorAttempt(_state, notes);
    final chord = notes.toSet().length > 1;
    if (chord) {
      _chordHeld.addAll(notes.where(_held.contains));
      _armChordReset();
    }
    setState(() => _state = result.state);

    for (final effect in result.effects) {
      switch (effect) {
        case Effect.play:
          break;
        case Effect.miss:
          final played = notes.last;
          _shake.forward(from: 0);
          _sparksKey.currentState?.burst(
            _circleCenter(),
            [pitchColor(pitchClass(played))],
            count: 12,
            speed: 300,
          );
          final anchor = notes.firstWhere(
            (note) => pitchClass(note) == _state.target,
            orElse: () => played,
          );
          final right = nearestOfClassInRange(
            anchor,
            _state.target,
            max(_base, Synth.lowestNote),
            min(_base + pianoKeyCount - 1, Synth.highestNote),
          );
          // End any still-held player notes before the correction. Their later
          // Note Off messages must not cut off the correction if it has the same
          // pitch as one of the chord notes.
          for (final note in {...notes, ..._held}) {
            widget.synth.noteOffNow(note);
          }
          _mutedUntilRelease.addAll(_held);
          _echo.playRightOnly(right);
        case Effect.hit:
          _echo.cancel();
          _celebrateHit(pitchClass(notes.single));
        case Effect.nextSoon:
          _scheduleAdvance(_hitDelay);
        case Effect.win:
          _celebrateWin();
          _scheduleAdvance(_winDelay);
      }
    }
  }

  // Lost MIDI Note Off messages should not leave the game permanently stuck
  // treating every future key as part of the same rejected chord.
  void _armChordReset() {
    if (_chordResetTimer != null) return;
    _chordResetTimer = Timer(_chordResetDelay, () {
      _chordResetTimer = null;
      if (!mounted || _chordHeld.isEmpty) return;
      setState(() {
        _held.removeAll(_chordHeld);
        _chordHeld.clear();
      });
    });
  }

  void _celebrateHit(int pc) {
    _pulse.forward(from: 0);
    final color = pitchColor(pc);
    _sparksKey.currentState?.burst(_circleCenter(), [
      color,
      Colors.white,
      _starGold,
    ]);
    widget.synth.tune([84 + pc, 91 + pc], stepMs: 70, lengthMs: 150);
  }

  void _celebrateWin() {
    setState(() => _celebrating = true);
    final rainbow = [for (final pc in whitePitchClasses) pitchColor(pc)];
    final size = MediaQuery.sizeOf(context);
    final sparks = _sparksKey.currentState;
    for (var i = 0; i < 5; i++) {
      Timer(Duration(milliseconds: 250 * i), () {
        if (!mounted) return;
        final at = Offset(
          size.width * (0.15 + 0.7 * _random.nextDouble()),
          size.height * (0.2 + 0.5 * _random.nextDouble()),
        );
        sparks?.burst(at, rainbow, count: 50, speed: 650);
      });
    }
    widget.synth.tune([84, 88, 91, 96, 91, 96], stepMs: 130, lengthMs: 200);
  }

  void _scheduleAdvance(Duration delay) {
    _advanceTimer?.cancel();
    _advanceTimer = Timer(delay, () {
      if (!mounted) return;
      setState(() {
        _state = advance(_state, _random, _choices);
        _celebrating = false;
      });
      _playTarget();
    });
  }

  Offset _circleCenter() {
    final circle = _circleKey.currentContext?.findRenderObject() as RenderBox?;
    final sparks = _sparksKey.currentContext?.findRenderObject() as RenderBox?;
    if (circle == null || sparks == null) return Offset.zero;
    final global = circle.localToGlobal(circle.size.center(Offset.zero));
    return sparks.globalToLocal(global);
  }

  @override
  Widget build(BuildContext context) {
    final target = pitchClasses[_state.target];
    final color = _colored ? Color(target.argb) : _letterOnly;
    return Scaffold(
      backgroundColor: _background,
      body: KeyNav(
        midi: widget.midi,
        child: Stack(
          fit: StackFit.expand,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [color.withValues(alpha: 0.28), _background],
                  radius: 0.9,
                ),
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Row(
                      children: [
                        if (Navigator.canPop(context)) const BackButton(),
                        Expanded(child: _StarRow(stars: _state.stars)),
                        Flexible(child: KeyboardStatus(midi: widget.midi)),
                      ],
                    ),
                  ),
                  Expanded(child: Center(child: _buildCircle(target, color))),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                    child: SizedBox(
                      height: min(
                        180,
                        MediaQuery.sizeOf(context).height * 0.24,
                      ),
                      child: PianoStrip(
                        base: _base,
                        target: _state.locked || !_glow ? null : _state.target,
                        plain: _plain,
                        held: _held,
                        onNoteOn: (note) =>
                            _onNote(NoteEvent(note, 100, on: true)),
                        onNoteOff: (note) =>
                            _onNote(NoteEvent(note, 0, on: false)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Positioned.fill(child: Sparks(key: _sparksKey)),
            if (_celebrating) const WinBanner(),
          ],
        ),
      ),
    );
  }

  Widget _buildCircle(PitchClassInfo target, Color color) {
    final darkText = color.computeLuminance() > 0.5;
    return LayoutBuilder(
      builder: (context, constraints) {
        final diameter =
            min(constraints.maxWidth, constraints.maxHeight) * 0.72;
        return AnimatedBuilder(
          animation: Listenable.merge([_pulse, _shake]),
          builder: (context, child) {
            final p = _pulse.value;
            final s = _shake.value;
            return Transform.translate(
              offset: Offset(sin(s * pi * 6) * 22 * (1 - s), 0),
              child: Transform.scale(
                scale: 1 + 0.16 * sin(p * pi),
                child: child,
              ),
            );
          },
          child: AnimatedContainer(
            key: _circleKey,
            duration: const Duration(milliseconds: 250),
            width: diameter,
            height: diameter,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 60),
              ],
            ),
            alignment: Alignment.center,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Padding(
                padding: EdgeInsets.all(diameter * 0.12),
                child: Text(
                  target.name,
                  style: TextStyle(
                    fontSize: diameter * 0.42,
                    fontWeight: FontWeight.w900,
                    color: darkText ? const Color(0xFF2A2233) : Colors.white,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _StarRow extends StatelessWidget {
  const _StarRow({required this.stars});

  final int stars;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = min(52.0, constraints.maxWidth / starsPerRound);
        return Row(
          children: [
            for (var i = 0; i < starsPerRound; i++)
              AnimatedScale(
                scale: i < stars ? 1.0 : 0.8,
                duration: const Duration(milliseconds: 300),
                curve: Curves.elasticOut,
                child: Icon(
                  Icons.star_rounded,
                  size: size,
                  color: i < stars ? _starGold : Colors.white24,
                ),
              ),
          ],
        );
      },
    );
  }
}
