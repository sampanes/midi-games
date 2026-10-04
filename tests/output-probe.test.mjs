import test from "node:test";
import assert from "node:assert/strict";
import { panicMidiOutput, sendSafeNoteProbe } from "../src/midi/output-probe.js";

function fakeOutput({ failAtSend = null } = {}) {
  const sent = [];
  let sendCount = 0;
  return {
    sent,
    clearCount: 0,
    async open() {},
    send(bytes) {
      sendCount += 1;
      if (sendCount === failAtSend) throw new Error(`send ${sendCount} failed`);
      sent.push([...bytes]);
    },
    clear() { this.clearCount += 1; }
  };
}

test("safe probe sends one note and three selected-channel cleanup messages", async () => {
  const output = fakeOutput();
  const result = await sendSafeNoteProbe({
    output,
    channel: 2,
    note: 60,
    velocity: 16,
    wait: async () => {}
  });
  assert.deepEqual(output.sent, [
    [0x91, 60, 16],
    [0x81, 60, 0],
    [0xb1, 123, 0],
    [0xb1, 120, 0]
  ]);
  assert.equal(result.noteOnSent, true);
  assert.equal(result.cleanupComplete, true);
  assert.equal(result.cleanupError, null);
  assert.equal(result.messagesSent, 4);
});

test("safe probe records uncertain cleanup without hiding the failed message", async () => {
  const output = fakeOutput({ failAtSend: 2 });
  const result = await sendSafeNoteProbe({
    output,
    channel: 1,
    note: 60,
    velocity: 8,
    wait: async () => {}
  });
  assert.equal(result.noteOnSent, true);
  assert.equal(result.noteOffSent, false);
  assert.equal(result.allNotesOffSent, true);
  assert.equal(result.allSoundOffSent, true);
  assert.equal(result.cleanupComplete, false);
  assert.match(result.cleanupError, /Note Off/);
});

test("safe probe still attempts cleanup when waiting fails", async () => {
  const output = fakeOutput();
  const result = await sendSafeNoteProbe({
    output,
    channel: 1,
    note: 64,
    velocity: 12,
    wait: async () => { throw new Error("interrupted"); }
  });
  assert.match(result.sendError, /interrupted/);
  assert.equal(result.cleanupComplete, true);
  assert.equal(output.sent.length, 4);
});

test("safe probe rejects loud velocity values", async () => {
  await assert.rejects(
    sendSafeNoteProbe({ output: fakeOutput(), channel: 1, note: 60, velocity: 127, wait: async () => {} }),
    /velocity/
  );
});

test("panic clears scheduling, releases active notes, and cleans all channels", () => {
  const output = fakeOutput();
  const result = panicMidiOutput(output, [{ channel: 3, note: 67 }]);
  assert.equal(output.clearCount, 1);
  assert.deepEqual(output.sent[0], [0x82, 67, 0]);
  assert.equal(result.noteOffsSent, 1);
  assert.equal(result.allNotesOffSent, 16);
  assert.equal(result.allSoundOffSent, 16);
  assert.equal(result.messagesSent, 33);
  assert.deepEqual(result.errors, []);
});
