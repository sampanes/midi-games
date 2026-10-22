// Pure rules for "Key Rush", after the arcade piano games: one minute to hit
// as many keys as possible. A board above the keys shows the next few keys
// to press, like the falling tiles on an arcade piano.
//
// Three ways to play:
// - Easy: the low, middle or high part of the keyboard (see zones.dart): any
//   key in the part counts, so mashing works. The hits play a song, whatever
//   key was pressed.
// - Medium: the keys C, E and G, any octave counts. The hits play a song too.
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

// Medium: the one octave shown, and its three keys.
const rushKeysLow = 60;
const rushKeysHigh = 72;
const rushKeys = [60, 64, 67];

// Easy: the parts of the keyboard, as lanes 0 (low) to 2 (high).
const rushZoneCount = 3;
const rushZones = [0, 1, 2];

// How far (in places in the list) the next key may be from the last.
const rushMaxStep = 2;

enum RushResult { hit, miss, frozen, over }

// Where the keys to press come from.
abstract class RushFeed {
  int next(int? last);
}

// Easy and Medium: a short walk over [keys] (Medium's keys, or Easy's
// parts), never the same one twice in a row.
class WalkRushFeed implements RushFeed {
  WalkRushFeed(this.random, this.keys);

  final Random random;
  final List<int> keys;

  @override
  int next(int? last) {
    final at = last == null ? -1 : keys.indexOf(last);
    final from = [
      for (var i = 0; i < keys.length; i++)
        if (at < 0 || (i != at && (i - at).abs() <= rushMaxStep)) keys[i],
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

// [exact] needs the very key (Real, or Easy's part number); otherwise any
// octave counts (Medium).
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
