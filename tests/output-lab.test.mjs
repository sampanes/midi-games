import test from "node:test";
import assert from "node:assert/strict";
import {
  DEFAULT_PAD_NOTES,
  parsePadNotes,
  programChangeBytes,
  runPadSweep,
  sendProgramChange,
  validateOutputLabLog
} from "../src/midi/output-lab.js";

function fakeOutput() {
  const sent = [];
  return {
    sent,
    async open() {},
    send(bytes) { sent.push([...bytes]); },
    clear() {}
  };
}

test("program change bytes use a zero-based channel nibble", () => {
  assert.deepEqual(programChangeBytes(1, 0), [0xc0, 0]);
  assert.deepEqual(programChangeBytes(16, 7), [0xcf, 7]);
  assert.throws(() => programChangeBytes(0, 0), /channel/);
  assert.throws(() => programChangeBytes(1, 128), /program/);
});

test("program change sends exactly one message", async () => {
  const output = fakeOutput();
  const result = await sendProgramChange({ output, channel: 2, program: 3 });
  assert.equal(result.sent, true);
  assert.deepEqual(output.sent, [[0xc1, 3]]);
});

test("pad note list parses commas and spaces and rejects bad notes", () => {
  assert.deepEqual(parsePadNotes("40, 41 42"), [40, 41, 42]);
  assert.equal(parsePadNotes(DEFAULT_PAD_NOTES.join(",")).length, 16);
  assert.throws(() => parsePadNotes(""), /1 to 32/);
  assert.throws(() => parsePadNotes("40, 200"), /invalid note/);
});

test("pad sweep plays every note with full cleanup after each", async () => {
  const output = fakeOutput();
  const visited = [];
  const result = await runPadSweep({
    output,
    channel: 10,
    notes: [40, 41],
    velocity: 16,
    wait: async () => {},
    onStep: ({ note }) => visited.push(note)
  });
  assert.equal(result.completed, true);
  assert.deepEqual(visited, [40, 41]);
  assert.deepEqual(output.sent, [
    [0x99, 40, 16], [0x89, 40, 0], [0xb9, 123, 0], [0xb9, 120, 0],
    [0x99, 41, 16], [0x89, 41, 0], [0xb9, 123, 0], [0xb9, 120, 0]
  ]);
});

test("pad sweep stops when asked", async () => {
  const output = fakeOutput();
  let calls = 0;
  const result = await runPadSweep({
    output,
    channel: 10,
    notes: [40, 41, 42],
    velocity: 16,
    wait: async () => {},
    shouldStop: () => calls++ >= 1
  });
  assert.equal(result.completed, false);
  assert.equal(result.steps.length, 1);
});

test("pad sweep inherits the safe velocity cap", async () => {
  await assert.rejects(
    runPadSweep({ output: fakeOutput(), channel: 10, notes: [40], velocity: 100, wait: async () => {} }),
    /velocity/
  );
});

test("output-lab log validation", () => {
  assert.equal(validateOutputLabLog({ kind: "output-lab", schemaVersion: 1, actions: [], incoming: [] }), null);
  assert.match(validateOutputLabLog({ kind: "other", schemaVersion: 1, actions: [], incoming: [] }), /kind/);
  assert.match(validateOutputLabLog({ kind: "output-lab", schemaVersion: 1, actions: {}, incoming: [] }), /actions/);
});
