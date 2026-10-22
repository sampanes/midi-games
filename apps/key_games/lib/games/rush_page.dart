// Key Rush screen: 3-2-1, then one minute to hit as many keys as possible.
// The minute starts at the first right key, not at GO, so a player can find
// the keys and set their fingers first.
// A board above the keyboard picture shows the key to press now (bottom row)
// and the next ones above it, lined up with the keys, like the tiles on an
// arcade piano. Each hit moves the tiles down a row.
//
// Easy asks for the low, middle or high part of the keyboard: any key in
// the part counts, and the board's three lanes line up with the parts of the
// keyboard picture. Medium shows one octave and uses its keys C, E and G.
// On both, every hit plays the next note of a song, whatever key was
// pressed, so the melody comes out, and a wrong key makes no sound and costs
// nothing.
// Real plays a song's own notes on their own keys: each key sounds as
// itself, and a wrong key plays itself and then the right note and freezes
// scoring for that moment.
//
// At the end: score, the best score on the device, and the song name. Keys
// at the end: C plays again, E goes back to the menu.

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/services.dart';
import '../app/settings.dart';
import '../app/theme.dart';
import '../audio/miss_echo.dart';
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
import 'rush_rules.dart';

const _countdownStepMs = 700;

const rushLevels = {
  Difficulty.easy: 'Low, middle or high: any key there; a song plays as you hit',
  Difficulty.medium: 'C, E and G; a song plays as you hit them',
  Difficulty.hard: "A song's real notes on the real keys",
};
const rushLabels = {Difficulty.hard: 'Real'};

// Best scores on the device per way to play. Real keeps the key it had when
// it was the second level, so its best scores carry over.
const _bestKeys = {
  Difficulty.easy: 'rush.zones',
  Difficulty.medium: 'rush.keys',
  Difficulty.hard: 'rush.medium',
};

enum _Phase { countdown, playing, done }

class RushPage extends StatefulWidget {
  const RushPage({
    super.key,
    this.difficulty = Difficulty.easy,
    this.random,
    this.songs,
  });

  // Easy, Medium, or anything harder for Real.
  final Difficulty difficulty;

  // Fixed in tests.
  final Random? random;
  final List<Song>? songs;

  @override
  State<RushPage> createState() => _RushPageState();
}

class _RushPageState extends State<RushPage> with TickerProviderStateMixin {
  late final Synth _synth = AppServices.of(context).synth;
  late final Settings _settings = AppServices.of(context).settings;
  late final Random _random = widget.random ?? Random();
  final GlobalKey<SparksState> _sparksKey = GlobalKey();
  final GlobalKey _boardKey = GlobalKey();
  late final AnimationController _slide =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 140), value: 1);
  late final AnimationController _shake =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
  late final MissEcho _echo = MissEcho(_synth);
  final List<Timer> _timers = [];
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
  bool get _zones => _level == Difficulty.easy;
  bool get _real => _level.atLeast(Difficulty.hard);
  String get _bestKey => _bestKeys[_level] ?? _bestKeys[Difficulty.hard]!;

  // Real: the keyboard's octave buttons move everything by whole octaves.
  int get _shift => _real ? _base - 48 : 0;

  ({int low, int high}) get _span {
    if (_zones) return pictureKeys(context, _base);
    if (!_real) return (low: rushKeysLow, high: rushKeysHigh);
    final notes = _song.notes.map((n) => n.note);
    return whiteSpan(notes.reduce(min) + _shift, notes.reduce(max) + _shift);
  }

  @override
  void initState() {
    super.initState();
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
    _clock?.cancel();
    _echo.cancel();
    for (final timer in _timers) {
      timer.cancel();
    }
    for (final note in _held) {
      _synth.noteOff(note);
    }
    _slide.dispose();
    _shake.dispose();
    super.dispose();
  }

  void _later(Duration delay, void Function() action) {
    _timers.add(Timer(delay, () {
      if (mounted) action();
    }));
  }

  void _resetRound() {
    _clock?.cancel();
    _clock = null;
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

  // 3, 2, 1 with a beep each, then GO. The clock waits for the first hit.
  void _countdown() {
    for (var i = 0; i < 3; i++) {
      _later(Duration(milliseconds: 400 + i * _countdownStepMs), () {
        setState(() => _count = 3 - i);
        _synth.blip(72, velocity: 70, lengthMs: 150);
      });
    }
    _later(const Duration(milliseconds: 400 + 3 * _countdownStepMs), _go);
  }

  void _go() {
    _synth.blip(84, velocity: 90, lengthMs: 300);
    setState(() {
      _phase = _Phase.playing;
      // Picked now, not at the start, so the songs have finished loading.
      _song = _songs.isEmpty ? scaleSong : _songs[_random.nextInt(_songs.length)];
      _feed = _real
          ? SongRushFeed([for (final n in _song.notes) n.note])
          : WalkRushFeed(_random, _zones ? rushZones : rushKeys);
      _state = RushState.start(_feed);
    });
  }

  // The minute starts with the first right key.
  void _startClock() {
    _clock = Timer.periodic(const Duration(milliseconds: rushTickMs), (_) {
      if (!mounted) return;
      setState(() => _state = rushTick(_state));
      if (_state.over) _finish();
    });
  }

  void _finish() {
    _clock?.cancel();
    _echo.cancel();
    setState(() {
      _phase = _Phase.done;
      _newBest = _settings.recordBest(_bestKey, _state.score);
    });
    _synth.tune([72, 76, 79, 84], stepMs: 120, lengthMs: 220);
    // A moment before the end keys work, so the last hits do not restart it.
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
      if (_real || _zones) _base = fitBase(_base, event.note);
    });
    if (_phase != _Phase.playing) {
      _synth.noteOn(event.note, event.velocity);
      return;
    }
    final target = _state.target;
    // No freeze before the clock runs: only its ticks would end it.
    // Easy answers with the part of the keyboard the key is in.
    final answer = _zones ? zoneOf(event.note, _span, rushZoneCount) : event.note - _shift;
    final step = pressRush(_state, answer, _feed,
        exact: _real || _zones, freeze: _real && _clock != null);
    setState(() => _state = step.state);
    switch (step.result) {
      case RushResult.hit:
        if (_clock == null) _startClock();
        _echo.cancel();
        if (_real) {
          _synth.noteOn(event.note, event.velocity);
        } else {
          _smash();
        }
        _slide.forward(from: 0);
        _sparksKey.currentState?.burst(
          _tileCenter(target),
          [_tileColor(target), AppColors.starGold],
          count: 16,
          speed: 380,
        );
      case RushResult.miss:
        _shake.forward(from: 0);
        if (_real) {
          _synth.noteOn(event.note, event.velocity);
          _echo.play(event.note, target + _shift);
        }
      case RushResult.frozen || RushResult.over:
        if (_real) _synth.noteOn(event.note, event.velocity);
    }
  }

  // Easy: the next note of the song instead of the key pressed.
  void _smash() {
    final notes = _song.notes;
    final n = notes[_songIndex % notes.length];
    _songIndex++;
    _synth.blip(n.note, velocity: 100, lengthMs: n.lengthMs.clamp(150, 700));
  }

  Color _tileColor(int target) =>
      _zones ? zoneColors(rushZoneCount)[target] : noteColor(target);

  // Middle of the bottom-row tile for [target] (a key, or Easy's part), in
  // the sparks' coordinates.
  Offset _tileCenter(int target) {
    final board = _boardKey.currentContext?.findRenderObject() as RenderBox?;
    final sparks = _sparksKey.currentContext?.findRenderObject() as RenderBox?;
    if (board == null || sparks == null) return Offset.zero;
    final span = _span;
    final width = board.size.width;
    final column = _zones
        ? zoneColumn(span, target, rushZoneCount, width)
        : keyColumn(span.low, span.high, width, target + _shift);
    final rowHeight = board.size.height / rushRows;
    final local = Offset(column.left + column.width / 2, board.size.height - rowHeight / 2);
    return sparks.globalToLocal(board.localToGlobal(local));
  }

  // Medium shows one octave, so a key pressed in another octave lights its
  // twin there.
  Set<int> get _shownHeld => _real || _zones
      ? _held
      : {for (final note in _held) rushKeysLow + pitchClass(note)};

  @override
  Widget build(BuildContext context) {
    final playing = _phase == _Phase.playing;
    final span = _span;
    return GamePage(
      picks: _phase == _Phase.done && _canPick
          ? {0: _startRound, 4: () => Navigator.maybePop(context)}
          : const {},
      onNote: _onNote,
      header: [
        Icon(Icons.star_rounded, color: AppColors.starGold, size: 40 * uiScale(context)),
        const SizedBox(width: 4),
        Text('${_state.score}',
            style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900)),
        const SizedBox(width: 16),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: _state.timeLeft,
              minHeight: 14 * uiScale(context),
              color: _state.timeLeft < 0.17 ? AppColors.red : AppColors.starGold,
              backgroundColor: Colors.white12,
            ),
          ),
        ),
        const SizedBox(width: 12),
      ],
      body: _phase == _Phase.done
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
      footer: [
        Text(
          _phase == _Phase.countdown
              ? 'Get ready!'
              : playing && _clock == null
                  ? _zones
                      ? 'Press in the lit part: the clock starts when you hit it'
                      : 'Find the key: the clock starts when you hit it'
                  : 'Song: ${_song.title}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: Colors.white54, fontSize: 16 * uiScale(context)),
        ),
        // Hidden at the end, so the end choices fit a landscape phone.
        if (_phase != _Phase.done)
          Padding(
            padding: const EdgeInsets.all(8),
            child: SizedBox(
              height: pianoStripHeight(context),
              child: PianoStrip(
                base: _base,
                span: _zones ? null : span,
                targetNote: playing && !_zones && !_state.frozen ? _state.target + _shift : null,
                zones: _zones ? rushZoneCount : null,
                litZone: playing && _zones ? _state.target : null,
                plain: _zones,
                held: _shownHeld,
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
              notes: playing
                  ? [for (final n in _state.upcoming) _zones ? n : n + _shift]
                  : const [],
              lanes: _real ? null : rushKeys,
              zones: _zones,
              slide: Curves.easeOut.transform(_slide.value),
              frozen: _state.frozen,
            ),
          ),
        );
      },
    );
  }

  // The countdown and the end panel are chrome: phone-sized text grown with
  // the screen.
  Widget _buildCountdown() {
    return ScaledChrome(
      scale: uiScale(context),
      child: TweenAnimationBuilder<double>(
        key: ValueKey(_count),
        tween: Tween(begin: 1.6, end: 1),
        duration: const Duration(milliseconds: 300),
        builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
        child: Text(
          '$_count',
          style: const TextStyle(fontSize: 160, fontWeight: FontWeight.w900, color: AppColors.starGold),
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
            const Text("Time's up!", style: TextStyle(fontSize: 36, fontWeight: FontWeight.w900)),
            SizedBox(height: 8 * s),
            Text('${_state.score} keys',
                style: const TextStyle(
                    fontSize: 56, fontWeight: FontWeight.w900, color: AppColors.starGold)),
            Text(
              _newBest ? 'New best!' : 'Best: $best',
              style: const TextStyle(fontSize: 22, color: Colors.white70),
            ),
            SizedBox(height: 4 * s),
            Text(_real ? 'You played ${_song.title}!' : 'You smashed out ${_song.title}!',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18, color: Colors.white70)),
            SizedBox(height: 20 * s),
            Wrap(
              spacing: 16 * s,
              runSpacing: 12 * s,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: _startRound,
                  style: keyButtonStyle(s),
                  icon: KeyBadge(pc: 0, size: 30 * s),
                  label: const Text('Play again'),
                ),
                OutlinedButton.icon(
                  onPressed: () => Navigator.maybePop(context),
                  style: keyButtonStyle(s),
                  icon: KeyBadge(pc: 4, size: 30 * s),
                  label: const Text('Menu'),
                ),
              ],
            ),
          ],
        ),
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
    required this.zones,
    required this.slide,
    required this.frozen,
  });

  final ({int low, int high}) span;

  // Keys, or on Easy the parts of the keyboard (0 low to 2 high).
  final List<int> notes;

  // Keys whose columns are a little lighter (Medium's keys); null for all.
  final List<int>? lanes;

  // Easy: the board's columns are the parts of the picture ([span]).
  final bool zones;
  bool get _zones => zones;

  ({double left, double width}) _column(int note, double width) => _zones
      ? zoneColumn(span, note, rushZoneCount, width)
      : keyColumn(span.low, span.high, width, note);
  final double slide;
  final bool frozen;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    final rowHeight = size.height / rushRows;
    final gap = min(6.0, rowHeight * 0.06);
    final fill = Paint();
    final columns = _zones
        ? rushZones
        : [
            for (var note = span.low; note <= span.high; note++)
              if (pitchClasses[pitchClass(note)].white) note,
          ];
    for (final note in columns) {
      final column = _column(note, size.width);
      final lane = _zones || lanes == null || lanes!.contains(note);
      fill.color = lane ? const Color(0x1FFFFFFF) : const Color(0x0AFFFFFF);
      for (var row = 0; row < rushRows; row++) {
        final rect = Rect.fromLTWH(column.left, row * rowHeight, column.width, rowHeight);
        canvas.drawRRect(RRect.fromRectAndRadius(rect.deflate(gap), const Radius.circular(8)), fill);
      }
    }

    for (var row = notes.length - 1; row >= 0; row--) {
      final note = notes[row];
      if (!_zones && (note < span.low || note > span.high)) continue;
      final info = pitchClasses[pitchClass(note)];
      final base = _zones ? zoneColors(rushZoneCount)[note] : Color(info.argb);
      final name = _zones ? zoneNames(rushZoneCount)[note] : info.name;
      final column = _column(note, size.width);
      final top = size.height - (row + 1 + (1 - slide)) * rowHeight;
      final rect = Rect.fromLTWH(column.left, top, column.width, rowHeight).deflate(gap);
      final now = row == 0;
      final color = base.withValues(alpha: frozen ? 0.3 : (now ? 1 : 0.75 - 0.15 * row));
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
      final dark = base.computeLuminance() > 0.5;
      final text = TextPainter(
        text: TextSpan(
          text: name,
          style: TextStyle(
            fontFamily: fontFamily,
            // Two letters (F#) on a narrow black-key tile need a smaller
            // size; a part's name is a word on a wide tile.
            fontSize: min(
              rect.width * (name.length > 2 ? 0.16 : name.length > 1 ? 0.34 : 0.5),
              rect.height * 0.45,
            ),
            fontWeight: FontWeight.w900,
            color: (dark ? AppColors.ink : Colors.white).withValues(alpha: frozen ? 0.4 : 1),
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
