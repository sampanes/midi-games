import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:key_games/games/color_keys_rules.dart';
import 'package:key_games/midi/mirror_filter.dart';
import 'package:key_games/widgets/piano_strip.dart';

void main() {
  test('pitch class ignores octave', () {
    expect(pitchClass(60), 0);
    expect(pitchClass(73), 1);
    expect(pitchClass(12), 0);
  });

  test('targets are white keys and never repeat', () {
    final random = Random(7);
    var previous = pickNextTarget(null, random);
    for (var i = 0; i < 200; i++) {
      final next = pickNextTarget(previous, random);
      expect(whitePitchClasses, contains(next));
      expect(next, isNot(previous));
      previous = next;
    }
  });

  test('any octave of the target color is a hit', () {
    const state = ColorKeysState(target: 4); // E, yellow
    final result = pressNote(state, 40); // E2
    expect(result.effects, [Effect.hit, Effect.nextSoon]);
    expect(result.state.stars, 1);
    expect(result.state.locked, isTrue);
  });

  test('wrong color is a miss and changes nothing', () {
    const state = ColorKeysState(target: 4, stars: 3);
    final result = pressNote(state, 60);
    expect(result.effects, [Effect.miss]);
    expect(result.state, same(state));
  });

  test('two-note attempt is one miss even when it contains the target', () {
    const state = ColorKeysState(target: 7, stars: 3);
    final result = pressColorAttempt(state, [67, 60]);
    expect(result.effects, [Effect.miss]);
    expect(result.state, same(state));
  });

  test('presses while locked only play', () {
    const state = ColorKeysState(target: 4, stars: 1, locked: true);
    expect(pressNote(state, 64).effects, [Effect.play]);
  });

  test('eighth star wins and advance starts a new round', () {
    final random = Random(1);
    const state = ColorKeysState(target: 0, stars: starsPerRound - 1);
    final result = pressNote(state, 72);
    expect(result.effects, [Effect.hit, Effect.win]);
    final next = advance(result.state, random);
    expect(next.stars, 0);
    expect(next.rounds, 1);
    expect(next.locked, isFalse);
    expect(next.target, isNot(0));
  });

  test('advance mid-round keeps stars and unlocks', () {
    final next = advance(
      const ColorKeysState(target: 2, stars: 3, locked: true),
      Random(3),
    );
    expect(next.stars, 3);
    expect(next.locked, isFalse);
    expect(next.target, isNot(2));
  });

  test('game note window', () {
    expect(isGameNote(minGameNote), isTrue);
    expect(isGameNote(maxGameNote), isTrue);
    expect(isGameNote(minGameNote - 1), isFalse);
    expect(isGameNote(maxGameNote + 1), isFalse);
  });

  group('mirror filter', () {
    test('drops the same message from another device inside the window', () {
      final filter = MirrorFilter();
      expect(filter.accept('usb', 'on/60/100', 1000), isTrue);
      expect(filter.accept('ble', 'on/60/100', 1020), isFalse);
    });

    test('passes repeats from the same device and late copies', () {
      final filter = MirrorFilter();
      expect(filter.accept('usb', 'on/60/100', 1000), isTrue);
      expect(filter.accept('usb', 'on/60/100', 1010), isTrue);
      expect(filter.accept('ble', 'on/60/100', 1200), isTrue);
    });
  });

  test('keyboard picture follows octave shifts in whole octaves', () {
    expect(fitBase(48, 60), 48);
    expect(fitBase(48, 84), 48); // top C of 37 keys
    expect(fitBase(48, 85), 60);
    expect(fitBase(48, 36), 36);
    expect(fitBase(48, 30), 24);
  });

  test('relative correction stays inside the displayed keyboard', () {
    expect(nearestOfClassInRange(48, 11, 48, 84), 59); // B below is hidden
    expect(nearestOfClassInRange(84, 6, 48, 84), 78); // F# above is hidden
    expect(nearestOfClassInRange(66, 0, 48, 84), 72); // in-range tie goes up
  });
}
