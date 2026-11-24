// Pure rules for "Song Memory": a real tune learned by heart. The game plays
// a bit of the tune in the tune's own rhythm, and the player plays it back
// from memory. What is played back right grows, until the whole line is
// known; then the next line starts.
//
// A song is cut into lines where the tune takes a breath (see [songLines]):
// "Twinkle, twinkle, little star" is one line, "how I wonder what you are"
// the next. The letter is what counts, in any octave, and the player's
// timing is never judged: the rhythm is for the ear.
//
// Easy and Medium learn a line one note at a time (one note, then two, then
// three), each line from its own start. Easy stops after two lines, and a
// wrong key there never starts over: the right key glows. Hard and Expert
// hear a whole new line at once and play the song from the top up to it;
// they have hearts, which come back with every new line. Expert is by ear:
// the keys stay dark while the game plays.

import 'dart:math';

import '../songs/song.dart';
import 'color_keys_rules.dart';
import 'difficulty.dart';

// Notes [start] up to, not including, [end] of a song's tune.
typedef SongLine = ({int start, int end});

extension SongLineLength on SongLine {
  int get length => end - start;
}

// A line is at least this long when the tune allows it, and never longer
// than [maxLineNotes] (a tail too short to stand alone may add one more).
const minLineNotes = 4;
const maxLineNotes = 8;

// From each note of the tune to the next; a note's own length when the song
// has no clock (the built-in scale) and for the last note.
List<int> songSteps(Song song) {
  final notes = song.notes;
  return [
    for (var i = 0; i < notes.length; i++)
      if (i + 1 < notes.length && notes[i + 1].startMs > notes[i].startMs)
        notes[i + 1].startMs - notes[i].startMs
      else
        notes[i].lengthMs,
  ];
}

// The song's everyday step from note to note: its beat, near enough.
int medianStep(Song song) {
  final steps = songSteps(song)..sort();
  return steps.isEmpty ? 0 : steps[steps.length ~/ 2];
}

// The song in lines. A line ends on a breath: a note held half as long
// again as the song's everyday step (the last of them, when several long
// notes follow each other). A tune that runs on without a breath is cut
// after its longest note within reach.
List<SongLine> songLines(Song song) {
  final steps = songSteps(song);
  final count = steps.length;
  final breath = medianStep(song) * 3 / 2;
  bool long(int i) => steps[i] >= breath;

  final lines = <SongLine>[];
  var start = 0;
  while (start < count) {
    // The last note this line may end on.
    final last = min(start + maxLineNotes, count) - 1;
    var end = count;
    if (count - start > minLineNotes) {
      int? found;
      for (var i = start + minLineNotes - 1; i <= last && found == null; i++) {
        if (i == count - 1 || (long(i) && !(i < last && long(i + 1)))) found = i;
      }
      if (found == null) {
        found = start + minLineNotes - 1;
        for (var i = found + 1; i <= last; i++) {
          if (steps[i] >= steps[found!]) found = i;
        }
      }
      end = found! + 1;
    }
    lines.add((start: start, end: end));
    start = end;
  }
  // A tail too short to be a line joins the line before it, when that
  // leaves a line that is still short enough to hold in the head.
  if (lines.length > 1 &&
      lines.last.length < minLineNotes &&
      lines.last.end - lines[lines.length - 2].start <= maxLineNotes + 1) {
    final tail = lines.removeLast();
    final before = lines.removeLast();
    lines.add((start: before.start, end: tail.end));
  }
  return lines;
}

class MemoryLevel {
  const MemoryLevel({
    required this.minStepMs,
    this.byNote = true,
    this.fromTop = false,
    this.shown = true,
    this.helps = false,
    this.hearts,
    this.lines,
  });

  // The game never plays faster than this from note to note: a quick tune
  // is slowed down until its everyday step is this long.
  final int minStepMs;

  // A line grows one note at a time. False: a whole line at once.
  final bool byNote;

  // The player plays the song from its start every time, up to the new
  // line. False: each line from the line's own start.
  final bool fromTop;

  // The keys light up as the game plays. False: by ear alone.
  final bool shown;

  // A wrong key does not start the line over: the right key glows.
  final bool helps;

  // Wrong keys allowed on one line; null for any number.
  final int? hearts;

  // Lines to learn; null for the whole song.
  final int? lines;
}

const memoryLevels = {
  Difficulty.easy: MemoryLevel(minStepMs: 500, helps: true, lines: 2),
  Difficulty.medium: MemoryLevel(minStepMs: 420),
  Difficulty.hard: MemoryLevel(minStepMs: 340, byNote: false, fromTop: true, hearts: 3),
  Difficulty.expert:
      MemoryLevel(minStepMs: 0, byNote: false, fromTop: true, hearts: 3, shown: false),
};

// How much slower than the song the game plays on [level]: 1 is the song's
// own speed.
double memoryStretch(Song song, MemoryLevel level) {
  final step = medianStep(song);
  return step <= 0 ? 1 : max(1, level.minStepMs / step);
}

// How many of the song's lines [level] asks for.
int memoryGoal(MemoryLevel level, List<SongLine> lines) =>
    min(level.lines ?? lines.length, lines.length);

typedef PlayedNote = ({int note, int atMs, int lengthMs});

// Notes [from] up to [to] of the tune as the game plays them: each at its
// place in the song's rhythm, [stretch] times slower, from zero.
List<PlayedNote> memoryPlayback(Song song, int from, int to, double stretch) {
  final steps = songSteps(song);
  final played = <PlayedNote>[];
  var at = 0;
  for (var i = from; i < to; i++) {
    // A note ends a little before the next one starts, so the same key
    // played twice is heard twice.
    final length = min(song.notes[i].lengthMs, steps[i] - 40);
    played.add((
      note: song.notes[i].note,
      atMs: (at * stretch).round(),
      lengthMs: max(80, (length * stretch).round()),
    ));
    at += steps[i];
  }
  return played;
}

enum MemoryResult { hit, grown, lineDone, won, miss, over, ignored }

class MemoryState {
  const MemoryState({
    required this.length,
    this.line = 0,
    this.at = 0,
    this.misses = 0,
    this.lineMisses = 0,
    this.again = false,
  });

  factory MemoryState.start(MemoryLevel level, List<SongLine> lines) =>
      MemoryState(length: _firstLength(level, lines.first));

  // The line being learned.
  final int line;

  // How many of its notes are in play now.
  final int length;

  // Notes played back so far on this try.
  final int at;

  // Wrong keys in this game, and on this line (the hearts).
  final int misses;
  final int lineMisses;

  // True after a wrong key: the game plays everything the player has to
  // play back, not just what is new.
  final bool again;

  int heartsLeft(MemoryLevel level) => max(0, (level.hearts ?? 0) - lineMisses);
}

int _firstLength(MemoryLevel level, SongLine line) => level.byNote ? 1 : line.length;

// The notes of the tune the player plays back now.
SongLine memorySpan(MemoryState state, MemoryLevel level, List<SongLine> lines) {
  final line = lines[state.line];
  return (start: level.fromTop ? 0 : line.start, end: line.start + state.length);
}

// The notes the game plays before the player's turn: what is to be played
// back, or just the new line when the earlier ones were played a moment ago.
SongLine memoryListen(MemoryState state, MemoryLevel level, List<SongLine> lines) {
  final span = memorySpan(state, level, lines);
  return level.fromTop && !state.again ? (start: lines[state.line].start, end: span.end) : span;
}

// The note the player has to play next; null when the turn is played out.
int? memoryWanted(MemoryState state, MemoryLevel level, Song song, List<SongLine> lines) {
  final span = memorySpan(state, level, lines);
  final index = span.start + state.at;
  return index < span.end ? song.notes[index].note : null;
}

({MemoryState state, MemoryResult result}) pressMemory(
  MemoryState state,
  int note,
  MemoryLevel level,
  Song song,
  List<SongLine> lines,
) {
  final want = memoryWanted(state, level, song, lines);
  if (want == null) return (state: state, result: MemoryResult.ignored);
  if (pitchClass(note) != pitchClass(want)) {
    final lineMisses = state.lineMisses + 1;
    final missed = MemoryState(
      line: state.line,
      length: state.length,
      // With help the player carries on from the same note.
      at: level.helps ? state.at : 0,
      misses: state.misses + 1,
      lineMisses: lineMisses,
      again: !level.helps,
    );
    final hearts = level.hearts;
    return (
      state: missed,
      result: hearts != null && lineMisses >= hearts ? MemoryResult.over : MemoryResult.miss,
    );
  }
  final played = MemoryState(
    line: state.line,
    length: state.length,
    at: state.at + 1,
    misses: state.misses,
    lineMisses: state.lineMisses,
    again: state.again,
  );
  final span = memorySpan(state, level, lines);
  if (span.start + played.at < span.end) return (state: played, result: MemoryResult.hit);
  if (state.length < lines[state.line].length) {
    return (state: played, result: MemoryResult.grown);
  }
  return (
    state: played,
    result: state.line + 1 < memoryGoal(level, lines) ? MemoryResult.lineDone : MemoryResult.won,
  );
}

// What follows a turn played back right: the same line one note longer, or
// the next line.
MemoryState nextMemory(MemoryState state, MemoryLevel level, List<SongLine> lines) {
  if (state.length < lines[state.line].length) {
    return MemoryState(
      line: state.line,
      length: state.length + 1,
      misses: state.misses,
      lineMisses: state.lineMisses,
    );
  }
  final line = min(state.line + 1, lines.length - 1);
  return MemoryState(line: line, length: _firstLength(level, lines[line]), misses: state.misses);
}

// The same turn from its first note, with nothing lost: the player asked to
// hear it again by waiting.
MemoryState replayMemory(MemoryState state) => MemoryState(
      line: state.line,
      length: state.length,
      misses: state.misses,
      lineMisses: state.lineMisses,
      again: true,
    );

// Stars for a song learned. With hearts: all three for no wrong key, two
// for no more than one a line. Without: as in Song Steps, by the share of
// wrong keys among the notes learned.
int memoryStars(int misses, MemoryLevel level, List<SongLine> lines) {
  final goal = memoryGoal(level, lines);
  if (goal == 0) return 0;
  if (level.hearts != null) return misses == 0 ? 3 : misses <= goal ? 2 : 1;
  return stepsStars(misses, lines[goal - 1].end);
}
