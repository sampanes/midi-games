// Key Rush screen: 3-2-1, then one minute to hit as many keys as possible.
// A board above the keyboard picture shows the key to press now (bottom row)
// and the next ones above it, lined up with the keys, like the tiles on an
// arcade piano. Each hit moves the tiles down a row.
//
// Easy shows one octave and uses only its four middle white keys; every hit
// plays the next note of a song, whatever key was pressed, so the melody
// comes out. A wrong key makes no sound and costs nothing.
// Real plays a song's own notes on their own keys: each key sounds as
// itself, and a wrong key plays itself and then the right note and freezes
// scoring for that moment.
//
// At the end: score, best score this session, and the song name. Keys at
// the end: C plays again, E goes back to the menu.

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
const _starGold = Color(0xFFFFD84A);
const _countdownStepMs = 700;

const rushLevels = {
  Difficulty.easy: 'Four keys in the middle; a song plays as you hit them',
  Difficulty.medium: "A song's real notes on the real keys",
};
const rushLabels = {Difficulty.medium: 'Real'};

// Best score per level, for this session.
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

  // Easy, or anything else for Real.
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
  final GlobalKey _boardKey = GlobalKey();
  late final AnimationController _slide =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 140), value: 1);
  late final AnimationController _shake =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
  late final MissEcho _echo = MissEcho(widget.synth);
  final List<Timer> _timers = [];
  StreamSubscription<NoteEvent>? _noteSub;
  Timer? _clock;

  RushState _state = const RushState(upcoming: []);
  RushFeed _feed = SongRushFeed(const [60]);
  _Phase _phase = _Phase.countdown;
  int _count = 3;
  bool _canPick = false;
  bool _newBest = false;
  int _base = 48;
  final Set<int> _held = {};

  List<Song> _songs = const [];
  Song _song = scaleSong;
  int _songIndex = 0;

  Difficulty get _level => widget.difficulty;
  bool get _real => _level != Difficulty.easy;

  // Real: the keyboard's octave buttons move everything by whole octaves.
  int get _shift => _real ? _base - 48 : 0;

  ({int low, int high}) get _span {
    if (!_real) return (low: rushEasyLow, high: rushEasyHigh);
    final notes = _song.notes.map((n) => n.note);
    return whiteSpan(notes.reduce(min) + _shift, notes.reduce(max) + _shift);
  }

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
    _slide.dispose();
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
    _state = const RushState(upcoming: []);
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
      _song = _songs.isEmpty ? scaleSong : _songs[_random.nextInt(_songs.length)];
      _feed = _real
          ? SongRushFeed([for (final n in _song.notes) n.note])
          : EasyRushFeed(_random);
      _state = RushState.start(_feed);
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
      if (_real) _base = fitBase(_base, event.note);
    });
    if (_phase != _Phase.playing) {
      widget.synth.noteOn(event.note, event.velocity);
      return;
    }
    final target = _state.target;
    final step = pressRush(_state, event.note - _shift, _feed, exact: _real, freeze: _real);
    setState(() => _state = step.state);
    switch (step.result) {
      case RushResult.hit:
        _echo.cancel();
        if (_real) {
          widget.synth.noteOn(event.note, event.velocity);
        } else {
          _smash();
        }
        _slide.forward(from: 0);
        _sparksKey.currentState?.burst(
          _tileCenter(target + _shift),
          [Color(pitchClasses[pitchClass(target)].argb), _starGold],
          count: 16,
          speed: 380,
        );
      case RushResult.miss:
        _shake.forward(from: 0);
        if (_real) {
          widget.synth.noteOn(event.note, event.velocity);
          _echo.play(event.note, target + _shift);
        }
      case RushResult.frozen || RushResult.over:
        if (_real) widget.synth.noteOn(event.note, event.velocity);
    }
  }

  // Easy: the next note of the song instead of the key pressed.
  void _smash() {
    final notes = _song.notes;
    final n = notes[_songIndex % notes.length];
    _songIndex++;
    widget.synth.blip(n.note, velocity: 100, lengthMs: n.lengthMs.clamp(150, 700));
  }

  // Middle of the bottom-row tile for [note], in the sparks' coordinates.
  Offset _tileCenter(int note) {
    final board = _boardKey.currentContext?.findRenderObject() as RenderBox?;
    final sparks = _sparksKey.currentContext?.findRenderObject() as RenderBox?;
    if (board == null || sparks == null) return Offset.zero;
    final span = _span;
    final column = keyColumn(span.low, span.high, board.size.width, note);
    final rowHeight = board.size.height / rushRows;
    final local = Offset(column.left + column.width / 2, board.size.height - rowHeight / 2);
    return sparks.globalToLocal(board.localToGlobal(local));
  }

  // Easy shows one octave, so a key pressed in another octave lights its
  // twin there.
  Set<int> get _shownHeld =>
      _real ? _held : {for (final note in _held) rushEasyLow + pitchClass(note)};

  @override
  Widget build(BuildContext context) {
    final playing = _phase == _Phase.playing;
    final span = _span;
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
                    child: _phase == _Phase.done
                        ? Center(child: _buildEnd())
                        : Padding(
                            padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                _buildBoard(span, playing),
                                if (_phase == _Phase.countdown) Center(child: _buildCountdown()),
                              ],
                            ),
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
                          span: span,
                          targetNote: playing && !_state.frozen ? _state.target + _shift : null,
                          held: _shownHeld,
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

  Widget _buildBoard(({int low, int high}) span, bool playing) {
    return AnimatedBuilder(
      animation: Listenable.merge([_slide, _shake]),
      builder: (context, _) {
        final s = _shake.value;
        return Transform.translate(
          offset: Offset(sin(s * pi * 6) * 18 * (1 - s), 0),
          child: CustomPaint(
            key: _boardKey,
            size: Size.infinite,
            painter: _BoardPainter(
              span: span,
              notes: playing ? [for (final n in _state.upcoming) n + _shift] : const [],
              lanes: _real ? null : rushEasyKeys,
              slide: Curves.easeOut.transform(_slide.value),
              frozen: _state.frozen,
            ),
          ),
        );
      },
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
          Text(_real ? 'You played ${_song.title}!' : 'You smashed out ${_song.title}!',
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

// The tile board: a grid of dim cells over the white keys, and a lit tile
// for each upcoming key (bottom row = press now). [slide] runs 0 to 1 after
// a hit, moving the tiles down from the row they were on.
class _BoardPainter extends CustomPainter {
  _BoardPainter({
    required this.span,
    required this.notes,
    required this.lanes,
    required this.slide,
    required this.frozen,
  });

  final ({int low, int high}) span;
  final List<int> notes;

  // Keys whose columns are a little lighter (Easy's four keys); null for all.
  final List<int>? lanes;
  final double slide;
  final bool frozen;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    final rowHeight = size.height / rushRows;
    final gap = min(6.0, rowHeight * 0.06);
    final fill = Paint();
    for (var note = span.low; note <= span.high; note++) {
      if (!pitchClasses[pitchClass(note)].white) continue;
      final column = keyColumn(span.low, span.high, size.width, note);
      final lane = lanes == null || lanes!.contains(note);
      fill.color = lane ? const Color(0x1FFFFFFF) : const Color(0x0AFFFFFF);
      for (var row = 0; row < rushRows; row++) {
        final rect = Rect.fromLTWH(column.left, row * rowHeight, column.width, rowHeight);
        canvas.drawRRect(RRect.fromRectAndRadius(rect.deflate(gap), const Radius.circular(8)), fill);
      }
    }

    for (var row = notes.length - 1; row >= 0; row--) {
      final note = notes[row];
      if (note < span.low || note > span.high) continue;
      final info = pitchClasses[pitchClass(note)];
      final column = keyColumn(span.low, span.high, size.width, note);
      final top = size.height - (row + 1 + (1 - slide)) * rowHeight;
      final rect = Rect.fromLTWH(column.left, top, column.width, rowHeight).deflate(gap);
      final now = row == 0;
      final color = Color(info.argb).withValues(alpha: frozen ? 0.3 : (now ? 1 : 0.75 - 0.15 * row));
      fill.color = color;
      final tile = RRect.fromRectAndRadius(rect, const Radius.circular(8));
      canvas.drawRRect(tile, fill);
      if (now && !frozen) {
        canvas.drawRRect(
          tile.deflate(1.5),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..color = Colors.white,
        );
      }
      final dark = Color(info.argb).computeLuminance() > 0.5;
      final text = TextPainter(
        text: TextSpan(
          text: info.name,
          style: TextStyle(
            // Two letters (F#) on a narrow black-key tile need a smaller size.
            fontSize: min(rect.width * (info.name.length > 1 ? 0.34 : 0.5), rect.height * 0.45),
            fontWeight: FontWeight.w900,
            color: (dark ? const Color(0xFF2A2233) : Colors.white)
                .withValues(alpha: frozen ? 0.4 : 1),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      text.paint(canvas, rect.center - Offset(text.width / 2, text.height / 2));
    }
  }

  @override
  bool shouldRepaint(_BoardPainter old) => true;
}
