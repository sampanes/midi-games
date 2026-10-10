// Pure rules for the "Color Keys" game: a color is shown, the child presses a
// key of that color. Port of src/games/color-keys.js. No Flutter imports, so
// it is unit tested on its own.
//
// Only the pitch class (C, D, E, ...) matters. A keyboard's preset can move
// keys and pads to any channel and the octave buttons shift note numbers, so
// every key and pad does something however the keyboard is set up.

import 'dart:math';

class PitchClassInfo {
  const PitchClassInfo(this.name, this.argb, this.colorName, this.white);

  final String name;
  final int argb;
  final String colorName;
  final bool white;
}

// Rainbow order on the white keys (C red .. B pink); black keys get
// in-between shades.
const pitchClasses = [
  PitchClassInfo('C', 0xFFFF3B3B, 'RED', true),
  PitchClassInfo('C#', 0xFFFF6A2B, 'RED-ORANGE', false),
  PitchClassInfo('D', 0xFFFF9A1F, 'ORANGE', true),
  PitchClassInfo('D#', 0xFFFFC61F, 'GOLD', false),
  PitchClassInfo('E', 0xFFFFE81F, 'YELLOW', true),
  PitchClassInfo('F', 0xFF3DDC4A, 'GREEN', true),
  PitchClassInfo('F#', 0xFF22C9A0, 'TEAL', false),
  PitchClassInfo('G', 0xFF2FA8FF, 'BLUE', true),
  PitchClassInfo('G#', 0xFF4A6BFF, 'INDIGO', false),
  PitchClassInfo('A', 0xFF8A4DFF, 'PURPLE', true),
  PitchClassInfo('A#', 0xFFC04DFF, 'VIOLET', false),
  PitchClassInfo('B', 0xFFFF5EC8, 'PINK', true),
];

final whitePitchClasses = [
  for (var i = 0; i < pitchClasses.length; i++)
    if (pitchClasses[i].white) i,
];

// Notes outside this window are ignored. Very low notes are used by some
// keyboards for transport buttons, very high ones for DAW knob-touch messages.
const minGameNote = 12;
const maxGameNote = 103;

const starsPerRound = 8;

int pitchClass(int note) => note % 12;

// The note of pitch class [pc] closest to [note] (the higher one on a tie),
// so a wrong key can be compared with the right one next to it.
int nearestOfClass(int note, int pc) {
  final below = note - (note - pc) % 12;
  return note - below < 6 ? below : below + 12;
}

// The nearest note of [pc] that is actually visible between [low] and [high].
// This keeps relative-octave corrections without sounding a key beyond the
// keyboard picture at its low and high edges. Ties still prefer the higher key.
int nearestOfClassInRange(int note, int pc, int low, int high) {
  final first = low + (pc - pitchClass(low)) % 12;
  if (first > high) {
    throw ArgumentError('range $low..$high does not contain pitch class $pc');
  }
  var nearest = first;
  for (var candidate = first + 12; candidate <= high; candidate += 12) {
    if ((candidate - note).abs() <= (nearest - note).abs()) nearest = candidate;
  }
  return nearest;
}

bool isGameNote(int note) => note >= minGameNote && note <= maxGameNote;

final allPitchClasses = [for (var pc = 0; pc < 12; pc++) pc];

// Next target from [choices] (white keys unless given), never the same as
// the last one.
int pickNextTarget(int? previous, Random random, [List<int>? choices]) {
  final from = (choices ?? whitePitchClasses)
      .where((pc) => pc != previous)
      .toList();
  return from[random.nextInt(from.length)];
}

enum Effect { play, miss, hit, nextSoon, win }

class ColorKeysState {
  const ColorKeysState({
    required this.target,
    this.stars = 0,
    this.rounds = 0,
    this.locked = false,
  });

  factory ColorKeysState.start(Random random, [List<int>? choices]) =>
      ColorKeysState(target: pickNextTarget(null, random, choices));

  final int target;
  final int stars;
  final int rounds;

  // True between a hit and the next target, so extra presses only make sound.
  final bool locked;

  ColorKeysState copyWith({
    int? target,
    int? stars,
    int? rounds,
    bool? locked,
  }) => ColorKeysState(
    target: target ?? this.target,
    stars: stars ?? this.stars,
    rounds: rounds ?? this.rounds,
    locked: locked ?? this.locked,
  );
}

class PressResult {
  const PressResult(this.state, this.effects);

  final ColorKeysState state;
  final List<Effect> effects;
}

PressResult pressNote(ColorKeysState state, int note) {
  if (state.locked) return PressResult(state, const [Effect.play]);
  if (pitchClass(note) != state.target) {
    return PressResult(state, const [Effect.miss]);
  }
  final stars = state.stars + 1;
  final next = state.copyWith(stars: stars, locked: true);
  if (stars >= starsPerRound) {
    return PressResult(next, const [Effect.hit, Effect.win]);
  }
  return PressResult(next, const [Effect.hit, Effect.nextSoon]);
}

// Notes that arrive together are one attempt. More than one distinct key is a
// miss even when one of the keys happens to be the target.
PressResult pressColorAttempt(ColorKeysState state, Iterable<int> notes) {
  final distinct = notes.toSet();
  if (distinct.isEmpty) return PressResult(state, const []);
  if (state.locked) return PressResult(state, const [Effect.play]);
  if (distinct.length > 1) return PressResult(state, const [Effect.miss]);
  return pressNote(state, distinct.single);
}

ColorKeysState advance(
  ColorKeysState state,
  Random random, [
  List<int>? choices,
]) {
  final target = pickNextTarget(state.target, random, choices);
  if (state.stars >= starsPerRound) {
    return ColorKeysState(target: target, rounds: state.rounds + 1);
  }
  return state.copyWith(target: target, locked: false);
}
