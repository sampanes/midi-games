import test from "node:test";
import assert from "node:assert/strict";
import { midiNoteName, parseMidiMessage, rangeValue } from "../src/midi/midi-parser.js";

test("names standard MIDI notes", () => {
  assert.equal(midiNoteName(0), "C-1");
  assert.equal(midiNoteName(60), "C4");
  assert.equal(midiNoteName(127), "G9");
});

test("parses note-on with channel, pitch, velocity, and stable signal key", () => {
  const event = parseMidiMessage([0x92, 60, 91], 12.5);
  assert.deepEqual(event, {
    category: "note",
    messageType: "note-on",
    phase: "press",
    channel: 3,
    number: 60,
    noteName: "C4",
    velocity: 91,
    value: 91,
    signalKey: "note:3:60",
    bytes: [0x92, 60, 91],
    timestamp: 12.5
  });
});

test("treats note-on velocity zero as note-off", () => {
  const event = parseMidiMessage([0x90, 64, 0], 20);
  assert.equal(event.messageType, "note-off");
  assert.equal(event.phase, "release");
  assert.equal(event.signalKey, "note:1:64");
});

test("reports a truncated channel message instead of inventing values", () => {
  const event = parseMidiMessage([0x90, 60], 21);
  assert.equal(event.category, "invalid");
  assert.equal(event.messageType, "invalid-length");
  assert.equal(event.expectedLength, 3);
  assert.equal(event.value, null);
});

test("keeps changing control values under one controller signal", () => {
  const low = parseMidiMessage([0xb1, 74, 1], 1);
  const high = parseMidiMessage([0xb1, 74, 127], 2);
  assert.equal(low.signalKey, "cc:2:74");
  assert.equal(high.signalKey, "cc:2:74");
  assert.equal(high.value, 127);
});

test("parses centered and maximum pitch bend as signed values", () => {
  assert.equal(parseMidiMessage([0xe0, 0, 64]).value, 0);
  assert.equal(parseMidiMessage([0xe0, 127, 127]).value, 8191);
});

test("classifies timing clock as system noise", () => {
  const event = parseMidiMessage([0xf8], 2);
  assert.equal(event.category, "system");
  assert.equal(event.messageType, "timing-clock");
  assert.equal(event.signalKey, "system:f8");
});

test("range value uses press velocity and ignores note releases", () => {
  assert.equal(rangeValue(parseMidiMessage([0x99, 72, 32])), 32);
  assert.equal(rangeValue(parseMidiMessage([0x89, 72, 64])), null);
  assert.equal(rangeValue(parseMidiMessage([0x99, 72, 0])), null);
});

test("range value keeps controller and pitch bend values", () => {
  assert.equal(rangeValue(parseMidiMessage([0xb0, 64, 0])), 0);
  assert.equal(rangeValue(parseMidiMessage([0xe3, 0, 0])), -8192);
  assert.equal(rangeValue(null), null);
});
