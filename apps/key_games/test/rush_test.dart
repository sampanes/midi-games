import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:key_games/games/difficulty.dart';
import 'package:key_games/games/rush_page.dart';
import 'package:key_games/games/rush_rules.dart';
import 'package:key_games/songs/song.dart';
import 'package:key_games/widgets/piano_strip.dart';

import 'helpers.dart';

void main() {
  test('easy asks for parts and medium for C E G, never the same twice', () {
    for (final keys in [rushZones, rushKeys]) {
      final feed = WalkRushFeed(Random(1), keys);
      int? last;
      for (var i = 0; i < 500; i++) {
        final next = feed.next(last);
        expect(keys, contains(next));
        if (last != null) {
          expect(next, isNot(last));
          final step = (keys.indexOf(next) - keys.indexOf(last)).abs();
          expect(step, lessThanOrEqualTo(rushMaxStep));
        }
        last = next;
      }
    }
    expect(rushKeys.map((n) => n % 12), [0, 4, 7]);
  });

  test('the board holds the next keys; a hit moves them down a row', () {
    final feed = SongRushFeed([60, 62, 64, 65, 67, 69]);
    final state = RushState.start(feed);
    expect(state.upcoming, [60, 62, 64, 65]);
    final step = pressRush(state, 60, feed, exact: true);
    expect(step.result, RushResult.hit);
    expect(step.state.score, 1);
    expect(step.state.upcoming, [62, 64, 65, 67]);
  });

  test('easy: the part of the keyboard is the answer, and a wrong part costs nothing', () {
    final feed = WalkRushFeed(Random(2), rushZones);
    final state = RushState.start(feed);
    expect(pressRush(state, state.target, feed, exact: true).result, RushResult.hit);
    final wrong = pressRush(state, (state.target + 1) % 3, feed, exact: true);
    expect(wrong.result, RushResult.miss);
    expect(wrong.state.frozen, isFalse);
  });

  test('medium: any octave counts and a wrong key costs nothing', () {
    final feed = WalkRushFeed(Random(2), rushKeys);
    final state = RushState.start(feed);
    final low = state.target - 12;
    expect(pressRush(state, low, feed).result, RushResult.hit);

    final wrong = pressRush(state, state.target + 1, feed);
    expect(wrong.result, RushResult.miss);
    expect(wrong.state.frozen, isFalse);
  });

  test('real: the octave matters, and a wrong key freezes while the clock runs', () {
    final feed = SongRushFeed([60, 72, 60, 72]);
    var step = pressRush(RushState.start(feed), 72, feed, exact: true, freeze: true);
    expect(step.result, RushResult.miss);
    expect(step.state.frozen, isTrue);
    expect(pressRush(step.state, 60, feed, exact: true, freeze: true).result, RushResult.frozen);

    var state = step.state;
    for (var t = 0; t < rushFreezeMs; t += rushTickMs) {
      state = rushTick(state);
    }
    expect(state.frozen, isFalse);
    expect(state.elapsedMs, rushFreezeMs);
    step = pressRush(state, 60, feed, exact: true, freeze: true);
    expect(step.result, RushResult.hit);
  });

  test('real: the song starts over after its last note; time runs out after a minute', () {
    final feed = SongRushFeed([60, 62]);
    var state = RushState.start(feed);
    expect(state.upcoming, [60, 62, 60, 62]);

    for (var t = 0; t < rushGameMs; t += rushTickMs) {
      state = rushTick(state);
    }
    expect(state.over, isTrue);
    expect(state.timeLeft, 0);
    expect(pressRush(state, 60, feed).result, RushResult.over);
  });

  Future<void> pumpRush(WidgetTester tester, Difficulty difficulty, List<Song> songs) async {
    usePhone(tester);
    await pumpApp(tester, RushPage(difficulty: difficulty, random: Random(5), songs: songs));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('3'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 2200));
  }

  double timeLeft(WidgetTester tester) =>
      tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).value!;

  testWidgets('easy rush counts down, scores, ends, and C plays again', (tester) async {
    await pumpRush(tester, Difficulty.easy, const []);

    // The minute waits for the first right key, however long that takes.
    expect(find.textContaining('the clock starts'), findsOneWidget);
    await tester.pump(const Duration(seconds: 10));
    expect(timeLeft(tester), 1);

    // Easy never freezes, so one touch in each part finds the one asked for.
    await startRushClock(tester);
    expect(find.text('0'), findsNothing);
    expect(find.text('Song: Scale'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(timeLeft(tester), lessThan(1));

    await tester.pump(const Duration(seconds: 61));
    expect(find.text("Time's up!"), findsOneWidget);
    expect(find.text('New best!'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA); // C: play again
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Get ready!'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('easy rush plays by touch alone on the one octave of a phone', (tester) async {
    usePhone(tester, landscape: true);
    await pumpApp(tester, RushPage(random: Random(5), songs: const []), keyboard: false);
    await tester.pump(const Duration(milliseconds: 2700));

    // The picture is one octave, C to C: its parts are C D E, F G and A B C,
    // and touching each once finds the part asked for.
    final strip = tester.getRect(find.byType(PianoStrip));
    expect(keyColumn(60, 72, strip.width, 60).width, closeTo(strip.width / 8, 1));
    await startRushClock(tester);
    expect(find.text('0'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('real rush follows the song key by key', (tester) async {
    // A synthetic tune within the computer keys (A S D F G = C D E F G).
    const tune = Song('Test Tune', [
      SongNote(60, 0, 300), SongNote(64, 300, 300), SongNote(67, 600, 300),
      SongNote(65, 900, 300), SongNote(62, 1200, 300),
    ]);
    await pumpRush(tester, Difficulty.hard, const [tune]);

    // A wrong key before the start neither scores, freezes nor starts the clock.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.pump(const Duration(seconds: 3));
    expect(timeLeft(tester), 1);
    expect(find.textContaining('the clock starts'), findsOneWidget);

    for (final key in [
      LogicalKeyboardKey.keyA, LogicalKeyboardKey.keyD, LogicalKeyboardKey.keyG,
    ]) {
      await tester.sendKeyEvent(key);
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('3'), findsOneWidget);
    expect(find.text('Song: Test Tune'), findsOneWidget);

    // Clicking the keyboard picture plays too (testing without a keyboard):
    // F is next.
    final strip = tester.getRect(find.byType(PianoStrip));
    final f = keyColumn(60, 67, strip.width, 65);
    await tester.tapAt(Offset(strip.left + f.left + f.width / 2, strip.bottom - 10));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('4'), findsOneWidget);

    // C is not next (D is): a miss, and the score stays.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('4'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });
}
