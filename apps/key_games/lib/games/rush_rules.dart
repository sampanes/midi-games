// Pure rules for "Key Rush", after the arcade piano games: one minute to hit
// as many keys as possible. A board above the keys shows the next few keys
// to press, like the falling tiles on an arcade piano.
//
// Two ways to play:
// - Easy: four white keys in the middle of one octave (E F G A above middle
//   C), any octave counts, and the next key is never more than two keys
//   away. The hits play a song, whatever key was pressed.
// - Real: the keys are the real notes of a song, in order, octave included,
//   and each key sounds as itself. A wrong key freezes scoring for a moment
//   while the clock keeps running (the game uses that moment to play the
//   wrong note and then the right one).
//
// Time is counted in ticks so the rules are exact in tests.

import 'dart:math';

import 'color_keys_rules.dart';

const rushTickMs = 100;
const rushGameMs = 60000;
const rushFreezeMs = 1600;

// Rows on the board: the key to press now plus the ones after it.
const rushRows = 4;

// Easy: the one octave shown, and the four keys in its middle.
const rushEasyLow = 60;
const rushEasyHigh = 72;
const rushEasyKeys = [64, 65, 67, 69];

// How far (in keys of rushEasyKeys) the next Easy key may be from the last.
const rushEasyMaxStep = 2;

enum RushResult { hit, miss, frozen, over }

// Where the keys to press come from.
abstract class RushFeed {
  int next(int? last);
}

// Easy: a short walk over rushEasyKeys, never the same key twice in a row.
class EasyRushFeed implements RushFeed {
  EasyRushFeed(this.random);

  final Random random;

  @override
  int next(int? last) {
    final at = last == null ? -1 : rushEasyKeys.indexOf(last);
    final from = [
      for (var i = 0; i < rushEasyKeys.length; i++)
        if (at < 0 || (i != at && (i - at).abs() <= rushEasyMaxStep)) rushEasyKeys[i],
    ];
    return from[random.nextInt(from.length)];
  }
}

// Real: a song's notes in order, starting over at the end.
class SongRushFeed implements RushFeed {
  SongRushFeed(this.notes);

  final List<int> notes;
  int _index = 0;

  @override
  int next(int? last) => notes[_index++ % notes.length];
}

class RushState {
  const RushState({
    required this.upcoming,
    this.score = 0,
    this.misses = 0,
    this.elapsedMs = 0,
    this.frozenMs = 0,
  });

  factory RushState.start(RushFeed feed) {
    final upcoming = <int>[];
    for (var i = 0; i < rushRows; i++) {
      upcoming.add(feed.next(upcoming.isEmpty ? null : upcoming.last));
    }
    return RushState(upcoming: upcoming);
  }

  // The key to press now, then the next ones (rushRows of them).
  final List<int> upcoming;
  final int score;
  final int misses;
  final int elapsedMs;

  // Time left in the current freeze.
  final int frozenMs;

  int get target => upcoming.first;
  bool get over => elapsedMs >= rushGameMs;
  bool get frozen => frozenMs > 0;
  double get timeLeft => max(0, 1 - elapsedMs / rushGameMs);

  RushState copyWith({
    List<int>? upcoming,
    int? score,
    int? misses,
    int? elapsedMs,
    int? frozenMs,
  }) =>
      RushState(
        upcoming: upcoming ?? this.upcoming,
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

// [exact] needs the very key (Real); otherwise any octave counts (Easy).
// [freeze] stops scoring for a moment after a wrong key.
({RushState state, RushResult result}) pressRush(
  RushState state,
  int note,
  RushFeed feed, {
  bool exact = false,
  bool freeze = false,
}) {
  if (state.over) return (state: state, result: RushResult.over);
  if (state.frozen) return (state: state, result: RushResult.frozen);
  final right = exact ? note == state.target : pitchClass(note) == pitchClass(state.target);
  if (!right) {
    return (
      state: state.copyWith(misses: state.misses + 1, frozenMs: freeze ? rushFreezeMs : 0),
      result: RushResult.miss,
    );
  }
  final rest = state.upcoming.sublist(1);
  return (
    state: state.copyWith(
      score: state.score + 1,
      upcoming: [...rest, feed.next(rest.isEmpty ? state.target : rest.last)],
    ),
    result: RushResult.hit,
  );
}
