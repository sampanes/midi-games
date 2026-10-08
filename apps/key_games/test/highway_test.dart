import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:key_games/audio/synth.dart';
import 'package:key_games/games/difficulty.dart';
import 'package:key_games/games/highway_page.dart';
import 'package:key_games/games/highway_rules.dart';
import 'package:key_games/games/rush_page.dart';
import 'package:key_games/midi/midi_input.dart';
import 'package:key_games/songs/song.dart';
import 'package:key_games/widgets/piano_strip.dart';

// A made-up tune: up the C scale and back, half a second a note.
final _scale = Song('Test scale', [
  for (final (i, note) in [60, 62, 64, 65, 67, 69, 71, 72, 71, 69, 67, 65, 64, 62, 60].indexed)
    SongNote(note, i * 500, 400),
]);

void main() {
  test('thinning drops notes that come too fast and never keeps two at once', () {
    const notes = [SongNote(60, 0, 100), SongNote(62, 0, 100), SongNote(64, 100, 100), SongNote(65, 600, 100)];
    expect(thinNotes(notes, 0).map((n) => n.note), [60, 64, 65]);
    expect(thinNotes(notes, 500).map((n) => n.note), [60, 65]);
  });

  test('a song in D moves to C for the white keys; octaves fit the keyboard', () {
    expect(whiteKeyShift([62, 64, 66, 67, 69, 71, 73]), -2);
    expect(whiteKeyShift([60, 62, 64]), 0);
    expect(fitOctaves([36, 40, 43]), 24);
    expect(fitOctaves([60, 72]), 0);
  });

  test('easy gives the player five neighboring white keys and plays the rest', () {
    final chart = buildChart(_scale, Difficulty.easy);
    // C to G covers most of the scale; A and B (four notes) are played for you.
    expect(chart.lanes.map((l) => l.key), [0, 2, 4, 5, 7]);
    expect(chart.notes, hasLength(11));
    expect(chart.autoNotes.map((n) => n.sound), [69, 71, 71, 69]);
    expect(chart.autoNotes.every((n) => n.lane == -1), isTrue);
    expect(chart.notes.first.timeMs, 0);
    // 500 ms apart becomes 667 ms at three-quarter speed.
    expect(chart.notes[1].timeMs, 667);
    // Every lane is the note that sounds: nothing is made up.
    for (final n in chart.notes) {
      expect(chart.lanes[n.lane].matches(n.sound), isTrue);
    }
  });

  test('easy keeps the real notes, moved to C only when the song is not on white keys', () {
    // E D C D E E E, half a second each.
    const song = Song('Three letters', [
      SongNote(64, 0, 400), SongNote(62, 500, 400), SongNote(60, 1000, 400), SongNote(62, 1500, 400),
      SongNote(64, 2000, 400), SongNote(64, 2500, 400), SongNote(64, 3000, 400),
    ]);
    final chart = buildChart(song, Difficulty.easy);
    expect(chart.lanes.map((l) => l.key), [0, 2, 4]);
    expect([for (final n in chart.notes) chart.lanes[n.lane].key], [4, 2, 0, 2, 4, 4, 4]);
    expect(chart.autoNotes, isEmpty);

    // The same tune in D moves to C, and it sounds where it is played.
    const inD = Song('In D', [SongNote(66, 0, 400), SongNote(64, 500, 400), SongNote(62, 1000, 400)]);
    final moved = buildChart(inD, Difficulty.easy);
    expect(moved.lanes.map((l) => l.key), [0, 2, 4]);
    expect(moved.notes.map((n) => n.sound), [64, 62, 60]);

    // C C G G A A G: C and G are on C to G; the A's are played for you.
    const hops = Song('Seven notes', [
      SongNote(60, 0, 400), SongNote(60, 600, 400), SongNote(67, 1200, 400), SongNote(67, 1800, 400),
      SongNote(69, 2400, 400), SongNote(69, 3000, 400), SongNote(67, 3600, 800),
    ]);
    final chart2 = buildChart(hops, Difficulty.easy);
    expect(chart2.lanes.map((l) => l.key), [0, 7]);
    expect(chart2.autoNotes.map((n) => n.sound), [69, 69]);
  });

  test('medium plays the black keys for you; notes too fast are played for you too', () {
    const song = Song('Chromatic', [SongNote(60, 0, 300), SongNote(61, 500, 300), SongNote(62, 1000, 300)]);
    final medium = buildChart(song, Difficulty.medium);
    expect(medium.lanes.map((l) => l.key), [0, 2]);
    expect(medium.autoNotes.map((n) => n.sound), [61]);

    const quick = Song('Quick', [SongNote(60, 0, 100), SongNote(62, 100, 100), SongNote(64, 1000, 100)]);
    final easy = buildChart(quick, Difficulty.easy);
    expect(easy.notes.map((n) => n.sound), [60, 64]);
    expect(easy.autoNotes.map((n) => n.sound), [62]);
    expect(easy.endMs, greaterThan(easy.autoNotes.single.timeMs));
  });

  test('hard keeps sharps; expert wants the exact keys', () {
    const song = Song('Sharp', [SongNote(61, 0, 300), SongNote(66, 400, 300), SongNote(36, 800, 300)]);
    final hard = buildChart(song, Difficulty.hard);
    expect(hard.lanes.map((l) => l.key), [0, 1, 6]);
    expect(hard.lanes[1].matches(73), isTrue);

    final expert = buildChart(_scale, Difficulty.expert);
    expect(expert.lanes.every((l) => l.exact), isTrue);
    expect(expert.lanes.first.matches(60), isTrue);
    expect(expert.lanes.first.matches(72), isFalse);
  });

  test('hits in time score with a streak; wrong keys and late notes miss', () {
    final chart = buildChart(_scale, Difficulty.hard);
    final run = HighwayRun(chart, 150);

    expect(run.press(64, -1000).result, HighwayResult.stray);
    final hit = run.press(72, 20); // any C counts on Hard
    expect(hit.result, HighwayResult.perfect);
    expect(run.score, perfectPoints);
    expect(run.press(62, 500 + 120).result, HighwayResult.good);
    expect(run.streak, 2);

    final wrong = run.press(67, 1000);
    expect(wrong.result, HighwayResult.wrong);
    expect(run.marks[wrong.index!], NoteMark.missed);
    expect(run.streak, 0);

    expect(run.advance(1700), [3]);
    expect(run.hits, 2);
    expect(multiplierFor(9), 1);
    expect(multiplierFor(10), 2);
    expect(multiplierFor(99), 4);
  });

  testWidgets('note highway counts down, hits on time, ends, and C plays again', (tester) async {
    tester.view.physicalSize = const Size(1080, 2316);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);

    const song = Song('Four notes', [
      SongNote(60, 0, 300), SongNote(62, 600, 300), SongNote(64, 1200, 300), SongNote(65, 1800, 300),
    ]);
    // The synth is never started here, so it stays silent.
    await tester.pumpWidget(MaterialApp(
      home: HighwayPage(song: song, synth: Synth(), midi: MidiInput()),
    ));
    // Easy: 3.8 s lead-in, the count starts 2.1 s before the first note.
    await tester.pump(const Duration(milliseconds: 2000));
    expect(find.text('3'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1800));

    // Three-quarter speed: the notes are 800 ms apart on C D E F.
    for (final key in [
      LogicalKeyboardKey.keyA, LogicalKeyboardKey.keyS,
      LogicalKeyboardKey.keyD, LogicalKeyboardKey.keyF,
    ]) {
      await tester.sendKeyEvent(key);
      await tester.pump();
      expect(find.text('Great!'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 800));
    }

    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Song done!'), findsOneWidget);
    expect(find.text('4 of 4 notes'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA); // C: play again
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Song done!'), findsNothing);
    await tester.pump(const Duration(milliseconds: 2000));
    expect(find.text('3'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });

  // A phone on its side: the keyboard picture is gone at the end, so the end
  // choices show in full.
  Future<void> expectEndFits(WidgetTester tester) async {
    final view = tester.getRect(find.byType(SingleChildScrollView).last);
    for (final label in ['Play again', 'Songs', 'Menu']) {
      final button = find.widgetWithText(ButtonStyleButton, label);
      if (button.evaluate().isEmpty) continue;
      expect(tester.getRect(button).bottom, lessThanOrEqualTo(view.bottom), reason: label);
    }
    expect(find.byType(PianoStrip), findsNothing);
  }

  // Larger text (a phone setting) must fit too.
  Widget bigText(Widget home) => MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.3)),
          child: child!,
        ),
        home: home,
      );

  testWidgets('end screens fit a landscape phone', (tester) async {
    tester.view.physicalSize = const Size(2316, 1080);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);

    const song = Song('Two notes', [SongNote(60, 0, 300), SongNote(62, 600, 300)]);
    await tester.pumpWidget(bigText(HighwayPage(song: song, synth: Synth(), midi: MidiInput())));
    await tester.pump(const Duration(seconds: 8));
    expect(find.text('Nice try!'), findsOneWidget);
    await expectEndFits(tester);

    await tester.pumpWidget(bigText(RushPage(synth: Synth(), midi: MidiInput(), songs: const [])));
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 61));
    expect(find.text("Time's up!"), findsOneWidget);
    await expectEndFits(tester);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });
}
