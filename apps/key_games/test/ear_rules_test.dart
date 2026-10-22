import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:key_games/games/ear_rules.dart';

void main() {
  test('targets come from the level and never repeat', () {
    final random = Random(1);
    for (var level = 0; level < earLevels.length; level++) {
      int? previous;
      for (var i = 0; i < 50; i++) {
        final target = pickEarTarget(level, previous, random);
        expect(earLevels[level], contains(target));
        expect(target, isNot(previous));
        previous = target;
      }
    }
  });

  test('the first level is high or low: the answer is the half of the keyboard', () {
    const state = EarState(level: earZoneLevel, target: 1);
    expect(state.zoned, isTrue);
    expect(pressEarNote(state, 0).effects, [EarEffect.miss]);
    expect(pressEarNote(state, 1).effects, [EarEffect.hit, EarEffect.nextSoon]);
    expect(const EarState(level: 1, target: 7).zoned, isFalse);
  });

  test('with only the choices counting, other keys just sound', () {
    const state = EarState(level: 1, target: 7);
    expect(pressEarNote(state, 62, onlyChoices: true).effects, isEmpty);
    expect(pressEarNote(state, 62, onlyChoices: true).state.misses, 0);
    expect(pressEarNote(state, 60, onlyChoices: true).effects, [EarEffect.miss]);
    expect(pressEarNote(state, 62).effects, [EarEffect.miss]);
  });

  test('right note in any octave earns a star and locks', () {
    const state = EarState(level: 1, target: 7);
    final press = pressEarNote(state, 43); // a low G
    expect(press.effects, [EarEffect.hit, EarEffect.nextSoon]);
    expect(press.state.stars, 1);
    expect(press.state.locked, isTrue);
    expect(pressEarNote(press.state, 60).effects, isEmpty);
  });

  test('two wrong tries reveal the answer; finding it then earns no star', () {
    var press = pressEarNote(const EarState(level: 1, target: 7, stars: 2), 60);
    expect(press.effects, [EarEffect.miss]);
    expect(press.state.revealed, isFalse);
    press = pressEarNote(press.state, 62);
    expect(press.effects, [EarEffect.miss, EarEffect.reveal]);
    expect(press.state.revealed, isTrue);
    press = pressEarNote(press.state, 67);
    expect(press.effects, [EarEffect.found, EarEffect.nextSoon]);
    expect(press.state.stars, 2);
  });

  test('a full row of stars moves up a level, the last level stays', () {
    final random = Random(2);
    final press = pressEarNote(
        const EarState(level: 2, target: 4, stars: earStarsPerLevel - 1), 64);
    expect(press.effects, [EarEffect.hit, EarEffect.levelUp]);
    final next = advanceEar(press.state, random);
    expect(next.level, 3);
    expect(next.stars, 0);
    expect(next.locked, isFalse);

    final last = earLevels.length - 1;
    final top = advanceEar(
        EarState(level: last, target: 3, stars: earStarsPerLevel, locked: true), random);
    expect(top.level, last);
    expect(top.stars, 0);
  });

  test('a normal advance keeps stars and clears misses', () {
    final next = advanceEar(
        const EarState(level: 2, target: 5, stars: 3, misses: 2, locked: true), Random(3));
    expect(next.stars, 3);
    expect(next.misses, 0);
    expect(next.locked, isFalse);
    expect(next.target, isNot(5));
  });
}
