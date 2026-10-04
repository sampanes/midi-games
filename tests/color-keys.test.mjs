import test from "node:test";
import assert from "node:assert/strict";
import {
  PITCH_CLASSES,
  STARS_PER_ROUND,
  WHITE_PITCH_CLASSES,
  advance,
  createGame,
  createMirrorFilter,
  noteEventFromBytes,
  pickNextTarget,
  pitchClass,
  pressNote
} from "../src/games/color-keys.js";

test("every pitch class has a distinct color and there are 7 white keys", () => {
  assert.equal(PITCH_CLASSES.length, 12);
  assert.equal(new Set(PITCH_CLASSES.map((p) => p.color)).size, 12);
  assert.deepEqual(WHITE_PITCH_CLASSES, [0, 2, 4, 5, 7, 9, 11]);
});

test("pitch class ignores octave", () => {
  assert.equal(pitchClass(60), 0);
  assert.equal(pitchClass(48), 0);
  assert.equal(pitchClass(71), 11);
});

test("note events work on any channel and treat velocity 0 as release", () => {
  assert.deepEqual(noteEventFromBytes([0x9c, 60, 100]), { type: "on", note: 60, velocity: 100, channel: 13 });
  assert.deepEqual(noteEventFromBytes([0x99, 40, 90]), { type: "on", note: 40, velocity: 90, channel: 10 });
  assert.equal(noteEventFromBytes([0x90, 60, 0]).type, "off");
  assert.equal(noteEventFromBytes([0x80, 60, 64]).type, "off");
});

test("non-note messages and out-of-range notes are ignored", () => {
  assert.equal(noteEventFromBytes([0xb0, 1, 64]), null);
  assert.equal(noteEventFromBytes([0xe0, 0, 64]), null);
  assert.equal(noteEventFromBytes([0x90, 0, 127]), null);
  assert.equal(noteEventFromBytes([0x90, 108, 127]), null);
  assert.equal(noteEventFromBytes([0xf8]), null);
});

test("mirror filter drops the same message from a second port", () => {
  const accept = createMirrorFilter(60);
  assert.equal(accept("usb", [0x90, 60, 100], 1000), true);
  assert.equal(accept("ble", [0x90, 60, 100], 1008), false);
  assert.equal(accept("usb-2", [0x90, 60, 100], 1010), false);
  assert.equal(accept("ble", [0x90, 60, 100], 1200), true);
});

test("mirror filter keeps repeats from the same port", () => {
  const accept = createMirrorFilter(60);
  assert.equal(accept("ble", [0x90, 60, 100], 1000), true);
  assert.equal(accept("ble", [0x90, 60, 100], 1020), true);
});

test("next target is always a different white key", () => {
  for (let previous = 0; previous < 12; previous++) {
    for (const r of [0, 0.3, 0.6, 0.999]) {
      const next = pickNextTarget(previous, () => r);
      assert.ok(WHITE_PITCH_CLASSES.includes(next));
      assert.notEqual(next, previous);
    }
  }
});

test("right pitch in any octave scores, wrong pitch misses", () => {
  const game = { ...createGame(() => 0), target: 0 };
  const miss = pressNote(game, 62);
  assert.equal(miss.state.stars, 0);
  assert.equal(miss.effects[0].type, "miss");
  const hit = pressNote(game, 84);
  assert.equal(hit.state.stars, 1);
  assert.deepEqual(hit.effects.map((e) => e.type), ["hit", "next-soon"]);
  assert.equal(pressNote(hit.state, 84).effects[0].type, "play");
});

test("a full round wins and resets stars", () => {
  let game = { ...createGame(() => 0), target: 0 };
  let last;
  for (let i = 0; i < STARS_PER_ROUND; i++) {
    game = { ...game, target: 0, locked: false };
    last = pressNote(game, 60);
    game = last.state;
  }
  assert.ok(last.effects.some((e) => e.type === "win"));
  game = advance(game, () => 0);
  assert.equal(game.stars, 0);
  assert.equal(game.rounds, 1);
  assert.equal(game.locked, false);
});
