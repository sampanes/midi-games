// Pure rules for "Key Runner" (Temple Run style, Arcade): a runner on three
// lanes dodges rocks and grabs coins. The keys are just buttons that pick a
// lane; which keys depends on the level:
// - Easy: the low, middle or high part of the keyboard. No hearts to lose,
//   a one-minute run.
// - Medium: the letters C, E and G.
// - Hard: three letters (sharps too) that change every 20 seconds.
// - Expert: faster, the letters change every 12 seconds, no colors.
// Above Easy a run goes on, slowly speeding up, until three hearts are lost.
// Times are in ms from GO.

import 'dart:math';

import 'difficulty.dart';

const laneCount = 3;
const runnerTimedMs = 60000;

// After a crash, rocks are passed through for this long.
const crashGraceMs = 1000;

class RunnerLevel {
  const RunnerLevel({
    required this.rowGapMs,
    required this.lookAheadMs,
    required this.hearts,
    required this.twoRockChance,
    required this.signChangeMs,
  });

  // Time between rows of rocks at the start.
  final int rowGapMs;

  // How long a thing is on screen before it reaches the runner.
  final int lookAheadMs;

  // 0: no hearts, the run lasts [runnerTimedMs].
  final int hearts;

  // Chance that a row has two rocks (one free lane) instead of one.
  final double twoRockChance;

  // 0: the lane letters never change.
  final int signChangeMs;
}

const runnerLevels = {
  Difficulty.easy: RunnerLevel(
      rowGapMs: 2600, lookAheadMs: 3000, hearts: 0, twoRockChance: 0, signChangeMs: 0),
  Difficulty.medium: RunnerLevel(
      rowGapMs: 1900, lookAheadMs: 2600, hearts: 3, twoRockChance: 0.35, signChangeMs: 0),
  Difficulty.hard: RunnerLevel(
      rowGapMs: 1600, lookAheadMs: 2300, hearts: 3, twoRockChance: 0.6, signChangeMs: 20000),
  Difficulty.expert: RunnerLevel(
      rowGapMs: 1300, lookAheadMs: 1900, hearts: 3, twoRockChance: 0.75, signChangeMs: 12000),
};

// Medium's lane letters.
const runnerMediumKeys = [0, 4, 7];

// Easy: which third of the keyboard (from its lowest C, [base]) a key is in.
int zoneLane(int note, int base) => ((note - base) ~/ 12).clamp(0, laneCount - 1);

// The lane whose letter is [note]'s, if any.
int? letterLane(int note, List<int> keys) {
  final i = keys.indexOf(note % 12);
  return i < 0 ? null : i;
}

// Three different letters from [pool], low to high, not the same set as
// [previous] when that can be helped.
List<int> pickLaneKeys(Random random, List<int> pool, [List<int>? previous]) {
  for (var tries = 0; ; tries++) {
    final keys = (List<int>.of(pool)..shuffle(random)).take(laneCount).toList()..sort();
    if (previous == null || tries > 20 || keys.join() != previous.join()) return keys;
  }
}

enum ThingKind { rock, coin }

class Thing {
  const Thing(this.kind, this.lane, this.atMs);

  final ThingKind kind;
  final int lane;

  // When it reaches the runner.
  final int atMs;
}

enum RunnerEvent { coin, crash }

class RunnerRun {
  RunnerRun(this.level, this.random) : hearts = level.hearts;

  final RunnerLevel level;
  final Random random;

  int lane = 1;
  int hearts;
  int coins = 0;
  int nowMs = 0;
  int crashedAt = -crashGraceMs;
  final List<Thing> things = [];
  late int _nextRowMs = level.lookAheadMs + 600;

  bool get timed => level.hearts == 0;
  bool get over => timed ? nowMs >= runnerTimedMs : hearts <= 0;
  double get timeLeft => timed ? max(0, 1 - nowMs / runnerTimedMs) : 1;
  bool get stumbling => nowMs - crashedAt < crashGraceMs;

  // Endless runs speed up over three minutes to 60% of the gaps.
  double get pace => timed ? 1 : max(0.6, 1 - nowMs / 180000 * 0.4);
  int get lookAheadMs => (level.lookAheadMs * pace).round();

  // Which set of lane letters is up (changes every [signChangeMs]).
  int get signs => level.signChangeMs == 0 ? 0 : nowMs ~/ level.signChangeMs;

  void moveTo(int to) {
    if (!over) lane = to.clamp(0, laneCount - 1);
  }

  // Moves time on: new rows come into view, things that reach the runner
  // are collected or crashed into.
  List<RunnerEvent> advance(int toMs) {
    if (over) return const [];
    nowMs = toMs;
    while (_nextRowMs <= nowMs + lookAheadMs) {
      _addRow(_nextRowMs);
      _nextRowMs += (level.rowGapMs * pace).round();
    }
    final events = <RunnerEvent>[];
    things.removeWhere((t) {
      if (t.atMs > nowMs) return false;
      if (t.lane != lane) return true;
      if (t.kind == ThingKind.coin) {
        coins++;
        events.add(RunnerEvent.coin);
      } else if (!stumbling) {
        crashedAt = nowMs;
        if (!timed) hearts--;
        events.add(RunnerEvent.crash);
      }
      return true;
    });
    return events;
  }

  // One or two rocks (never all three lanes), a coin in a free lane now and
  // then, and a short coin trail halfway to the next row.
  void _addRow(int at) {
    final lanes = [0, 1, 2]..shuffle(random);
    final rocks = random.nextDouble() < level.twoRockChance ? 2 : 1;
    for (final l in lanes.take(rocks)) {
      things.add(Thing(ThingKind.rock, l, at));
    }
    if (random.nextBool()) things.add(Thing(ThingKind.coin, lanes.last, at));
    final gap = (level.rowGapMs * pace).round();
    final trail = random.nextInt(laneCount);
    for (var i = 1; i <= 3; i++) {
      things.add(Thing(ThingKind.coin, trail, at + gap * i ~/ 4));
    }
    things.sort((a, b) => a.atMs.compareTo(b.atMs));
  }
}
