import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:key_games/audio/synth.dart';
import 'package:key_games/games/color_keys_rules.dart';
import 'package:key_games/games/difficulty.dart';
import 'package:key_games/games/runner_page.dart';
import 'package:key_games/games/runner_rules.dart';
import 'package:key_games/midi/midi_input.dart';
import 'package:key_games/widgets/piano_strip.dart';

RunnerRun _emptyRun(Difficulty d) {
  final run = RunnerRun(runnerLevels[d]!, Random(1));
  run.advance(0);
  run.things.clear();
  return run;
}

void main() {
  test('easy lanes are the low, middle and high part of the keyboard', () {
    expect(zoneLane(50, 48), 0);
    expect(zoneLane(62, 48), 1);
    expect(zoneLane(80, 48), 2);
    expect(zoneLane(84, 48), 2);
    expect(zoneLane(40, 48), 0);
  });

  test('letter lanes, and new letters differ from the old ones', () {
    expect(letterLane(64, runnerMediumKeys), 1);
    expect(letterLane(79, runnerMediumKeys), 2);
    expect(letterLane(62, runnerMediumKeys), isNull);

    final random = Random(4);
    var keys = pickLaneKeys(random, allPitchClasses);
    for (var i = 0; i < 20; i++) {
      final next = pickLaneKeys(random, allPitchClasses, keys);
      expect(next.toSet().length, laneCount);
      expect(next, orderedEquals([...next]..sort()));
      expect(next.join(), isNot(keys.join()));
      keys = next;
    }
  });

  test('a row never blocks all three lanes', () {
    for (final d in Difficulty.values) {
      final run = RunnerRun(runnerLevels[d]!, Random(7));
      final rocks = <int, int>{};
      for (var t = 0; t <= 50000; t += 50) {
        run.advance(t);
        for (final thing in run.things.where((x) => x.kind == ThingKind.rock)) {
          rocks[thing.atMs] = run.things.where((x) => x.kind == ThingKind.rock && x.atMs == thing.atMs).length;
        }
      }
      expect(rocks, isNotEmpty);
      expect(rocks.values.every((n) => n <= 2), isTrue, reason: d.name);
    }
  });

  test('coins are collected in your lane; rocks cost a heart, then a moment of grace', () {
    final run = _emptyRun(Difficulty.medium);
    run.things.addAll(const [
      Thing(ThingKind.coin, 1, 100),
      Thing(ThingKind.coin, 2, 150),
      Thing(ThingKind.rock, 1, 200),
      Thing(ThingKind.rock, 1, 500),
      Thing(ThingKind.rock, 0, 1400),
      Thing(ThingKind.rock, 1, 1500),
    ]);
    expect(run.advance(150), [RunnerEvent.coin]);
    expect(run.coins, 1);
    expect(run.advance(200), [RunnerEvent.crash]);
    expect(run.hearts, 2);
    expect(run.advance(500), isEmpty); // still stumbling
    run.moveTo(0);
    expect(run.advance(1400), [RunnerEvent.crash]);
    run.moveTo(2);
    expect(run.advance(1500), isEmpty); // dodged
    expect(run.hearts, 1);
  });

  test('easy has no hearts and lasts a minute; hard changes letters', () {
    final easy = _emptyRun(Difficulty.easy);
    easy.things.add(const Thing(ThingKind.rock, 1, 100));
    expect(easy.advance(100), [RunnerEvent.crash]);
    expect(easy.hearts, 0);
    expect(easy.over, isFalse);
    easy.advance(runnerTimedMs);
    expect(easy.over, isTrue);

    final hard = _emptyRun(Difficulty.hard);
    expect(hard.signs, 0);
    hard.advance(20000);
    expect(hard.signs, 1);
  });

  testWidgets('key runner counts down, runs a minute on easy, and C plays again', (tester) async {
    tester.view.physicalSize = const Size(2316, 1080);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);

    // The synth is never started here, so it stays silent.
    await tester.pumpWidget(MaterialApp(
      home: RunnerPage(synth: Synth(), midi: MidiInput(), random: Random(3), songs: const []),
    ));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('3'), findsOneWidget);
    expect(find.text('Middle'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 2200));

    // Hop between lanes for most of the minute (a C after the end would
    // pick Play again), then let the time run out.
    for (var i = 0; i < 55; i++) {
      await tester.sendKeyEvent(i.isEven ? LogicalKeyboardKey.keyA : LogicalKeyboardKey.keyK);
      await tester.pump(const Duration(seconds: 1));
    }
    for (var i = 0; i < 7; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(find.text("Time's up!"), findsOneWidget);
    expect(find.textContaining('coins'), findsWidgets);
    // The keyboard picture is gone, so the end choices fit.
    expect(find.byType(PianoStrip), findsNothing);

    await tester.pump(const Duration(seconds: 2));
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA); // C: play again
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('3'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  });
}
