// Song Memory screen: a real tune learned by heart. The game plays a bit of
// the tune in the tune's own rhythm (the keys light up and a big bubble
// shows each note), then the player plays it back from memory. Played back
// right, it grows; a whole line known, the next line starts (see
// memory_rules.dart for the lines and the levels).
//
// Easy and Medium grow a line one note at a time. On Easy a wrong key makes
// the right key glow and the player carries on; on Medium the game plays the
// bit again. Waiting a while does the same on both, at no cost. Hard and
// Expert hear a whole new line and play the song from the top up to it,
// with three hearts for each line; Expert is by ear, the keys and the bubble
// stay dark while the game plays. The letter counts, in any octave.
//
// The dots count what is to be played back, one per note with a gap between
// lines, and fill as it is played. At the end the whole song plays at its
// real speed with its band, and up to three stars are kept per song and
// level. The end buttons are picked with keys too: C again, D listen, E more
// songs, F the next song of the list.
//
// Input: the keyboard and the computer keys, through the key router, plus
// touching the keyboard picture.

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../app/services.dart';
import '../app/settings.dart';
import '../app/theme.dart';
import '../app/timer_group.dart';
import '../audio/synth.dart';
import '../midi/midi_input.dart';
import '../songs/song.dart';
import '../songs/song_queue.dart';
import '../widgets/game_page.dart';
import '../widgets/key_badge.dart';
import '../widgets/piano_strip.dart';
import '../widgets/sparks.dart';
import '../widgets/win_banner.dart';
import 'color_keys_rules.dart';
import 'difficulty.dart';
import 'memory_rules.dart';

const _firstDelay = Duration(milliseconds: 1200);
const _leadIn = 300;
const _growDelay = Duration(milliseconds: 900);
const _lineDelay = Duration(milliseconds: 1700);
const _missDelay = Duration(milliseconds: 1200);
const _idle = Duration(seconds: 7);
const _playbackCapMs = 45000;

const memoryLevelsText = {
  Difficulty.easy: 'One more note each time, and the keys help',
  Difficulty.medium: 'One more note each time, the whole song',
  Difficulty.hard: 'A whole line at a time, from the top',
  Difficulty.expert: 'A line at a time, by ear',
};

// Where the most stars won on [song] at [level] are kept (Settings.best).
String memoryStarsKey(Difficulty level, Song song) => 'stars.memory.${level.name}.${song.title}';

enum _Phase { watching, turn, between, done }

class MemoryPage extends StatefulWidget {
  const MemoryPage({super.key, required this.song, this.difficulty = Difficulty.easy});

  final Song song;
  final Difficulty difficulty;

  @override
  State<MemoryPage> createState() => _MemoryPageState();
}

class _MemoryPageState extends State<MemoryPage> with SingleTickerProviderStateMixin {
  // Looked up when the page opens: a page left before it made a sound must
  // not look it up while it closes.
  late final Synth _synth;
  late final Settings _settings = AppServices.of(context).settings;
  late final MemoryLevel _rules = memoryLevels[widget.difficulty]!;
  late final List<SongLine> _lines = songLines(widget.song);
  late final double _stretch = memoryStretch(widget.song, _rules);
  late final AnimationController _shake =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
  final GlobalKey<SparksState> _sparksKey = GlobalKey();
  final GlobalKey _bubbleKey = GlobalKey();
  final TimerGroup _timers = TimerGroup();
  Timer? _idleTimer;
  Timer? _flashTimer;

  late MemoryState _state = MemoryState.start(_rules, _lines);
  _Phase _phase = _Phase.between;
  String _status = '';

  // The note in the big bubble, and whether it is lit: the game's note as it
  // plays, or the player's last right one.
  int? _bubble;
  bool _lit = false;

  // The letter that glows on the keyboard picture: help after a wrong key.
  int? _help;

  // Keys the player holds, and keys the game is playing.
  final Set<int> _held = {};
  final Set<int> _sounding = {};

  bool _won = false;
  bool _celebrating = false;
  bool _listening = false;
  bool _canPick = false;
  int _stars = 0;

  // Lowest C of the keyboard picture; moves when the octave buttons are used.
  int _base = 48;

  int get _shift => _base - 48;
  int get _goal => memoryGoal(_rules, _lines);
  late final int _lowest = widget.song.notes.map((n) => n.note).reduce(min);
  late final int _highest = widget.song.notes.map((n) => n.note).reduce(max);

  // The levels for small children picture just the song's keys. So does
  // every level with no keyboard connected, where the picture is the
  // keyboard and a song can be wider than the one octave it shows otherwise.
  ({int low, int high})? get _span => _rules.byNote || !AppServices.hasKeyboard(context)
      ? whiteSpan(_lowest + _shift, _highest + _shift)
      : null;

  String get _watchText => _rules.shown ? 'Watch and listen' : 'Listen';

  @override
  void initState() {
    super.initState();
    _synth = AppServices.of(context).synth;
    _status = _watchText;
    // The first notes once the synth has had time to load.
    _later(_firstDelay, _playTurn);
  }

  @override
  void dispose() {
    _stopAll();
    for (final note in _held) {
      _synth.noteOff(note);
    }
    _shake.dispose();
    super.dispose();
  }

  // Drops everything the page meant to do later, and what it is playing.
  void _stopAll() {
    _idleTimer?.cancel();
    _flashTimer?.cancel();
    _timers.cancelAll();
    _synth.stopBand();
    for (final note in _sounding) {
      _synth.noteOff(note);
    }
    _sounding.clear();
  }

  void _later(Duration delay, void Function() action) {
    _timers.schedule(delay, () {
      if (mounted) action();
    });
  }

  // Plays [notes] (see memoryPlayback) on the keys, [leadMs] from now, and
  // says when the last of them has ended.
  int _play(List<PlayedNote> notes, {int leadMs = 0, bool bubble = true}) {
    var end = leadMs;
    for (final n in notes) {
      final note = n.note + _shift;
      _later(Duration(milliseconds: leadMs + n.atMs), () {
        _synth.noteOn(note, 85);
        setState(() {
          _sounding.add(note);
          if (bubble) {
            _bubble = n.note;
            _lit = true;
          }
        });
      });
      _later(Duration(milliseconds: leadMs + n.atMs + n.lengthMs), () {
        _synth.noteOff(note);
        setState(() {
          _sounding.remove(note);
          if (bubble) _lit = false;
        });
      });
      end = max(end, leadMs + n.atMs + n.lengthMs);
    }
    return end;
  }

  // The game plays what the player is about to play back, in the song's
  // rhythm, then it is the player's turn.
  void _playTurn() {
    _stopAll();
    final listen = memoryListen(_state, _rules, _lines);
    setState(() {
      _phase = _Phase.watching;
      _lit = false;
      _help = null;
      _status = _watchText;
    });
    final end = _play(
      memoryPlayback(widget.song, listen.start, listen.end, _stretch),
      leadMs: _leadIn,
    );
    _later(Duration(milliseconds: end + 150), () {
      setState(() {
        _phase = _Phase.turn;
        _lit = false;
        // Earlier lines were not played again: say where to start.
        _status = listen.start > 0 && _rules.fromTop ? 'From the top!' : 'Your turn!';
      });
      _armIdle();
    });
  }

  // A player who waits gets help for free: the glowing key on Easy, the bit
  // played again on Medium. With hearts, waiting does nothing.
  void _armIdle() {
    _idleTimer?.cancel();
    if (_rules.hearts != null) return;
    _idleTimer = Timer(_idle, () {
      if (!mounted || _phase != _Phase.turn) return;
      if (_rules.helps) {
        _showHelp();
      } else {
        setState(() => _state = replayMemory(_state));
        _playTurn();
      }
    });
  }

  void _showHelp() {
    final want = memoryWanted(_state, _rules, widget.song, _lines);
    if (want == null) return;
    setState(() {
      _help = pitchClass(want);
      _status = 'Try the glowing key';
    });
  }

  void _restart() {
    _stopAll();
    setState(() {
      _state = MemoryState.start(_rules, _lines);
      _phase = _Phase.between;
      _bubble = null;
      _lit = false;
      _help = null;
      _won = false;
      _celebrating = false;
      _listening = false;
      _canPick = false;
      _status = _watchText;
    });
    _later(const Duration(milliseconds: 600), _playTurn);
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
      _held.add(event.note);
      _base = fitBase(_base, event.note);
    });
    if (_phase == _Phase.turn) _answer(event.note);
  }

  void _answer(int note) {
    final step = pressMemory(_state, note, _rules, widget.song, _lines);
    if (step.result == MemoryResult.ignored) return;
    final line = _state.line;
    setState(() {
      _state = step.state;
      if (step.result != MemoryResult.miss && step.result != MemoryResult.over) {
        _bubble = note - _shift;
        _lit = true;
        _help = null;
      }
    });
    switch (step.result) {
      case MemoryResult.hit:
        setState(() => _status = 'Your turn!');
        // The bubble shows the right note for a moment.
        _flashTimer?.cancel();
        _flashTimer = Timer(const Duration(milliseconds: 260), () {
          if (mounted && _phase == _Phase.turn) setState(() => _lit = false);
        });
        _armIdle();
      case MemoryResult.grown:
        _between('Yes!');
        _sparkle(note, 26);
        _later(_growDelay, _next);
      case MemoryResult.lineDone:
        _between('Line ${line + 1}: got it!');
        _sparkle(note, 60);
        _later(const Duration(milliseconds: 450),
            () => _synth.tune([84, 91], stepMs: 70, lengthMs: 150));
        _later(_lineDelay, _next);
      case MemoryResult.won:
        _finish(note);
      case MemoryResult.miss:
        _shake.forward(from: 0);
        if (_rules.helps) {
          _showHelp();
          _armIdle();
        } else {
          _between('Listen again');
          setState(() => _lit = false);
          _later(_missDelay, _playTurn);
        }
      case MemoryResult.over:
        _shake.forward(from: 0);
        _idleTimer?.cancel();
        setState(() {
          _phase = _Phase.done;
          _lit = false;
        });
        _later(const Duration(milliseconds: 1500), () => setState(() => _canPick = true));
      case MemoryResult.ignored:
        break;
    }
  }

  void _between(String status) {
    _idleTimer?.cancel();
    setState(() {
      _phase = _Phase.between;
      _status = status;
    });
  }

  void _next() {
    setState(() => _state = nextMemory(_state, _rules, _lines));
    _playTurn();
  }

  void _sparkle(int note, int count) {
    _sparksKey.currentState
        ?.burst(_bubbleCenter(), [noteColor(note), Colors.white, AppColors.starGold], count: count);
  }

  Offset _bubbleCenter() {
    final bubble = _bubbleKey.currentContext?.findRenderObject() as RenderBox?;
    final sparks = _sparksKey.currentContext?.findRenderObject() as RenderBox?;
    if (bubble == null || sparks == null) return Offset.zero;
    return sparks.globalToLocal(bubble.localToGlobal(bubble.size.center(Offset.zero)));
  }

  // The song is known: stars, a party, then the whole song with its band.
  void _finish(int note) {
    _idleTimer?.cancel();
    final stars = memoryStars(_state.misses, _rules, _lines);
    setState(() {
      _phase = _Phase.done;
      _won = true;
      _celebrating = true;
      _stars = stars;
    });
    _settings.recordBest(memoryStarsKey(widget.difficulty, widget.song), stars);
    final rainbow = [for (final pc in whitePitchClasses) pitchColor(pc)];
    final size = MediaQuery.sizeOf(context);
    final random = Random();
    for (var i = 0; i < 4; i++) {
      _later(Duration(milliseconds: 250 * i), () {
        final at = Offset(
          size.width * (0.15 + 0.7 * random.nextDouble()),
          size.height * (0.2 + 0.5 * random.nextDouble()),
        );
        _sparksKey.currentState?.burst(at, rainbow, count: 45, speed: 620);
      });
    }
    _later(const Duration(milliseconds: 1800), _playBack);
  }

  // The whole song at its real speed, with its band, the keys lighting up.
  void _playBack() {
    _stopAll();
    setState(() {
      _celebrating = false;
      _listening = true;
      _canPick = false;
    });
    final song = widget.song;
    final first = song.notes.first.startMs;
    final notes = [
      for (final n in song.notes)
        if (n.startMs - first <= _playbackCapMs)
          (note: n.note, atMs: n.startMs - first, lengthMs: max(80, n.lengthMs - 20)),
    ];
    // A song without a clock (the built-in scale) plays in even steps.
    final timed = notes.length < 2 || notes.last.atMs > 0;
    final end = _play(
      timed ? notes : memoryPlayback(song, 0, song.notes.length, 1),
      bubble: false,
    );
    if (timed) {
      for (final n in song.backing) {
        if (n.startMs - first > _playbackCapMs || n.startMs < first) continue;
        _later(Duration(milliseconds: n.startMs - first),
            () => _synth.band(n.note + _shift, lengthMs: n.lengthMs));
      }
    }
    _later(Duration(milliseconds: end + 600), () {
      setState(() {
        _listening = false;
        _canPick = true;
      });
    });
  }

  void _moreSongs() => Navigator.pop(context);

  @override
  Widget build(BuildContext context) {
    final done = _phase == _Phase.done;
    final ended = done && _canPick && !_listening && !_celebrating;
    final queue = SongQueue.of(context);
    final watching = _phase == _Phase.watching;
    // By ear: nothing of the game's own playing is shown.
    final dark = watching && !_rules.shown;
    final bubble = _bubble;
    final tint = bubble == null || dark || !_lit ? AppColors.mystery : noteColor(bubble);
    final linesDone = _won ? _goal : _state.line;
    return GamePage(
      picks: ended
          ? {
              0: _restart,
              2: _playBack,
              4: _moreSongs,
              if (queue != null) nextSongPc: () => queue.openNext(context),
            }
          : const {},
      navigationLabels: {
        0: 'Play again', 2: 'Listen', 4: 'More songs',
        if (queue != null) nextSongPc: 'Next song',
      },
      onNote: _onNote,
      backdrop: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        decoration: BoxDecoration(
          gradient: RadialGradient(
            colors: [tint.withValues(alpha: 0.3), AppColors.background],
            radius: 0.9,
          ),
        ),
      ),
      header: _header(linesDone),
      body: done ? Center(child: _endPanel()) : _buildBoard(dark),
      footer: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: SizedBox(
            height: pianoStripHeight(context, design: 150, share: 0.22),
            child: PianoStrip(
              base: _base,
              span: _span,
              target: _phase == _Phase.turn ? _help : null,
              plain: !_rules.byNote,
              held: {..._held, if (!dark) ..._sounding},
              onNoteOn: (note) => _onNote(NoteEvent(note, 100, on: true)),
              onNoteOff: (note) => _onNote(NoteEvent(note, 0, on: false)),
            ),
          ),
        ),
      ],
      overlays: [
        Positioned.fill(child: IgnorePointer(child: Sparks(key: _sparksKey))),
        if (_celebrating) const WinBanner(),
      ],
    );
  }

  // The song's name over a bar of the lines learned, then the hearts.
  List<Widget> _header(int linesDone) {
    final scale = uiScale(context);
    final hearts = _rules.hearts;
    return [
      Expanded(
        flex: 2,
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
                value: _goal == 0 ? 0 : linesDone / _goal,
                minHeight: 8 * scale,
                color: AppColors.starGold,
                backgroundColor: Colors.white12,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(width: 12),
      if (hearts != null)
        for (var i = 0; i < hearts; i++)
          Icon(Icons.favorite_rounded,
              size: 28 * scale,
              color: i < _state.heartsLeft(_rules) ? AppColors.red : Colors.white24),
    ];
  }

  // The status line, the bubble, which line it is, and the dots.
  Widget _buildBoard(bool dark) {
    final scale = uiScale(context);
    final bubble = _bubble;
    final span = memorySpan(_state, _rules, _lines);
    final notes = widget.song.notes;
    return Padding(
      padding: EdgeInsets.fromLTRB(12 * scale, 0, 12 * scale, 4 * scale),
      child: Column(
        children: [
          Text(
            _status,
            style: TextStyle(
              fontSize: 26 * scale,
              fontWeight: FontWeight.w900,
              color: _phase == _Phase.turn ? AppColors.starGold : Colors.white70,
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = min(
                  constraints.maxWidth * 0.6,
                  min(constraints.maxHeight - 12 * scale, 230 * scale),
                );
                return AnimatedBuilder(
                  animation: _shake,
                  builder: (context, child) => Transform.translate(
                    offset: Offset(sin(_shake.value * pi * 6) * 22 * (1 - _shake.value), 0),
                    child: child,
                  ),
                  child: Center(
                    child: _Bubble(
                      key: _bubbleKey,
                      size: max(0, size),
                      color: bubble == null || dark ? AppColors.plain : noteColor(bubble),
                      label: bubble == null || dark ? '?' : pitchClasses[pitchClass(bubble)].name,
                      lit: _lit,
                    ),
                  ),
                );
              },
            ),
          ),
          Text(
            'Line ${_state.line + 1} of $_goal',
            style: TextStyle(fontSize: 15 * scale, color: Colors.white60),
          ),
          SizedBox(height: 4 * scale),
          _Dots(
            size: 16 * scale,
            dots: [
              for (var i = span.start; i < span.end; i++)
                (
                  color: _filled(i - span.start) ? noteColor(notes[i].note) : null,
                  // A gap where a line of the song ends.
                  gap: i > span.start && _lines.any((line) => line.start == i),
                  small: i < _lines[_state.line].start,
                ),
            ],
          ),
        ],
      ),
    );
  }

  // True when dot [k] of the turn is filled: its note has been played back.
  // While the game plays the dots stay empty: no peeking.
  bool _filled(int k) => _phase != _Phase.watching && k < _state.at;

  // The end panel is chrome: phone-sized text grown with the screen.
  Widget _endPanel() {
    if (_celebrating) return const SizedBox.shrink();
    final s = uiScale(context);
    if (_listening) {
      return ScaledChrome(
        scale: s,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.hearing, size: 72 * s, color: Colors.white70),
            SizedBox(height: 8 * s),
            const Text('Listen to your song!',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
          ],
        ),
      );
    }
    final title = widget.song.title;
    final learned = _state.line;
    return ScaledChrome(
      scale: s,
      child: SingleChildScrollView(
        padding: EdgeInsets.all(12 * s),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              !_won
                  ? 'Out of hearts!'
                  : _goal < _lines.length
                      ? 'You know the start of $title!'
                      : 'You know $title by heart!',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
            ),
            if (_won)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < songStars; i++)
                    Icon(Icons.star_rounded,
                        size: 52 * s, color: i < _stars ? AppColors.starGold : Colors.white24),
                ],
              )
            else
              Text(
                learned == 0
                    ? 'Listen to the line, then play it back'
                    : 'You learned $learned of $_goal lines',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18, color: Colors.white70),
              ),
            SizedBox(height: 12 * s),
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
                FilledButton.tonalIcon(
                  onPressed: _playBack,
                  style: keyButtonStyle(s),
                  icon: KeyBadge(pc: 2, size: 30 * s),
                  label: const Text('Listen'),
                ),
                OutlinedButton.icon(
                  onPressed: _moreSongs,
                  style: keyButtonStyle(s),
                  icon: KeyBadge(pc: 4, size: 30 * s),
                  label: const Text('More songs'),
                ),
                NextSongButton(scale: s),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// The big bubble: the note sounding now, in its color with its letter; dim
// between notes, and a plain "?" when the note is not to be seen.
class _Bubble extends StatelessWidget {
  const _Bubble({
    super.key,
    required this.size,
    required this.color,
    required this.label,
    required this.lit,
  });

  final double size;
  final Color color;
  final String label;
  final bool lit;

  @override
  Widget build(BuildContext context) {
    final shown = lit ? color : Color.lerp(color, AppColors.background, 0.62)!;
    final dark = shown.computeLuminance() > 0.5;
    return AnimatedScale(
      scale: lit ? 1.0 : 0.88,
      duration: const Duration(milliseconds: 90),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 90),
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: shown,
          shape: BoxShape.circle,
          border: Border.all(color: lit ? Colors.white : Colors.white24, width: size * 0.03),
          boxShadow: [
            if (lit) BoxShadow(color: color.withValues(alpha: 0.7), blurRadius: size * 0.35),
          ],
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Padding(
            padding: EdgeInsets.all(size * 0.14),
            child: Text(
              label,
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                fontSize: size * 0.46,
                fontWeight: FontWeight.w900,
                color: dark ? AppColors.ink : Colors.white.withValues(alpha: lit ? 1 : 0.8),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// One dot per note to play back, in order: gray until it has been played,
// then its note's color (null: not yet). A wider gap where a line ends, and
// the lines before the new one a little smaller.
class _Dots extends StatelessWidget {
  const _Dots({required this.dots, required this.size});

  final List<({Color? color, bool gap, bool small})> dots;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: size * 1.5,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final dot in dots)
              Container(
                width: size * (dot.small ? 0.7 : 1),
                height: size * (dot.small ? 0.7 : 1),
                margin: EdgeInsets.only(
                  left: size * (dot.gap ? 1.1 : 0.25),
                  right: size * 0.25,
                ),
                decoration: BoxDecoration(
                  color: dot.color ?? Colors.white24,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
