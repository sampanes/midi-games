// Pure rules for "Note Highway" (falling notes, Guitar Hero style): a song's
// notes fall in lanes and are hit as they reach the line. Each lane is the
// note that sounds when it is hit.
//
// Notes are never made up. A chart is built from a song per difficulty; the
// song's notes that are not for the player (too fast, or off the level's
// keys) are played by the game itself, so the tune is always whole:
// - Easy: the song moved to the white keys (when it is not there already),
//   and the player gets the notes on the five neighboring white keys that
//   cover the most of it (C to G for most songs). Slow, fast runs thinned.
// - Medium: all the white-key notes.
// - Hard: every letter, sharps and flats too, any octave.
// - Expert: the exact keys (the song moved by octaves onto the keyboard).

import 'dart:math';

import '../songs/song.dart';
import 'color_keys_rules.dart';
import 'difficulty.dart';

class HighwayLevel {
  const HighwayLevel({
    required this.speed,
    required this.minGapMs,
    required this.windowMs,
    required this.lookAheadMs,
  });

  // Song tempo factor (0.75 = slower).
  final double speed;

  // Notes closer than this (after the tempo change) are dropped.
  final int minGapMs;

  // A note can be hit this early or late.
  final int windowMs;

  // How long a note is on screen before it reaches the line.
  final int lookAheadMs;
}

const highwayLevels = {
  Difficulty.easy: HighwayLevel(speed: 0.75, minGapMs: 550, windowMs: 260, lookAheadMs: 3200),
  Difficulty.medium: HighwayLevel(speed: 0.85, minGapMs: 330, windowMs: 200, lookAheadMs: 2600),
  Difficulty.hard: HighwayLevel(speed: 1, minGapMs: 180, windowMs: 150, lookAheadMs: 2100),
  Difficulty.expert: HighwayLevel(speed: 1, minGapMs: 100, windowMs: 110, lookAheadMs: 1700),
};

// Easy's hand position: this many neighboring white keys.
const easyKeys = 5;

// Lowest and highest key with the keyboard's octave buttons centered.
const keyboardLow = 48;
const keyboardHigh = 84;

class Lane {
  const Lane(this.key, {this.exact = false});

  // A pitch class (0-11), or an exact note when [exact].
  final int key;
  final bool exact;

  int get pc => pitchClass(key);
  bool matches(int note) => exact ? note == key : pitchClass(note) == key;
}

class ChartNote {
  const ChartNote(this.lane, this.sound, this.timeMs, this.lengthMs);

  final int lane;

  // The note that plays when it is hit: the song's own note.
  final int sound;
  final int timeMs;
  final int lengthMs;
}

class Chart {
  const Chart(this.lanes, this.notes, [this.autoNotes = const []]);

  final List<Lane> lanes;
  final List<ChartNote> notes;

  // Song notes the game plays itself (their lane is -1).
  final List<ChartNote> autoNotes;

  int get endMs => [
        for (final n in [...notes, ...autoNotes]) n.timeMs + n.lengthMs,
      ].fold(0, max);
}

// Keeps a note only when it starts at least [minGapMs] after the last kept
// one (never two notes at once).
List<SongNote> thinNotes(List<SongNote> notes, int minGapMs) {
  final kept = <SongNote>[];
  for (final n in notes) {
    if (kept.isEmpty || n.startMs - kept.last.startMs >= max(1, minGapMs)) kept.add(n);
  }
  return kept;
}

// The shift (-5..6) that puts the most notes on white keys; the smallest
// move wins a tie.
int whiteKeyShift(List<int> pitches) {
  var best = 0;
  var bestCount = -1;
  for (final shift in [0, 1, -1, 2, -2, 3, -3, 4, -4, 5, -5, 6]) {
    final count = pitches.where((p) => pitchClasses[pitchClass(p + shift)].white).length;
    if (count > bestCount) {
      best = shift;
      bestCount = count;
    }
  }
  return best;
}

// Whole octaves that move the notes onto the keyboard, centered when the
// song is wider than the keyboard.
int fitOctaves(List<int> pitches, {int low = keyboardLow, int high = keyboardHigh}) {
  if (pitches.isEmpty) return 0;
  final lowest = pitches.reduce(min);
  final highest = pitches.reduce(max);
  final middle = (lowest + highest) / 2;
  final want = (low + high) / 2;
  return ((want - middle) / 12).round() * 12;
}

// The first of [size] neighboring white keys (as an index into the white
// keys C..B) that covers the most of [keys]; the lowest wins a tie.
int bestWhiteWindow(List<int> keys, int size) {
  var best = 0;
  var bestCount = -1;
  for (var start = 0; start + size <= whitePitchClasses.length; start++) {
    final window = whitePitchClasses.sublist(start, start + size);
    final count = keys.where(window.contains).length;
    if (count > bestCount) {
      best = start;
      bestCount = count;
    }
  }
  return best;
}

Chart buildChart(Song song, Difficulty difficulty) {
  final level = highwayLevels[difficulty]!;
  final scaled = [
    for (final n in song.notes)
      SongNote(n.note, (n.startMs / level.speed).round(), (n.lengthMs / level.speed).round()),
  ];
  final first = scaled.isEmpty ? 0 : scaled.first.startMs;
  final kept = Set<SongNote>.identity()..addAll(thinNotes(scaled, level.minGapMs));
  final keptPitches = [for (final n in scaled) if (kept.contains(n)) n.note];

  // What sounds for each song note, and the lane key the player presses for
  // it (null: the game plays it).
  late final int Function(int pitch) sound;
  late final int? Function(int sound) key;
  var exact = false;
  switch (difficulty) {
    case Difficulty.easy || Difficulty.medium:
      final shift = whiteKeyShift(keptPitches);
      sound = (p) => p + shift;
      final whites = [
        for (final p in keptPitches)
          if (pitchClasses[pitchClass(p + shift)].white) pitchClass(p + shift),
      ];
      final start = difficulty == Difficulty.easy ? bestWhiteWindow(whites, easyKeys) : 0;
      final allowed = difficulty == Difficulty.easy
          ? whitePitchClasses.sublist(start, start + easyKeys)
          : whitePitchClasses;
      key = (s) => allowed.contains(pitchClass(s)) ? pitchClass(s) : null;
    case Difficulty.hard:
      sound = (p) => p;
      key = pitchClass;
    case Difficulty.expert:
      final octaves = fitOctaves(keptPitches);
      sound = (p) => p + octaves;
      key = (s) => s;
      exact = true;
  }

  final keys = <int>{
    for (final n in scaled)
      if (kept.contains(n) && key(sound(n.note)) != null) key(sound(n.note))!,
  }.toList()
    ..sort();
  final lanes = [for (final k in keys) Lane(k, exact: exact)];
  final notes = <ChartNote>[];
  final autoNotes = <ChartNote>[];
  for (final n in scaled) {
    final s = sound(n.note);
    final k = kept.contains(n) ? key(s) : null;
    final note = ChartNote(k == null ? -1 : keys.indexOf(k), s, n.startMs - first, n.lengthMs);
    (k == null ? autoNotes : notes).add(note);
  }
  return Chart(lanes, notes, autoNotes);
}

enum NoteMark { waiting, hit, missed }

enum HighwayResult { perfect, good, wrong, stray }

const perfectPoints = 100;
const goodPoints = 50;

// Streak bonus: x2 from 10 in a row, x3 from 20, x4 from 30.
int multiplierFor(int streak) => min(4, 1 + streak ~/ 10);

// One play of a chart. Times are in ms on the chart's clock (0 = first note
// on the line).
class HighwayRun {
  HighwayRun(this.chart, this.windowMs)
      : marks = List.filled(chart.notes.length, NoteMark.waiting);

  final Chart chart;
  final int windowMs;
  final List<NoteMark> marks;
  int score = 0;
  int streak = 0;
  int bestStreak = 0;
  int hits = 0;

  // Notes before this are all hit or missed.
  int _first = 0;

  int get total => chart.notes.length;
  bool finishedAt(int nowMs) => nowMs > chart.endMs + windowMs + 1200;

  // 0 to 3 stars by the share of notes hit.
  int get stars {
    if (total == 0) return 0;
    final share = hits / total;
    return share >= 0.9 ? 3 : share >= 0.75 ? 2 : share >= 0.5 ? 1 : 0;
  }

  // Waiting notes close enough to [nowMs] to be hit.
  Iterable<int> _due(int nowMs) sync* {
    for (var i = _first; i < total; i++) {
      final t = chart.notes[i].timeMs;
      if (t > nowMs + windowMs) break;
      if (marks[i] == NoteMark.waiting && (t - nowMs).abs() <= windowMs) yield i;
    }
  }

  // Marks the notes that went past the line unhit; returns them.
  List<int> advance(int nowMs) {
    final missed = <int>[];
    while (_first < total && chart.notes[_first].timeMs < nowMs - windowMs) {
      if (marks[_first] == NoteMark.waiting) {
        marks[_first] = NoteMark.missed;
        missed.add(_first);
        streak = 0;
      }
      _first++;
    }
    return missed;
  }

  // [index] is the note hit, or on a wrong key the note that was due (it
  // counts as missed). A key with nothing due is a stray: no penalty.
  ({HighwayResult result, int? index}) press(int note, int nowMs) {
    final due = _due(nowMs).toList();
    if (due.isEmpty) return (result: HighwayResult.stray, index: null);
    int? best;
    for (final i in due) {
      if (!chart.lanes[chart.notes[i].lane].matches(note)) continue;
      final dt = (chart.notes[i].timeMs - nowMs).abs();
      if (best == null || dt < (chart.notes[best].timeMs - nowMs).abs()) best = i;
    }
    if (best == null) {
      final i = due.first;
      marks[i] = NoteMark.missed;
      streak = 0;
      return (result: HighwayResult.wrong, index: i);
    }
    marks[best] = NoteMark.hit;
    hits++;
    streak++;
    bestStreak = max(bestStreak, streak);
    final perfect = (chart.notes[best].timeMs - nowMs).abs() <= windowMs * 0.45;
    score += (perfect ? perfectPoints : goodPoints) * multiplierFor(streak);
    return (result: perfect ? HighwayResult.perfect : HighwayResult.good, index: best);
  }
}
