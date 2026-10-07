// Pure rules for "Key Rush", after the arcade piano games: one minute to hit
// as many target keys as possible. The target jumps after every hit. A wrong
// key freezes scoring for a moment while the clock keeps running (the game
// uses that moment to play the wrong note and then the right one). Time is
// counted in ticks so the rules are exact in tests.

import 'dart:math';

import 'color_keys_rules.dart';

const rushTickMs = 100;
const rushGameMs = 60000;
const rushFreezeMs = 1600;

enum RushResult { hit, miss, frozen, over }

class RushState {
  const RushState({
    required this.target,
    this.score = 0,
    this.misses = 0,
    this.elapsedMs = 0,
    this.frozenMs = 0,
  });

  factory RushState.start(Random random, List<int> choices) =>
      RushState(target: pickNextTarget(null, random, choices));

  final int target;
  final int score;
  final int misses;
  final int elapsedMs;

  // Time left in the current freeze.
  final int frozenMs;

  bool get over => elapsedMs >= rushGameMs;
  bool get frozen => frozenMs > 0;
  double get timeLeft => max(0, 1 - elapsedMs / rushGameMs);

  RushState copyWith({int? target, int? score, int? misses, int? elapsedMs, int? frozenMs}) =>
      RushState(
        target: target ?? this.target,
        score: score ?? this.score,
        misses: misses ?? this.misses,
        elapsedMs: elapsedMs ?? this.elapsedMs,
        frozenMs: frozenMs ?? this.frozenMs,
      );
}

RushState rushTick(RushState state) => state.copyWith(
      elapsedMs: min(rushGameMs, state.elapsedMs + rushTickMs),
      frozenMs: max(0, state.frozenMs - rushTickMs),
    );

// Any octave counts. [freeze] is off on the easiest level.
({RushState state, RushResult result}) pressRush(
  RushState state,
  int note,
  Random random,
  List<int> choices, {
  bool freeze = true,
}) {
  if (state.over) return (state: state, result: RushResult.over);
  if (state.frozen) return (state: state, result: RushResult.frozen);
  if (pitchClass(note) != state.target) {
    return (
      state: state.copyWith(misses: state.misses + 1, frozenMs: freeze ? rushFreezeMs : 0),
      result: RushResult.miss,
    );
  }
  return (
    state: state.copyWith(
      score: state.score + 1,
      target: pickNextTarget(state.target, random, choices),
    ),
    result: RushResult.hit,
  );
}
