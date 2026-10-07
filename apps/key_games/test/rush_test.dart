import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:key_games/audio/synth.dart';
import 'package:key_games/games/color_keys_rules.dart';
import 'package:key_games/games/difficulty.dart';
import 'package:key_games/games/rush_page.dart';
import 'package:key_games/games/rush_rules.dart';
import 'package:key_games/midi/midi_input.dart';

void main() {
  test('a hit scores and moves the target; any octave counts', () {
    final random = Random(1);
    const state = RushState(target: 4);
    final step = pressRush(state, 52, random, whitePitchClasses); // a low E
    expect(step.result, RushResult.hit);
    expect(step.state.score, 1);
    expect(step.state.target, isNot(4));
    expect(whitePitchClasses, contains(step.state.target));
  });

  test('a wrong key freezes scoring while the clock runs on', () {
    final random = Random(2);
    var step = pressRush(const RushState(target: 0), 62, random, whitePitchClasses);
    expect(step.result, RushResult.miss);
    expect(step.state.frozen, isTrue);
    expect(pressRush(step.state, 60, random, whitePitchClasses).result, RushResult.frozen);

    var state = step.state;
    for (var t = 0; t < rushFreezeMs; t += rushTickMs) {
      state = rushTick(state);
    }
    expect(state.frozen, isFalse);
    expect(state.elapsedMs, rushFreezeMs);
    step = pressRush(state, 60, random, whitePitchClasses);
    expect(step.result, RushResult.hit);
  });

  test('easy has no freeze; time runs out after a minute', () {
    final random = Random(3);
    final step = pressRush(const RushState(target: 0), 62, random, whitePitchClasses, freeze: false);
    expect(step.result, RushResult.miss);
    expect(step.state.frozen, isFalse);

    var state = const RushState(target: 0);
    for (var t = 0; t < rushGameMs; t += rushTickMs) {
      state = rushTick(state);
    }
    expect(state.over, isTrue);
    expect(state.timeLeft, 0);
    expect(pressRush(state, 60, random, whitePitchClasses).result, RushResult.over);
  });

  testWidgets('rush counts down, scores, ends, and C plays again', (tester) async {
    tester.view.physicalSize = const Size(1080, 2316);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);

    // The synth is never started here, so it stays silent.
    await tester.pumpWidget(MaterialApp(
      home: RushPage(
        synth: Synth(),
        midi: MidiInput(),
        difficulty: Difficulty.easy,
        random: Random(5),
        songs: const [],
      ),
    ));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('3'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 2200));
    expect(find.text('Song: Scale'), findsOneWidget);

    // Easy never freezes, so one pass over the white keys finds the target.
    for (final key in [
      LogicalKeyboardKey.keyA, LogicalKeyboardKey.keyS, LogicalKeyboardKey.keyD,
      LogicalKeyboardKey.keyF, LogicalKeyboardKey.keyG, LogicalKeyboardKey.keyH,
      LogicalKeyboardKey.keyJ,
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
}
