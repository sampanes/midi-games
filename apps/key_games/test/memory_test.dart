// Song Memory: a song cut into lines, the rules (a line grows a note at a
// time or comes whole, a wrong key plays it again or gets help, hearts come
// back with each line) and the screen.

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:key_games/games/difficulty.dart';
import 'package:key_games/games/memory_page.dart';
import 'package:key_games/games/memory_rules.dart';
import 'package:key_games/songs/song.dart';

import 'helpers.dart';

// A tune on a clock: [notes] one [stepMs] apart, each note in [long] held
// for two steps.
Song _tune(List<int> notes, {int stepMs = 500, Set<int> long = const {}, String title = 'Test'}) {
  final out = <SongNote>[];
  var at = 0;
  for (var i = 0; i < notes.length; i++) {
    final steps = long.contains(i) ? 2 : 1;
    out.add(SongNote(notes[i], at, stepMs * steps - 75));
    at += stepMs * steps;
  }
  return Song(title, out);
}

// The first two lines of a well-known tune: seven notes each, the seventh
// held.
final _twoLines = _tune(
  [60, 60, 67, 67, 69, 69, 67, 65, 65, 64, 64, 62, 62, 60],
  long: {6, 13},
);

// Two lines of four notes on the computer keys: C D E F, then G F E D.
final _short = _tune([60, 62, 64, 65, 67, 65, 64, 62], long: {3, 7}, title: 'Short');

const _keys = {
  60: LogicalKeyboardKey.keyA,
  62: LogicalKeyboardKey.keyS,
  64: LogicalKeyboardKey.keyD,
  65: LogicalKeyboardKey.keyF,
  67: LogicalKeyboardKey.keyG,
  69: LogicalKeyboardKey.keyH,
};

Future<void> _tapKey(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(key);
  await tester.pump(const Duration(milliseconds: 50));
  await tester.sendKeyUpEvent(key);
  await tester.pump(const Duration(milliseconds: 50));
}

// Lets the game play what it has to and hand over the turn.
Future<void> _listen(WidgetTester tester) async {
  for (var i = 0; i < 100 && find.text('Your turn!').evaluate().isEmpty; i++) {
    if (find.text('From the top!').evaluate().isNotEmpty) return;
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  final easy = memoryLevels[Difficulty.easy]!;
  final medium = memoryLevels[Difficulty.medium]!;
  final hard = memoryLevels[Difficulty.hard]!;

  test('a song is cut into lines where it takes a breath', () {
    expect(songLines(_twoLines), [(start: 0, end: 7), (start: 7, end: 14)]);
    // Two long notes in a row end the line together.
    final pair = _tune([60, 60, 60, 62, 64, 62, 60, 64, 62, 62, 60], long: {4, 5, 10});
    expect(songLines(pair), [(start: 0, end: 6), (start: 6, end: 11)]);
  });

  test('a tune without a breath is cut into lines short enough to remember', () {
    final run = _tune([for (var i = 0; i < 30; i++) 60 + i % 5]);
    final lines = songLines(run);
    expect(lines.first.start, 0);
    expect(lines.last.end, 30);
    for (var i = 0; i < lines.length; i++) {
      expect(lines[i].length, inInclusiveRange(minLineNotes, maxLineNotes + 1));
      if (i > 0) expect(lines[i].start, lines[i - 1].end);
    }
    // A song with no clock at all (the built-in scale) still has lines.
    final scale = songLines(scaleSong);
    expect(scale.first.start, 0);
    expect(scale.last.end, scaleSong.notes.length);
    // A tune shorter than a line is one line.
    expect(songLines(_tune([60, 62, 64])), [(start: 0, end: 3)]);
  });

  test('the game plays in the rhythm of the song, slowed down for a quick one', () {
    // At its own speed: half a second a note, the long note a full second.
    final played = memoryPlayback(_twoLines, 4, 8, 1);
    expect([for (final n in played) n.atMs], [0, 500, 1000, 2000]);
    expect([for (final n in played) n.note], [69, 69, 67, 65]);
    // A note ends before the next begins, so a key played twice sounds twice.
    expect(played.first.lengthMs, lessThan(500));

    final quick = _tune([60, 62, 64, 65, 67, 69], stepMs: 200);
    expect(memoryStretch(quick, easy), 2.5);
    expect(memoryStretch(quick, memoryLevels[Difficulty.expert]!), 1);
    expect(memoryStretch(_twoLines, easy), 1);
    expect([for (final n in memoryPlayback(quick, 0, 3, 2.5)) n.atMs], [0, 500, 1000]);
  });

  test('a line grows one note at a time, then the next line starts from its own start', () {
    final lines = songLines(_short);
    var state = MemoryState.start(medium, lines);
    for (var length = 1; length <= 4; length++) {
      expect(memorySpan(state, medium, lines), (start: 0, end: length));
      for (var i = 0; i < length; i++) {
        // Any octave of the right letter counts.
        final step = pressMemory(state, _short.notes[i].note + 12, medium, _short, lines);
        state = step.state;
        expect(
          step.result,
          i < length - 1
              ? MemoryResult.hit
              : length < 4
                  ? MemoryResult.grown
                  : MemoryResult.lineDone,
        );
      }
      state = nextMemory(state, medium, lines);
    }
    expect(state.line, 1);
    expect(memorySpan(state, medium, lines), (start: 4, end: 5));
    expect(memoryListen(state, medium, lines), (start: 4, end: 5));
    expect(memoryWanted(state, medium, _short, lines), 67);
  });

  test('a wrong key starts the turn over, or with help carries on', () {
    final lines = songLines(_short);
    var state = const MemoryState(length: 3, at: 2);
    var step = pressMemory(state, 60, medium, _short, lines); // wanted: E
    expect(step.result, MemoryResult.miss);
    expect(step.state.at, 0);
    expect(step.state.again, isTrue);
    expect(step.state.misses, 1);

    step = pressMemory(state, 60, easy, _short, lines);
    expect(step.result, MemoryResult.miss);
    expect(step.state.at, 2);
    step = pressMemory(step.state, 64, easy, _short, lines);
    expect(step.result, MemoryResult.grown);

    // Waiting for it to be played again costs nothing.
    state = replayMemory(const MemoryState(length: 3, at: 2, misses: 1));
    expect((state.at, state.misses, state.again), (0, 1, true));
  });

  test('easy learns two lines; the other levels the whole song', () {
    final song = _tune([for (var i = 0; i < 24; i++) 60 + i % 4], long: {3, 7, 11, 15, 19, 23});
    final lines = songLines(song);
    expect(lines.length, 6);
    expect(memoryGoal(easy, lines), 2);
    expect(memoryGoal(medium, lines), 6);
    // The last note of the second line wins on Easy and goes on on Medium.
    const last = MemoryState(line: 1, length: 4, at: 3);
    expect(pressMemory(last, 63, easy, song, lines).result, MemoryResult.won);
    expect(pressMemory(last, 63, medium, song, lines).result, MemoryResult.lineDone);
    // A song of one line is won at one line, on every level.
    expect(memoryGoal(easy, songLines(_tune([60, 62, 64]))), 1);
  });

  test('hard hears a whole line and plays from the top, with hearts for each line', () {
    final lines = songLines(_short);
    var state = MemoryState.start(hard, lines);
    expect(memorySpan(state, hard, lines), (start: 0, end: 4));
    for (final n in _short.notes.take(4)) {
      state = pressMemory(state, n.note, hard, _short, lines).state;
    }
    state = nextMemory(state, hard, lines);

    // The second line: only it is played, but the turn starts at the top.
    expect(memoryListen(state, hard, lines), (start: 4, end: 8));
    expect(memorySpan(state, hard, lines), (start: 0, end: 8));
    expect(memoryWanted(state, hard, _short, lines), 60);

    // A wrong key costs a heart, and now everything is played again.
    var step = pressMemory(state, 71, hard, _short, lines);
    expect(step.result, MemoryResult.miss);
    expect(step.state.heartsLeft(hard), 2);
    expect(memoryListen(step.state, hard, lines), (start: 0, end: 8));
    step = pressMemory(step.state, 71, hard, _short, lines);
    step = pressMemory(step.state, 71, hard, _short, lines);
    expect(step.result, MemoryResult.over);

    // Hearts come back with a new line; the wrong keys still count for stars.
    final missed = pressMemory(MemoryState.start(hard, lines), 71, hard, _short, lines).state;
    var played = missed;
    for (final n in _short.notes.take(4)) {
      played = pressMemory(played, n.note, hard, _short, lines).state;
    }
    final next = nextMemory(played, hard, lines);
    expect(next.heartsLeft(hard), 3);
    expect(next.misses, 1);
  });

  test('stars: three for a clean song, fewer for wrong keys', () {
    final lines = songLines(_twoLines);
    expect(memoryStars(0, hard, lines), 3);
    expect(memoryStars(2, hard, lines), 2);
    expect(memoryStars(3, hard, lines), 1);
    expect(memoryStars(1, medium, lines), 3);
    expect(memoryStars(4, medium, lines), 2);
    expect(memoryStars(9, medium, lines), 1);
  });

  test('every built-in song has lines that cover it, none too long', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final songs = await loadSongs(rootBundle);
    expect(songs, isNotEmpty);
    for (final song in songs) {
      final lines = songLines(song);
      expect(lines.first.start, 0, reason: song.title);
      expect(lines.last.end, song.notes.length, reason: song.title);
      for (var i = 0; i < lines.length; i++) {
        expect(lines[i].length, inInclusiveRange(1, maxLineNotes + 1), reason: song.title);
        if (i > 0) expect(lines[i].start, lines[i - 1].end, reason: song.title);
      }
    }
    final twinkle = songs.firstWhere((song) => song.title == 'Twinkle Twinkle Little Star');
    expect([for (final line in songLines(twinkle)) line.length], [7, 7, 7, 7, 7, 7]);
  });

  testWidgets('medium: a line grows a note at a time, a wrong key plays it again', (tester) async {
    usePhone(tester, landscape: true);
    final synth = RecordingSynth();
    final services = await pumpApp(
      tester,
      MemoryPage(song: _short, difficulty: Difficulty.medium),
      synth: synth,
    );
    expect(find.text('Watch and listen'), findsOneWidget);
    expect(find.text('Short'), findsOneWidget);
    expect(find.text('Line 1 of 2'), findsOneWidget);

    // The game plays the first note (C), then it is the player's turn.
    await _listen(tester);
    expect(synth.events.where((e) => e == 'on 60'), hasLength(1));
    await _tapKey(tester, _keys[60]!);
    expect(find.text('Yes!'), findsOneWidget);

    // C D: played in the song's rhythm, half a second apart.
    synth.events.clear();
    await _listen(tester);
    expect(synth.events.where((e) => e.startsWith('on')), ['on 60', 'on 62']);

    // A wrong key: the same two notes again, and nothing is lost.
    await _tapKey(tester, _keys[60]!);
    await _tapKey(tester, _keys[67]!);
    expect(find.text('Listen again'), findsOneWidget);
    synth.events.clear();
    await _listen(tester);
    expect(synth.events.where((e) => e.startsWith('on')), ['on 60', 'on 62']);
    await _tapKey(tester, _keys[60]!);
    await _tapKey(tester, _keys[62]!);

    // The rest of the first line, then the second line from its own start.
    for (final length in [3, 4]) {
      await _listen(tester);
      for (final n in _short.notes.take(length)) {
        await _tapKey(tester, _keys[n.note]!);
      }
    }
    expect(find.text('Line 1: got it!'), findsOneWidget);
    for (var length = 1; length <= 4; length++) {
      await _listen(tester);
      expect(find.text('Line 2 of 2'), findsOneWidget);
      for (final n in _short.notes.skip(4).take(length)) {
        await _tapKey(tester, _keys[n.note]!);
      }
    }

    // The song is known: a party, the whole song played back, then stars.
    expect(find.text('YAY!'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 2000));
    expect(find.text('Listen to your song!'), findsOneWidget);
    await tester.pump(const Duration(seconds: 7));
    expect(find.text('You know Short by heart!'), findsOneWidget);
    expect(services.settings.best(memoryStarsKey(Difficulty.medium, _short)), 2);

    // C plays it again from the first note.
    await _tapKey(tester, _keys[60]!);
    expect(find.text('Line 1 of 2'), findsOneWidget);
    await _listen(tester);
    expect(find.text('Your turn!'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
    expect(synth.sounding, isEmpty);
  });

  testWidgets('easy: a wrong key gets help, and waiting does too', (tester) async {
    usePhone(tester, landscape: true);
    await pumpApp(tester, MemoryPage(song: _short), keyboard: false);
    await _listen(tester);
    // The turn is from memory: the bubble no longer shows the note played.
    expect(find.text('?'), findsOneWidget);
    await _tapKey(tester, _keys[65]!); // F: wrong, the first note is C
    expect(find.text('Try the glowing key'), findsOneWidget);
    await _tapKey(tester, _keys[60]!);
    expect(find.text('Yes!'), findsOneWidget);

    // C D: the player plays C and then forgets.
    await _listen(tester);
    await _tapKey(tester, _keys[60]!);
    expect(find.text('Try the glowing key'), findsNothing);
    await tester.pump(const Duration(seconds: 8));
    expect(find.text('Try the glowing key'), findsOneWidget);
    await _tapKey(tester, _keys[62]!);
    expect(find.text('Yes!'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('hard: a line at a time from the top, and out of hearts ends it', (tester) async {
    usePhone(tester, landscape: true);
    final synth = RecordingSynth();
    await pumpApp(tester, MemoryPage(song: _short, difficulty: Difficulty.hard), synth: synth);

    // The whole first line is played, and played back.
    await _listen(tester);
    expect(synth.events.where((e) => e.startsWith('on')), ['on 60', 'on 62', 'on 64', 'on 65']);
    for (final n in _short.notes.take(4)) {
      await _tapKey(tester, _keys[n.note]!);
    }
    expect(find.text('Line 1: got it!'), findsOneWidget);

    // Only the new line is played; the player starts at the top.
    synth.events.clear();
    await _listen(tester);
    expect(find.text('From the top!'), findsOneWidget);
    expect(synth.events.where((e) => e.startsWith('on')), ['on 67', 'on 65', 'on 64', 'on 62']);

    // Three wrong keys on a line and the game is over.
    for (var miss = 1; miss <= 3; miss++) {
      await _tapKey(tester, _keys[69]!);
      if (miss < 3) {
        expect(find.text('Listen again'), findsOneWidget);
        await _listen(tester);
      }
    }
    expect(find.text('Out of hearts!'), findsOneWidget);
    expect(find.text('You learned 1 of 2 lines'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
    expect(synth.sounding, isEmpty);
  });

  testWidgets('expert is by ear: nothing shows what the game plays', (tester) async {
    usePhone(tester, landscape: true);
    await pumpApp(tester, MemoryPage(song: _short, difficulty: Difficulty.expert));
    expect(find.text('Listen'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1700));
    // The first note is sounding: the bubble does not say which.
    expect(find.text('?'), findsOneWidget);
    // Nor does it once the turn starts: only a right key shows its letter.
    await _listen(tester);
    expect(find.text('?'), findsOneWidget);
    await _tapKey(tester, _keys[69]!); // A: wrong
    await _listen(tester);
    expect(find.text('?'), findsOneWidget);
    await _tapKey(tester, _keys[60]!);
    expect(find.text('?'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });
}
