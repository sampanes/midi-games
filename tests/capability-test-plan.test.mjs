import test from "node:test";
import assert from "node:assert/strict";
import { CAPABILITY_TEST_PLAN } from "../src/midi/capability-test-plan.js";

const requiredGroups = [
  "setup",
  "idle",
  "keys",
  "pads",
  "knobs",
  "faders",
  "wheels",
  "pedal",
  "buttons",
  "transport",
  "modes",
  "presets",
  "output",
  "audio",
  "reliability"
];

test("exports an ordered frozen plan with frozen valid steps", () => {
  assert.ok(Object.isFrozen(CAPABILITY_TEST_PLAN));
  assert.ok(CAPABILITY_TEST_PLAN.length > 90);

  for (const item of CAPABILITY_TEST_PLAN) {
    assert.ok(Object.isFrozen(item), `${item.key} must be frozen`);
    for (const field of ["key", "group", "label", "instructions"]) {
      assert.equal(typeof item[field], "string", `${item.key}.${field} must be a string`);
      assert.ok(item[field].trim(), `${item.key}.${field} must not be blank`);
    }
    if ("optional" in item) assert.equal(typeof item.optional, "boolean");
    if ("accessory" in item) assert.ok(item.accessory.trim());
    if ("risk" in item) assert.ok(item.risk.trim());
  }
});

test("uses unique stable keys and includes every required group", () => {
  const keys = CAPABILITY_TEST_PLAN.map((item) => item.key);
  assert.equal(new Set(keys).size, keys.length);

  const groups = new Set(CAPABILITY_TEST_PLAN.map((item) => item.group));
  for (const group of requiredGroups) {
    assert.ok(groups.has(group), `missing ${group} group`);
  }
});

test("enumerates both logical pad banks individually", () => {
  const padKeys = CAPABILITY_TEST_PLAN
    .filter((item) => item.group === "pads")
    .map((item) => item.key);
  const expected = [
    ...Array.from({ length: 16 }, (_, index) => `pads.base.${String(index + 1).padStart(2, "0")}`),
    ...Array.from({ length: 16 }, (_, index) => `pads.bank.${String(index + 17).padStart(2, "0")}`)
  ];
  assert.deepEqual(padKeys, expected);
});

test("enumerates both knob and fader banks individually", () => {
  const knobKeys = CAPABILITY_TEST_PLAN
    .filter((item) => item.group === "knobs")
    .map((item) => item.key);
  const faderKeys = CAPABILITY_TEST_PLAN
    .filter((item) => item.group === "faders")
    .map((item) => item.key);

  assert.deepEqual(knobKeys, [
    ...Array.from({ length: 8 }, (_, index) => `knobs.base.${String(index + 1).padStart(2, "0")}`),
    ...Array.from({ length: 8 }, (_, index) => `knobs.bank.${String(index + 9).padStart(2, "0")}`)
  ]);
  assert.deepEqual(faderKeys, [
    ...Array.from({ length: 4 }, (_, index) => `faders.base.${String(index + 1).padStart(2, "0")}`),
    ...Array.from({ length: 4 }, (_, index) => `faders.bank.${String(index + 5).padStart(2, "0")}`)
  ]);
});

test("covers the documented panel buttons one by one", () => {
  const expectedButtonKeys = [
    "buttons.knob-bank",
    "buttons.fader-bank",
    "buttons.octave-down",
    "buttons.octave-up",
    "buttons.left",
    "buttons.right",
    "buttons.arp",
    "buttons.note-repeat",
    "buttons.scale",
    "buttons.chord",
    "buttons.globe",
    "buttons.bt",
    "buttons.patch",
    "buttons.para",
    "buttons.fx",
    "buttons.seq",
    "buttons.seq-play",
    "buttons.seq-rec"
  ];
  assert.deepEqual(
    CAPABILITY_TEST_PLAN.filter((item) => item.group === "buttons").map((item) => item.key),
    expectedButtonKeys
  );
});

test("keeps setup, idle observation, active census, and manual probes in order", () => {
  const indexOf = (key) => CAPABILITY_TEST_PLAN.findIndex((item) => item.key === key);
  assert.ok(indexOf("setup.identity") < indexOf("idle.untouched"));
  assert.ok(indexOf("idle.untouched") < indexOf("keys.bulk-sweep"));
  assert.ok(indexOf("keys.bulk-sweep") < indexOf("pads.base.01"));
  assert.ok(indexOf("pads.bank.32") < indexOf("knobs.base.01"));
  assert.ok(indexOf("buttons.seq-rec") < indexOf("transport.usb-only"));
  assert.ok(indexOf("transport.bluetooth-only") < indexOf("modes.scale"));
  assert.ok(indexOf("presets.08") < indexOf("output.usb-ports"));
  assert.ok(indexOf("output.usb-ports") < indexOf("audio.host-playback"));
  assert.ok(indexOf("audio.usb-recording") < indexOf("reliability.hot-reconnect"));
});

test("contains no timer or countdown instructions", () => {
  for (const item of CAPABILITY_TEST_PLAN) {
    assert.doesNotMatch(item.instructions, /\b(timer|countdown)\b/i, item.key);
    assert.doesNotMatch(item.instructions, /\bwait for \d+\b/i, item.key);
  }
});
