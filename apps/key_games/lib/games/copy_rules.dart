// Pure rules for "Copy Cat", after the light-and-sound memory toys: the game
// plays a pattern of notes and the player plays it back. A pattern played
// back right grows by one note and plays again. A wrong note is never a
// dead end: the same pattern plays again.
//
// The answers are parts of the keyboard on Easy (low, middle, high: any key
// in the part counts, see zones.dart) and letters on the other levels, any
// octave. A key that is not one of the level's answers only sounds.
//
// Easy has no way to lose: a pattern that reaches [CopyLevel.winLength] is a
// win, and a new one starts. The other levels have hearts: each wrong note
// costs one, and the game ends when they are gone. The score is the longest
// pattern played back.

import 'dart:math';

import 'difficulty.dart';

class CopyLevel {
  const CopyLevel({
    required this.choices,
    required this.stepMs,
    this.zones = false,
    this.hearts,
    this.winLength,
    this.shown = true,
  });

  // The answers: pitch classes, or parts of the keyboard when [zones].
  final List<int> choices;
  final bool zones;

  // Time from one note of the pattern to the next when the game plays it.
  final int stepMs;

  // Wrong notes allowed; null for any number.
  final int? hearts;

  // A pattern this long, played back, wins; null and it grows for ever.
  final int? winLength;

  // The pattern lights up as it plays. False: by ear alone.
  final bool shown;
}

const copyZoneCount = 3;

const copyLevels = {
  Difficulty.easy: CopyLevel(choices: [0, 1, 2], zones: true, stepMs: 800, winLength: 6),
  Difficulty.medium: CopyLevel(choices: [0, 4, 7], stepMs: 700, hearts: 3),
  Difficulty.hard: CopyLevel(choices: [0, 2, 4, 5, 7], stepMs: 620, hearts: 3),
  Difficulty.expert:
      CopyLevel(choices: [0, 2, 4, 5, 7, 9, 11], stepMs: 560, hearts: 3, shown: false),
};

// What each part of the keyboard sounds like on Easy: low C, middle E and
// high G, far enough apart to tell by ear.
const copyZoneNotes = [48, 64, 79];

// The note an answer sounds as when the game plays the pattern.
int copyNote(CopyLevel level, int answer) => level.zones ? copyZoneNotes[answer] : 60 + answer;

enum CopyResult { hit, patternDone, won, miss, over, ignored }

class CopyState {
  const CopyState({required this.pattern, this.at = 0, this.misses = 0, this.best = 0});

  factory CopyState.start(CopyLevel level, Random random) =>
      CopyState(pattern: [_next(level, const [], random)]);

  final List<int> pattern;

  // Notes of the pattern played back so far on this try.
  final int at;

  // Wrong notes so far in this game.
  final int misses;

  // The longest pattern played back in this game.
  final int best;

  int heartsLeft(CopyLevel level) => max(0, (level.hearts ?? 0) - misses);
}

// The next note of a pattern: any answer, but never a third of the same in a
// row.
int _next(CopyLevel level, List<int> pattern, Random random) {
  final n = pattern.length;
  final stuck = n >= 2 && pattern[n - 1] == pattern[n - 2] ? pattern[n - 1] : null;
  final from = [
    for (final choice in level.choices)
      if (choice != stuck) choice,
  ];
  return from[random.nextInt(from.length)];
}

// [answer] is the pitch class of the key pressed, or on Easy the part of the
// keyboard it is in.
({CopyState state, CopyResult result}) pressCopy(CopyState state, int answer, CopyLevel level) {
  if (!level.choices.contains(answer) || state.at >= state.pattern.length) {
    return (state: state, result: CopyResult.ignored);
  }
  if (answer != state.pattern[state.at]) {
    final misses = state.misses + 1;
    final missed =
        CopyState(pattern: state.pattern, misses: misses, best: state.best);
    final hearts = level.hearts;
    return (
      state: missed,
      result: hearts != null && misses >= hearts ? CopyResult.over : CopyResult.miss,
    );
  }
  final at = state.at + 1;
  if (at < state.pattern.length) {
    return (
      state: CopyState(pattern: state.pattern, at: at, misses: state.misses, best: state.best),
      result: CopyResult.hit,
    );
  }
  final done = CopyState(
    pattern: state.pattern,
    at: at,
    misses: state.misses,
    best: max(state.best, at),
  );
  return (state: done, result: at == level.winLength ? CopyResult.won : CopyResult.patternDone);
}

// The same pattern one note longer, to play back from its start.
CopyState growCopy(CopyState state, CopyLevel level, Random random) => CopyState(
      pattern: [...state.pattern, _next(level, state.pattern, random)],
      misses: state.misses,
      best: state.best,
    );
