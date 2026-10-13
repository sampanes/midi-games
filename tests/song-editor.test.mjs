import test from "node:test";
import assert from "node:assert/strict";
import {
  DEFAULT_ADDED_MS,
  addNote,
  dropPart,
  keepNote,
  keepPart,
  nextStep,
  onsetTimes,
  snapStart,
  toggleNote,
  tuneNotes
} from "../src/song-editor/roll.js";

// A made-up song: a chord part (part 0) and a drum part (part 1).
//   0 ms: chord C E G (1000 ms)   1000 ms: chord F A C (1000 ms)
//   drums every 250 ms
const notes = [
  [0, 1000, 60, 0], [0, 1000, 64, 0], [0, 1000, 67, 0],
  [1000, 2000, 65, 0], [1000, 2000, 69, 0], [1000, 2000, 72, 0],
  ...[0, 250, 500, 750, 1000, 1250, 1500, 1750].map((t) => [t, t + 50, 42, 1])
];
const hidden = new Set([1]);
const empty = { kept: new Set(), added: [] };

test("onsets leave out hidden parts; a lyric close by wins the snap", () => {
  const onsets = onsetTimes(notes, hidden);
  assert.deepEqual(onsets, [0, 1000]);
  assert.equal(snapStart(380, onsets, []), 0);
  assert.equal(snapStart(620, onsets, []), 1000);
  assert.equal(snapStart(620, onsets, [500]), 500);
  assert.equal(snapStart(620, onsets, [100]), 1000);
});

test("keeping a chord note drops the other tune note at that moment", () => {
  let state = keepNote(notes, empty, 2);
  state = toggleNote(notes, state, 0);
  assert.deepEqual([...state.kept], [0]);
  state = toggleNote(notes, state, 0);
  assert.equal(state.kept.size, 0);
});

test("adding the song's own note keeps it instead of making one up", () => {
  const onsets = onsetTimes(notes, hidden);
  const { state } = addNote(notes, empty, 64, 30, { onsets, lyrics: [], hidden });
  assert.deepEqual([...state.kept], [1]);
  assert.equal(state.added.length, 0);
});

test("an added note starts on the beat and lasts as long as the chord under it", () => {
  const onsets = onsetTimes(notes, hidden);
  const ctx = { onsets, lyrics: [], hidden };
  const first = addNote(notes, keepNote(notes, empty, 2), 62, 90, ctx);
  assert.equal(first.start, 0);
  assert.equal(first.end, 1000);
  assert.equal(first.state.kept.size, 0, "the G kept at 0 ms gives way");
  assert.deepEqual(first.state.added, [{ s: 0, e: 1000, n: 62 }]);

  // Nothing in a shown part starts at 2000: the default length applies.
  const late = addNote(notes, empty, 62, 2000, { onsets: [2000], lyrics: [], hidden });
  assert.equal(late.end, 2000 + DEFAULT_ADDED_MS);
});

test("an added note stops at the next tune note or syllable", () => {
  const onsets = onsetTimes(notes, hidden);
  const kept = keepNote(notes, empty, 4);
  const { end } = addNote(notes, kept, 62, 0, { onsets, lyrics: [], hidden });
  assert.equal(end, 1000);
  const sung = addNote(notes, empty, 62, 0, { onsets, lyrics: [0, 400, 1000], hidden });
  assert.equal(sung.end, 400);
});

test("step entry moves to the next syllable, or the next note start", () => {
  assert.equal(nextStep(0, [0, 1000], []), 1000);
  assert.equal(nextStep(0, [0, 1000], [0, 400]), 400);
  assert.equal(nextStep(1000, [0, 1000], []), 1000);
});

test("keeping a part keeps its top note at each moment; dropping clears it", () => {
  const state = keepPart(notes, empty, 0);
  assert.deepEqual(tuneNotes(notes, state.kept, state.added).map((n) => n.n), [67, 72]);
  assert.equal(dropPart(notes, state, 0).kept.size, 0);
});
