// Song mode: the glowing key walks through a real melody. The game waits for
// each note (no timing pressure). The octave matters: the right letter in the
// wrong octave gets a "Higher!" / "Lower!" nudge. The keyboard's octave
// buttons are followed by whole octaves (its keys send 48-84 when centered,
// the same range as the picture). A row of bubbles shows
// what comes next, higher notes sitting higher. A wrong key is followed by
// that note and then the right one, to compare by ear. If nothing is played for a
// few seconds, the next note sounds as a hint. At the end the whole melody
// plays back at its real speed, so the child hears the song they just built.
// The end buttons are picked with keys too: C again, D listen, E more songs.
//
// Difficulty: Easy glows the key; Medium shows only the colored bubbles;
// Hard shows letters alone on a plain keyboard; Expert is by ear ("?"
// bubbles; the hint note and Higher!/Lower! still help). Easy and Medium
// show only the keys from the song's lowest note to its highest.

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../audio/miss_echo.dart';
import '../audio/synth.dart';
import '../games/color_keys_rules.dart';
import '../games/difficulty.dart';
import '../midi/computer_keys.dart';
import '../midi/midi_input.dart';
import '../widgets/key_nav.dart';
import '../widgets/keyboard_status.dart';
import '../widgets/piano_strip.dart';
import '../widgets/sparks.dart';
import '../widgets/win_banner.dart';
import 'song.dart';

const _background = Color(0xFF14111C);
const _hintEvery = Duration(seconds: 5);
const _slide = Duration(milliseconds: 280);
const _upcoming = 6;
const _playbackCapMs = 45000;

Color _noteColor(int note) => Color(pitchClasses[pitchClass(note)].argb);
const _neutral = Color(0xFF4A4360);

const songLevels = {
  Difficulty.easy: 'The next key glows',
  Difficulty.medium: 'Follow the colored bubbles',
  Difficulty.hard: 'Read the letters',
  Difficulty.expert: 'By ear: hidden notes',
};

class SongPlayPage extends StatefulWidget {
  const SongPlayPage({
    super.key,
    required this.song,
    required this.synth,
    required this.midi,
    this.difficulty = Difficulty.easy,
  });

  final Song song;
  final Difficulty difficulty;
  final Synth synth;
  final MidiInput midi;

  @override
  State<SongPlayPage> createState() => _SongPlayPageState();
}

class _SongPlayPageState extends State<SongPlayPage> with SingleTickerProviderStateMixin {
  final GlobalKey<SparksState> _sparksKey = GlobalKey();
  late final AnimationController _shake =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 380));
  late SongRun _run = SongRun(widget.song);
  late final MissEcho _echo = MissEcho(widget.synth);
  final Set<int> _held = {};
  final List<Timer> _timers = [];
  StreamSubscription<NoteEvent>? _noteSub;
  Timer? _hintTimer;
  Size _laneSize = Size.zero;
  bool _celebrating = false;
  bool _listening = false;
  // Lowest C of the keyboard picture; moves when the octave buttons are used.
  int _base = 48;
  String? _nudge;
  Timer? _nudgeTimer;

  int get _shift => _base - 48;
  bool get _glow => widget.difficulty == Difficulty.easy;
  bool get _colored => !widget.difficulty.atLeast(Difficulty.hard);
  bool get _hidden => widget.difficulty == Difficulty.expert;
  Color _bubbleColor(int note) => _colored ? _noteColor(note) : _neutral;

  late final int _lowest = widget.song.notes.map((n) => n.note).reduce(min);
  late final int _highest = widget.song.notes.map((n) => n.note).reduce(max);
  ({int low, int high})? get _span =>
      _colored ? whiteSpan(_lowest + _shift, _highest + _shift) : null;

  @override
  void initState() {
    super.initState();
    _noteSub = widget.midi.notes.listen(_onNote);
    HardwareKeyboard.instance.addHandler(_onKey);
    _later(const Duration(milliseconds: 700), _hint);
    _armHint();
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    unawaited(_noteSub?.cancel());
    _hintTimer?.cancel();
    _nudgeTimer?.cancel();
    _echo.cancel();
    for (final timer in _timers) {
      timer.cancel();
    }
    for (final note in _held) {
      widget.synth.noteOff(note);
    }
    _shake.dispose();
    super.dispose();
  }

  bool _onKey(KeyEvent event) => handleComputerKey(event, _onNote);

  void _later(Duration delay, void Function() action) {
    _timers.add(Timer(delay, () {
      if (mounted) action();
    }));
  }

  void _armHint() {
    _hintTimer?.cancel();
    _hintTimer = Timer.periodic(_hintEvery, (_) => _hint());
  }

  void _hint() {
    final want = _run.current;
    if (want == null || _listening) return;
    widget.synth.blip(want.note + _shift, velocity: 55, lengthMs: 450);
  }

  void _onNote(NoteEvent event) {
    if (!isGameNote(event.note)) return;
    if (!event.on) {
      widget.synth.noteOff(event.note);
      setState(() => _held.remove(event.note));
      return;
    }
    widget.synth.noteOn(event.note, event.velocity);
    setState(() {
      _held.add(event.note);
      _base = fitBase(_base, event.note);
    });
    final want = _run.current;
    if (want == null || _listening || _celebrating) return;
    final target = want.note + _shift;
    final step = _run.press(event.note, shift: _shift);
    setState(() => _run = step.run);
    switch (step.result) {
      case SongPress.hit:
        _echo.cancel();
        _burst(event.note - _shift, 22);
        _armHint();
        _showNudge(null);
      case SongPress.finished:
        _echo.cancel();
        _burst(event.note - _shift, 40);
        _finish();
        _showNudge(null);
      case SongPress.tooLow:
        _missed(event.note, target, 'Higher!');
      case SongPress.tooHigh:
        _missed(event.note, target, 'Lower!');
      case SongPress.miss:
        _missed(event.note, target, null);
      case SongPress.ignored:
        break;
    }
  }

  void _missed(int note, int target, String? nudge) {
    _shake.forward(from: 0);
    if (nudge != null) _showNudge(nudge);
    _echo.play(note, target);
    _armHint();
  }

  void _showNudge(String? text) {
    _nudgeTimer?.cancel();
    setState(() => _nudge = text);
    if (text != null) {
      _nudgeTimer = Timer(const Duration(milliseconds: 1400), () {
        if (mounted) setState(() => _nudge = null);
      });
    }
  }

  void _burst(int note, int count) {
    final center = _bubbleRect(0, note, note, _laneSize).center;
    _sparksKey.currentState?.burst(center, [_bubbleColor(note), Colors.white], count: count);
  }

  void _finish() {
    _hintTimer?.cancel();
    setState(() => _celebrating = true);
    final rainbow = [for (final pc in whitePitchClasses) Color(pitchClasses[pc].argb)];
    for (var i = 0; i < 4; i++) {
      _later(Duration(milliseconds: 250 * i), () {
        final at = Offset(
          _laneSize.width * (0.2 + 0.6 * Random().nextDouble()),
          _laneSize.height * (0.2 + 0.6 * Random().nextDouble()),
        );
        _sparksKey.currentState?.burst(at, rainbow, count: 45, speed: 620);
      });
    }
    _later(const Duration(milliseconds: 1800), _playBack);
  }

  // Play the melody at its real speed and light the keys as it goes.
  void _playBack() {
    setState(() {
      _celebrating = false;
      _listening = true;
    });
    var endMs = 0;
    for (final n in widget.song.notes) {
      if (n.startMs > _playbackCapMs) break;
      final length = max(80, n.lengthMs - 20);
      _later(Duration(milliseconds: n.startMs), () {
        widget.synth.noteOn(n.note, 85);
        setState(() => _held.add(n.note));
      });
      _later(Duration(milliseconds: n.startMs + length), () {
        widget.synth.noteOff(n.note);
        setState(() => _held.remove(n.note));
      });
      endMs = max(endMs, n.startMs + length);
    }
    _later(Duration(milliseconds: endMs + 600), () => setState(() => _listening = false));
  }

  void _restart() {
    setState(() {
      _run = SongRun(widget.song);
      _nudge = null;
    });
    _later(const Duration(milliseconds: 500), _hint);
    _armHint();
  }

  // Bubble k places after the current note (k = -1 is the one just played).
  Rect _bubbleRect(int k, int note, int currentNote, Size size) {
    final big = min(size.height * 0.55, size.width * 0.3);
    final small = big * 0.5;
    final d = k == 0 ? big : small;
    final x0 = size.width * 0.28;
    final double cx;
    if (k < 0) {
      cx = -big;
    } else if (k == 0) {
      cx = x0;
    } else {
      cx = x0 + big / 2 + 24 + (k - 1) * (small + 14) + small / 2;
    }
    final lift = (note - currentNote) * size.height * 0.03;
    final cy = (size.height / 2 - lift).clamp(d / 2, max(d / 2, size.height - d / 2));
    return Rect.fromCenter(center: Offset(cx, cy.toDouble()), width: d, height: d);
  }

  @override
  Widget build(BuildContext context) {
    final want = _run.current;
    final color = want == null ? Colors.white : _bubbleColor(want.note);
    final total = widget.song.notes.length;
    final ended = want == null && !_listening && !_celebrating;
    return Scaffold(
      backgroundColor: _background,
      body: KeyNav(
        midi: widget.midi,
        picks: ended ? {0: _restart, 2: _playBack, 4: _moreSongs} : const {},
        child: Stack(
          fit: StackFit.expand,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(-0.45, 0),
                  colors: [color.withValues(alpha: 0.22), _background],
                  radius: 0.9,
                ),
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
                    child: Row(
                      children: [
                        const BackButton(),
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(widget.song.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                              const SizedBox(height: 6),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: _run.index / total,
                                  minHeight: 8,
                                  color: color,
                                  backgroundColor: Colors.white12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Flexible(flex: 2, child: KeyboardStatus(midi: widget.midi)),
                      ],
                    ),
                  ),
                  Expanded(child: _buildLane()),
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: SizedBox(
                      height: min(180, MediaQuery.sizeOf(context).height * 0.24),
                      child: PianoStrip(
                        base: _base,
                        span: _span,
                        targetNote: _listening || want == null || !_glow ? null : want.note + _shift,
                        plain: !_colored,
                        held: _held,
                        onNoteOn: (note) => _onNote(NoteEvent(note, 100, on: true)),
                        onNoteOff: (note) => _onNote(NoteEvent(note, 0, on: false)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_celebrating) const WinBanner(),
          ],
        ),
      ),
    );
  }

  void _moreSongs() => Navigator.pop(context);

  Widget _buildLane() {
    return LayoutBuilder(
      builder: (context, constraints) {
        _laneSize = constraints.biggest;
        final want = _run.current;
        return Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            if (want != null)
              AnimatedBuilder(
                animation: _shake,
                builder: (context, child) => Transform.translate(
                  offset: Offset(sin(_shake.value * pi * 6) * 18 * (1 - _shake.value), 0),
                  child: child,
                ),
                child: Stack(children: _bubbles(want.note)),
              )
            else
              Center(child: _endPanel()),
            if (want != null && _nudge != null) _buildNudge(want.note),
            Positioned.fill(child: Sparks(key: _sparksKey)),
          ],
        );
      },
    );
  }

  // "Higher!" / "Lower!" above the current bubble, with an arrow.
  Widget _buildNudge(int note) {
    final rect = _bubbleRect(0, note, note, _laneSize);
    final up = _nudge == 'Higher!';
    final width = min(_laneSize.width, 320.0);
    return Positioned(
      left: (rect.center.dx - width / 2).clamp(0, _laneSize.width - width),
      width: width,
      height: 60,
      top: up ? max(0, rect.top - 64) : min(_laneSize.height - 60, rect.bottom + 4),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, size: 44),
            Text(_nudge!, style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900)),
          ],
        ),
      ),
    );
  }

  List<Widget> _bubbles(int currentNote) {
    final notes = widget.song.notes;
    final first = max(0, _run.index - 1);
    final last = min(notes.length - 1, _run.index + _upcoming);
    return [
      for (var i = last; i >= first; i--)
        _bubble(i, i - _run.index, notes[i].note, currentNote),
    ];
  }

  Widget _bubble(int i, int k, int note, int currentNote) {
    final rect = _bubbleRect(k, note, currentNote, _laneSize);
    final color = _bubbleColor(note);
    final dark = color.computeLuminance() > 0.5;
    return AnimatedPositioned.fromRect(
      key: ValueKey(i),
      duration: _slide,
      curve: Curves.easeOutCubic,
      rect: rect,
      child: AnimatedOpacity(
        duration: _slide,
        opacity: k < 0 ? 0 : (k == 0 ? 1 : 0.85 - 0.08 * k),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: k == 0 ? [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 40)] : null,
          ),
          child: Center(
            child: FractionallySizedBox(
              widthFactor: 0.6,
              heightFactor: 0.6,
              child: FittedBox(
                child: Text(
                  _hidden ? '?' : pitchClasses[pitchClass(note)].name,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: dark ? const Color(0xFF2A2233) : Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _endPanel() {
    if (_celebrating) return const SizedBox.shrink();
    if (_listening) {
      return const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.hearing, size: 72, color: Colors.white70),
          SizedBox(height: 8),
          Text('Listen to your song!', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('You played ${widget.song.title}!',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
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
            FilledButton.tonalIcon(
              onPressed: _playBack,
              icon: const KeyBadge(pc: 2, size: 30),
              label: const Text('Listen again'),
            ),
            OutlinedButton.icon(
              onPressed: _moreSongs,
              icon: const KeyBadge(pc: 4, size: 30),
              label: const Text('More songs'),
            ),
          ],
        ),
      ],
    );
  }
}
