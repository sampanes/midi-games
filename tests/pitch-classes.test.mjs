import test from "node:test";
import assert from "node:assert/strict";
import { PITCH_CLASSES, WHITE_PITCH_CLASSES, pitchClass } from "../src/midi/pitch-classes.js";

test("every pitch class has a distinct color and there are 7 white keys", () => {
  assert.equal(PITCH_CLASSES.length, 12);
  assert.equal(new Set(PITCH_CLASSES.map((p) => p.color)).size, 12);
  assert.deepEqual(WHITE_PITCH_CLASSES, [0, 2, 4, 5, 7, 9, 11]);
});

test("pitch class ignores octave", () => {
  assert.equal(pitchClass(60), 0);
  assert.equal(pitchClass(48), 0);
  assert.equal(pitchClass(71), 11);
  assert.equal(pitchClass(-1), 11);
});
