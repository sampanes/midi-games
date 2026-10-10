import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:key_games/audio/synth.dart';
import 'package:key_games/games/difficulty.dart';
import 'package:key_games/games/rush_page.dart';
import 'package:key_games/games/rush_rules.dart';
import 'package:key_games/midi/midi_input.dart';
import 'package:key_games/songs/song.dart';

void main() {
  test('easy keys are the four middle keys, never the same twice, never far', () {
    final feed = EasyRushFeed(Random(1));
    int? last;
    for (var i = 0; i < 500; i++) {
      final next = feed.next(last);
      expect(rushEasyKeys, contains(next));
      if (last != null) {
        expect(next, isNot(last));
        final step = (rushEasyKeys.indexOf(next) - rushEasyKeys.indexOf(last)).abs();
        expect(step, lessThanOrEqualTo(rushEasyMaxStep));
      }
      last = next;
    }
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

  test('easy: any octave counts and a wrong key costs nothing', () {
    final feed = EasyRushFeed(Random(2));
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
    tester.view.physicalSize = const Size(1080, 2316);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);

    // The synth is never started here, so it stays silent.
    await tester.pumpWidget(MaterialApp(
      home: RushPage(
        synth: Synth(),
        midi: MidiInput(),
        difficulty: difficulty,
        random: Random(5),
        songs: songs,
      ),
    ));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('3'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 2200));
  }

  testWidgets('easy rush counts down, scores, ends, and C plays again', (tester) async {
    await pumpRush(tester, Difficulty.easy, const []);
    expect(find.text('Song: Scale'), findsOneWidget);

    // Easy never freezes, so one pass over E F G A finds the key.
    for (final key in [
      LogicalKeyboardKey.keyD, LogicalKeyboardKey.keyF,
      LogicalKeyboardKey.keyG, LogicalKeyboardKey.keyH,
    ]) {
      await tester.sendKeyEvent(key);
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('0'), findsNothing);

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

  testWidgets('real rush follows the song key by key', (tester) async {
    // A synthetic tune within the computer keys (A S D F G = C D E F G).
    const tune = Song('Test Tune', [
      SongNote(60, 0, 300), SongNote(64, 300, 300), SongNote(67, 600, 300),
      SongNote(65, 900, 300), SongNote(62, 1200, 300),
    ]);
    await pumpRush(tester, Difficulty.medium, const [tune]);
    expect(find.text('Song: Test Tune'), findsOneWidget);

    for (final key in [
      LogicalKeyboardKey.keyA, LogicalKeyboardKey.keyD, LogicalKeyboardKey.keyG,
    ]) {
      await tester.sendKeyEvent(key);
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('3'), findsOneWidget);

    // C is not next (F is): a miss, and the score stays.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('3'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });
}
