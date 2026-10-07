// Pure rules for "Ear Notes": a mystery note plays and the child finds it by
// sound alone. No colors or glow until they have tried twice, then the answer
// lights up so nobody is ever stuck. Like Color Keys, any octave counts.
//
// Levels start with two far-apart notes and grow to all twelve.

import 'dart:math';

import 'color_keys_rules.dart' show pitchClass;

const earLevels = [
  [0, 7], // C G
  [0, 4, 7], // C E G
  [0, 2, 4, 5, 7], // C D E F G
  [0, 2, 4, 5, 7, 9, 11], // all white keys
  [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11], // black keys too
];

const earStarsPerLevel = 6;

// Wrong tries before the answer lights up.
const earMissesBeforeReveal = 2;

int pickEarTarget(int level, int? previous, Random random) {
  final choices = earLevels[level].where((pc) => pc != previous).toList();
  return choices[random.nextInt(choices.length)];
}

enum EarEffect { miss, reveal, hit, found, nextSoon, levelUp }

class EarState {
  const EarState({
    required this.level,
    required this.target,
    this.stars = 0,
    this.misses = 0,
    this.locked = false,
  });

  factory EarState.start(int level, Random random) =>
      EarState(level: level, target: pickEarTarget(level, null, random));

  final int level;
  final int target;
  final int stars;

  // Wrong tries on this note.
  final int misses;

  // True between finding the note and the next one, so extra presses only
  // make sound.
  final bool locked;

  bool get revealed => misses >= earMissesBeforeReveal;
  List<int> get choices => earLevels[level];
  bool get lastLevel => level >= earLevels.length - 1;
}

class EarPress {
  const EarPress(this.state, this.effects);

  final EarState state;
  final List<EarEffect> effects;
}

EarPress pressEarNote(EarState state, int note) {
  if (state.locked) return EarPress(state, const []);
  if (pitchClass(note) != state.target) {
    final missed = EarState(
      level: state.level,
      target: state.target,
      stars: state.stars,
      misses: state.misses + 1,
    );
    if (missed.misses == earMissesBeforeReveal) {
      return EarPress(missed, const [EarEffect.miss, EarEffect.reveal]);
    }
    return EarPress(missed, const [EarEffect.miss]);
  }
  // Found by ear earns a star; found after the reveal is still a happy
  // moment, just without the star.
  final earned = !state.revealed;
  final stars = state.stars + (earned ? 1 : 0);
  final next = EarState(
    level: state.level,
    target: state.target,
    stars: stars,
    misses: state.misses,
    locked: true,
  );
  if (stars >= earStarsPerLevel) return EarPress(next, const [EarEffect.hit, EarEffect.levelUp]);
  return EarPress(next, [earned ? EarEffect.hit : EarEffect.found, EarEffect.nextSoon]);
}

// The next mystery note. A full row of stars moves up a level (the last level
// just starts a new row).
EarState advanceEar(EarState state, Random random) {
  if (state.stars >= earStarsPerLevel) {
    final level = state.lastLevel ? state.level : state.level + 1;
    return EarState.start(level, random);
  }
  return EarState(
    level: state.level,
    target: pickEarTarget(state.level, state.target, random),
    stars: state.stars,
  );
}
