// Copy Cat: the rules (a pattern grows by one each time it is played back,
// a wrong note plays it again, hearts end the harder levels) and the screen.

import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:key_games/games/copy_page.dart';
import 'package:key_games/games/copy_rules.dart';
import 'package:key_games/games/difficulty.dart';

import 'helpers.dart';

// Always the first choice on offer. With the "never three the same in a
// row" rule, a pattern then goes first, first, second, first, first, second.
class _First implements Random {
  @override
  int nextInt(int max) => 0;

  @override
  double nextDouble() => 0;

  @override
  bool nextBool() => false;
}

Future<void> _tapKey(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(key);
  await tester.pump(const Duration(milliseconds: 50));
  await tester.sendKeyUpEvent(key);
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  final medium = copyLevels[Difficulty.medium]!;
  final easy = copyLevels[Difficulty.easy]!;

  test('a pattern played back grows by one note, from its start', () {
    var state = CopyState.start(medium, _First());
    expect(state.pattern, [0]);

    var step = pressCopy(state, 0, medium);
    expect(step.result, CopyResult.patternDone);
    expect(step.state.best, 1);

    state = growCopy(step.state, medium, _First());
    expect(state.pattern, [0, 0]);
    expect(state.at, 0);
    step = pressCopy(state, 0, medium);
    expect(step.result, CopyResult.hit);
    step = pressCopy(step.state, 0, medium);
    expect(step.result, CopyResult.patternDone);
    expect(step.state.best, 2);

    // Never three of the same in a row.
    state = growCopy(step.state, medium, _First());
    expect(state.pattern, [0, 0, 4]);
  });

  test('a wrong note starts the same pattern over and costs a heart', () {
    var state = const CopyState(pattern: [0, 4, 7], at: 2, best: 2);
    final step = pressCopy(state, 0, medium);
    expect(step.result, CopyResult.miss);
    expect(step.state.pattern, [0, 4, 7]);
    expect(step.state.at, 0);
    expect(step.state.best, 2);
    expect(step.state.heartsLeft(medium), 2);

    // The third wrong note ends the game.
    state = const CopyState(pattern: [0], misses: 2);
    expect(pressCopy(state, 4, medium).result, CopyResult.over);
  });

  test('a key that is not one of the answers only sounds', () {
    const state = CopyState(pattern: [0]);
    final step = pressCopy(state, 2, medium); // D: not one of C, E, G
    expect(step.result, CopyResult.ignored);
    expect(step.state.misses, 0);
  });

  test('easy cannot be lost, and a pattern of six wins', () {
    expect(easy.hearts, isNull);
    expect(easy.zones, isTrue);
    var state = const CopyState(pattern: [0, 1, 2, 0, 1, 2], at: 5, misses: 40);
    expect(pressCopy(state, 0, easy).result, CopyResult.miss);
    state = const CopyState(pattern: [0, 1, 2, 0, 1, 2], at: 5);
    expect(pressCopy(state, 2, easy).result, CopyResult.won);
  });

  test('every level has answers, and only the hardest is by ear', () {
    for (final level in Difficulty.values) {
      final rules = copyLevels[level]!;
      expect(rules.choices.length, greaterThanOrEqualTo(3));
      expect(rules.shown, level != Difficulty.expert);
      expect(copyLevelsText.containsKey(level), isTrue);
    }
    expect(copyNote(easy, 2), copyZoneNotes[2]);
    expect(copyNote(medium, 7), 67);
  });

  testWidgets('the screen plays the pattern, then takes it back and grows it', (tester) async {
    usePhone(tester, landscape: true);
    final synth = RecordingSynth();
    final services = await pumpApp(
      tester,
      CopyPage(difficulty: Difficulty.medium, random: _First()),
      synth: synth,
    );
    expect(find.text('Watch and listen'), findsOneWidget);
    // The pads are the level's notes; three hearts.
    for (final letter in ['C', 'E', 'G']) {
      expect(find.text(letter), findsOneWidget);
    }

    // The game plays its one note (C), then it is the player's turn.
    await tester.pump(const Duration(milliseconds: 1600));
    expect(synth.events, contains('blip 60'));
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.text('Your turn!'), findsOneWidget);

    // A key pressed while the pattern plays would only sound; now C counts.
    await _tapKey(tester, LogicalKeyboardKey.keyA);
    expect(find.text('Yes!'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);

    // The pattern is now C C: it plays, and is played back.
    await tester.pump(const Duration(milliseconds: 1100 + 300 + 2 * 700 + 50));
    expect(find.text('Your turn!'), findsOneWidget);
    await _tapKey(tester, LogicalKeyboardKey.keyA);
    await _tapKey(tester, LogicalKeyboardKey.keyA);
    expect(find.text('2'), findsOneWidget);

    // C C E: a wrong note shows it again, three times and the game is over.
    for (var miss = 1; miss <= 3; miss++) {
      await tester.pump(const Duration(milliseconds: 1300 + 300 + 3 * 700 + 50));
      expect(find.text('Your turn!'), findsOneWidget);
      await _tapKey(tester, LogicalKeyboardKey.keyG); // G: wrong
      if (miss < 3) expect(find.text('Watch again'), findsOneWidget);
    }
    expect(find.text('Out of hearts!'), findsOneWidget);
    expect(find.text('2 in a row'), findsOneWidget);
    expect(find.text('New best!'), findsOneWidget);
    expect(services.settings.best('copy.medium'), 2);

    // C plays again, once the end panel has settled.
    await tester.pump(const Duration(milliseconds: 1600));
    await _tapKey(tester, LogicalKeyboardKey.keyA);
    expect(find.text('Out of hearts!'), findsNothing);
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Your turn!'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('easy is the three parts of the keyboard, and six in a row wins', (tester) async {
    usePhone(tester, landscape: true);
    await pumpApp(tester, CopyPage(random: _First()), keyboard: false);
    // A pad and a part of the keyboard picture for each: low, middle, high.
    for (final name in ['Low', 'Middle', 'High']) {
      expect(find.text(name), findsNWidgets(2));
    }
    await tester.pump(const Duration(milliseconds: 1200));

    // Low Low Middle Low Low Middle, one note longer each time, on the pads.
    const pattern = ['Low', 'Low', 'Middle', 'Low', 'Low', 'Middle'];
    for (var length = 1; length <= pattern.length; length++) {
      await tester.pump(Duration(milliseconds: 1100 + 300 + length * 800 + 50));
      expect(find.text('Your turn!'), findsOneWidget);
      for (final name in pattern.take(length)) {
        await tester.tap(find.text(name).first);
        await tester.pump(const Duration(milliseconds: 50));
      }
    }
    expect(find.text('You did it!'), findsOneWidget);
    expect(find.text('YAY!'), findsOneWidget);

    // A new pattern starts by itself.
    await tester.pump(const Duration(milliseconds: 3100));
    expect(find.text('YAY!'), findsNothing);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Your turn!'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });
}
