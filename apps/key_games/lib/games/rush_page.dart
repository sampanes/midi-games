// Key Rush screen: 3-2-1, then one minute to hit as many target keys as
// possible. Song smash: every hit plays the next note of a real song instead
// of the key pressed, so a fast player hears the melody come out. A wrong key
// plays itself and then the right note, and (above Easy) freezes scoring for
// that moment. At the end: score, best score this session, and the song name.
//
// Difficulty: Easy glows the keys and never freezes; Medium freezes; Hard
// uses all twelve notes on a plain keyboard (read the letter); Expert shows
// the letter alone, with no color.
//
// Keys at the end: C plays again, E goes back to the menu.

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../audio/miss_echo.dart';
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
import 'rush_rules.dart';

const _background = Color(0xFF14111C);
const _letterOnly = Color(0xFF4A4360);
const _starGold = Color(0xFFFFD84A);
const _countdownStepMs = 700;

const rushLevels = {
  Difficulty.easy: 'The keys glow, no penalty',
  Difficulty.medium: 'Wrong keys freeze you',
  Difficulty.hard: 'Read the letter, black keys too',
  Difficulty.expert: 'Letter only, no colors',
};

// Played when no songs are bundled: up and down the C major scale.
const _scaleSong = Song('Scale', [
  SongNote(60, 0, 300), SongNote(62, 0, 300), SongNote(64, 0, 300), SongNote(65, 0, 300),
  SongNote(67, 0, 300), SongNote(69, 0, 300), SongNote(71, 0, 300), SongNote(72, 0, 500),
  SongNote(71, 0, 300), SongNote(69, 0, 300), SongNote(67, 0, 300), SongNote(65, 0, 300),
  SongNote(64, 0, 300), SongNote(62, 0, 300), SongNote(60, 0, 500),
]);

// Best score per difficulty, for this session.
final Map<Difficulty, int> _best = {};

enum _Phase { countdown, playing, done }

class RushPage extends StatefulWidget {
  const RushPage({
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
  State<RushPage> createState() => _RushPageState();
}

class _RushPageState extends State<RushPage> with TickerProviderStateMixin {
  late final Random _random = widget.random ?? Random();
  final GlobalKey<SparksState> _sparksKey = GlobalKey();
  final GlobalKey _circleKey = GlobalKey();
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
  late final AnimationController _shake =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
  late final MissEcho _echo = MissEcho(widget.synth);
  final List<Timer> _timers = [];
  StreamSubscription<NoteEvent>? _noteSub;
  Timer? _clock;

  late RushState _state = RushState.start(_random, _choices);
  _Phase _phase = _Phase.countdown;
  int _count = 3;
  bool _canPick = false;
  bool _newBest = false;
  int _base = 48;
  final Set<int> _held = {};

  List<Song> _songs = const [];
  Song _song = _scaleSong;
  int _songIndex = 0;

  Difficulty get _level => widget.difficulty;
  bool get _glow => !_level.atLeast(Difficulty.hard);
  bool get _plain => _level.atLeast(Difficulty.hard);
  bool get _colored => _level != Difficulty.expert;
  bool get _freeze => _level != Difficulty.easy;
  List<int> get _choices => _plain ? allPitchClasses : whitePitchClasses;

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
    _resetRound();
    _countdown();
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    unawaited(_noteSub?.cancel());
    _clock?.cancel();
    _echo.cancel();
    for (final timer in _timers) {
      timer.cancel();
    }
    for (final note in _held) {
      widget.synth.noteOff(note);
    }
    _pulse.dispose();
    _shake.dispose();
    super.dispose();
  }

  bool _onKey(KeyEvent event) => handleComputerKey(event, _onNote);

  void _later(Duration delay, void Function() action) {
    _timers.add(Timer(delay, () {
      if (mounted) action();
    }));
  }

  void _resetRound() {
    _clock?.cancel();
    _echo.cancel();
    _state = RushState.start(_random, _choices);
    _phase = _Phase.countdown;
    _count = 3;
    _canPick = false;
    _newBest = false;
    _songIndex = 0;
  }

  void _startRound() {
    setState(_resetRound);
    _countdown();
  }

  // 3, 2, 1 with a beep each, then GO and the clock starts.
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
      _song = _songs.isEmpty ? _scaleSong : _songs[_random.nextInt(_songs.length)];
    });
    _clock = Timer.periodic(const Duration(milliseconds: rushTickMs), (_) {
      if (!mounted) return;
      setState(() => _state = rushTick(_state));
      if (_state.over) _finish();
    });
  }

  void _finish() {
    _clock?.cancel();
    _echo.cancel();
    final best = _best[_level] ?? 0;
    setState(() {
      _phase = _Phase.done;
      _newBest = _state.score > best;
      if (_newBest) _best[_level] = _state.score;
    });
    widget.synth.tune([72, 76, 79, 84], stepMs: 120, lengthMs: 220);
    // A moment before the end keys work, so the last hits do not restart it.
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
    if (_phase != _Phase.playing) {
      widget.synth.noteOn(event.note, event.velocity);
      return;
    }
    final target = _state.target;
    final step = pressRush(_state, event.note, _random, _choices, freeze: _freeze);
    setState(() => _state = step.state);
    switch (step.result) {
      case RushResult.hit:
        _echo.cancel();
        _smash();
        _pulse.forward(from: 0);
        _sparksKey.currentState?.burst(
          _circleCenter(),
          [_colored ? Color(pitchClasses[target].argb) : Colors.white, _starGold],
          count: 16,
          speed: 380,
        );
      case RushResult.miss:
        widget.synth.noteOn(event.note, event.velocity);
        _shake.forward(from: 0);
        _echo.play(event.note, nearestOfClass(event.note, target));
      case RushResult.frozen || RushResult.over:
        widget.synth.noteOn(event.note, event.velocity);
    }
  }

  // Song smash: the next note of the song instead of the key pressed.
  void _smash() {
    final notes = _song.notes;
    final n = notes[_songIndex % notes.length];
    _songIndex++;
    widget.synth.blip(n.note, velocity: 100, lengthMs: n.lengthMs.clamp(150, 700));
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
    final playing = _phase == _Phase.playing;
    return Scaffold(
      backgroundColor: _background,
      body: KeyNav(
        midi: widget.midi,
        picks: _phase == _Phase.done && _canPick
            ? {0: _startRound, 4: () => Navigator.maybePop(context)}
            : const {},
        child: Stack(
          fit: StackFit.expand,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [
                    (playing ? color : _letterOnly).withValues(alpha: _state.frozen ? 0.1 : 0.3),
                    _background,
                  ],
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
                        if (Navigator.canPop(context)) const BackButton(),
                        const Icon(Icons.star_rounded, color: _starGold, size: 40),
                        const SizedBox(width: 4),
                        Text('${_state.score}',
                            style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900)),
                        const SizedBox(width: 16),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: _state.timeLeft,
                              minHeight: 14,
                              color: _state.timeLeft < 0.17 ? const Color(0xFFFF3B3B) : _starGold,
                              backgroundColor: Colors.white12,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Flexible(child: KeyboardStatus(midi: widget.midi)),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: switch (_phase) {
                        _Phase.countdown => _buildCountdown(),
                        _Phase.playing => _buildCircle(target, color),
                        _Phase.done => _buildEnd(),
                      },
                    ),
                  ),
                  Text(
                    _phase == _Phase.countdown ? 'Get ready!' : 'Song: ${_song.title}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white54, fontSize: 16),
                  ),
                  // Hidden at the end, so the end choices fit a landscape phone.
                  if (_phase != _Phase.done)
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: SizedBox(
                        height: min(180, MediaQuery.sizeOf(context).height * 0.24),
                        child: PianoStrip(
                          base: _base,
                          target: playing && _glow && !_state.frozen ? _state.target : null,
                          plain: _plain,
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

  Widget _buildCountdown() {
    return TweenAnimationBuilder<double>(
      key: ValueKey(_count),
      tween: Tween(begin: 1.6, end: 1),
      duration: const Duration(milliseconds: 300),
      builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
      child: Text(
        '$_count',
        style: const TextStyle(fontSize: 160, fontWeight: FontWeight.w900, color: _starGold),
      ),
    );
  }

  Widget _buildCircle(PitchClassInfo target, Color color) {
    final dark = _colored && color.computeLuminance() > 0.5;
    return LayoutBuilder(
      builder: (context, constraints) {
        final diameter = min(constraints.maxWidth, constraints.maxHeight) * 0.68;
        return AnimatedBuilder(
          animation: Listenable.merge([_pulse, _shake]),
          builder: (context, child) {
            final p = _pulse.value;
            final s = _shake.value;
            return Transform.translate(
              offset: Offset(sin(s * pi * 6) * 22 * (1 - s), 0),
              child: Transform.scale(scale: 1 + 0.12 * sin(p * pi), child: child),
            );
          },
          child: Opacity(
            opacity: _state.frozen ? 0.35 : 1,
            child: Container(
              key: _circleKey,
              width: diameter,
              height: diameter,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 50)],
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Padding(
                  padding: EdgeInsets.all(diameter * 0.12),
                  child: Text(
                    _state.frozen ? 'Oops!' : target.name,
                    style: TextStyle(
                      fontSize: diameter * (_state.frozen ? 0.2 : 0.42),
                      fontWeight: FontWeight.w900,
                      color: dark ? const Color(0xFF2A2233) : Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEnd() {
    final best = _best[_level] ?? 0;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text("Time's up!", style: TextStyle(fontSize: 36, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Text('${_state.score} keys',
              style: const TextStyle(fontSize: 56, fontWeight: FontWeight.w900, color: _starGold)),
          Text(
            _newBest ? 'New best!' : 'Best: $best',
            style: const TextStyle(fontSize: 22, color: Colors.white70),
          ),
          const SizedBox(height: 4),
          Text('You smashed out ${_song.title}!',
              textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, color: Colors.white70)),
          const SizedBox(height: 20),
          Wrap(
            spacing: 16,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: _startRound,
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
