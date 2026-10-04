import test from "node:test";
import assert from "node:assert/strict";
import {
  CAPABILITY_SCHEMA_LIMITS,
  validateCapabilityInventory
} from "../src/midi/capability-schema.js";

function validInventory() {
  return {
    schemaVersion: 2,
    session: {
      startedAt: "2026-10-04T00:00:00.000Z",
      savedAt: "2026-10-04T00:01:00.000Z",
      durationMs: 60000,
      launcherBackend: "WinRT",
      sysexEnabled: false,
      browserUserAgent: "Synthetic browser",
      metadata: { connectionMode: "usb-and-bluetooth" },
      rawEventLimit: CAPABILITY_SCHEMA_LIMITS.rawEvents,
      rawEventsDropped: 0,
      physicalInputLatencyMeasured: false
    },
    totals: {
      events: 1,
      rawEventsRetained: 1,
      rawEventsDropped: 0,
      distinctSignals: 1,
      possibleMirrorCandidates: 0,
      trials: 2,
      noMidiObserved: 1,
      outputProbes: 1
    },
    ports: {
      inputs: [{
        ref: "in-01",
        id: "browser-input-id",
        direction: "input",
        name: "Synthetic input",
        manufacturer: "Fixture",
        state: "connected",
        connection: "open",
        present: true,
        openError: null,
        firstSeenAtMs: 0,
        events: 1,
        notes: 1,
        controls: 0,
        other: 0,
        possibleMirrors: 0
      }],
      outputs: [{
        ref: "out-01",
        id: "browser-output-id",
        direction: "output",
        name: "Synthetic output",
        manufacturer: "Fixture",
        state: "connected",
        connection: "open",
        present: true,
        openError: null,
        firstSeenAtMs: 0,
        messagesSent: 36
      }],
      transitions: [{
        atMs: 5,
        portRef: "in-01",
        direction: "input",
        name: "Synthetic input",
        manufacturer: "Fixture",
        state: "connected",
        connection: "open",
        trialId: "trial-001",
        trialKey: "keys.bulk-sweep"
      }]
    },
    signals: [{ portRef: "in-01", signalKey: "note:1:60" }],
    trials: [{
      id: "trial-001",
      planKey: "keys.bulk-sweep",
      group: "keys",
      label: "Play all keys",
      instructions: "Play the keys in order.",
      observation: "All keys reported note messages.",
      result: "completed",
      startedAtMs: 10,
      endedAtMs: 20,
      startSequence: 1,
      endSequence: 1,
      eventCount: 1,
      meaningfulEventCount: 1,
      portRefs: ["in-01"],
      signalRefs: ["in-01|note:1:60"]
    }, {
      id: "trial-002",
      planKey: "buttons.bt",
      group: "buttons",
      label: "BT button",
      instructions: "Press and release the button.",
      observation: "No MIDI message appeared.",
      result: "no-midi-observed",
      startedAtMs: 30,
      endedAtMs: 31,
      startSequence: 2,
      endSequence: 1,
      eventCount: 0,
      meaningfulEventCount: 0,
      portRefs: [],
      signalRefs: []
    }],
    noMidiObserved: [{
      trialId: "trial-002",
      planKey: "buttons.bt",
      label: "BT button",
      result: "no-midi-observed",
      observation: "No MIDI message appeared.",
      recordedAtMs: 31
    }],
    outputProbes: [{
      id: "probe-001",
      outputRef: "out-01",
      channel: 1,
      note: 60,
      velocity: 16,
      sentAtMs: 40,
      noteLengthMs: 300,
      result: "internal-synth-audible",
      notes: "Quiet piano sound",
      noteOnSent: true,
      noteOffSent: true,
      allNotesOffSent: true,
      allSoundOffSent: true,
      cleanupComplete: true,
      messagesSent: 4,
      sendError: null,
      cleanupError: null,
      outputClosed: true,
      closeError: null,
      observedAtMs: 41
    }],
    outputCleanupActions: [{
      atMs: 50,
      reason: "Manual panic",
      outputRef: "out-01",
      clearCalled: true,
      noteOffsSent: 0,
      allNotesOffSent: 16,
      allSoundOffSent: 16,
      messagesSent: 32,
      outputClosed: true,
      closeError: null,
      errors: []
    }],
    rawEvents: [{
      sequence: 1,
      portRef: "in-01",
      eventTimestampMs: 11,
      receivedAtMs: 11.5,
      callbackDelayMs: 0.5,
      bytes: [0x90, 60, 100],
      parsed: { messageType: "note-on", signalKey: "note:1:60" },
      trialId: "trial-001",
      trialKey: "keys.bulk-sweep",
      mirrorCandidateId: null
    }]
  };
}

function cloneInventory() {
  return JSON.parse(JSON.stringify(validInventory()));
}

test("accepts the current live schema-version-2 payload shape", () => {
  assert.equal(validateCapabilityInventory(validInventory()), null);
});

test("rejects malformed MIDI bytes and non-increasing event sequences", () => {
  const badByte = cloneInventory();
  badByte.rawEvents[0].bytes = [0x90, 300, 1];
  assert.match(validateCapabilityInventory(badByte), /MIDI bytes/);

  const duplicateSequence = cloneInventory();
  duplicateSequence.rawEvents.push({ ...duplicateSequence.rawEvents[0], sequence: 1 });
  duplicateSequence.totals.events = 2;
  duplicateSequence.totals.rawEventsRetained = 2;
  duplicateSequence.ports.inputs[0].events = 2;
  duplicateSequence.ports.inputs[0].notes = 2;
  assert.match(validateCapabilityInventory(duplicateSequence), /strictly increasing/);
});

test("requires every bounded collection in the live payload", () => {
  for (const field of ["trials", "noMidiObserved", "outputProbes", "outputCleanupActions"]) {
    const inventory = cloneInventory();
    delete inventory[field];
    assert.equal(validateCapabilityInventory(inventory), `${field} must be an array`);
  }
});

test("rejects invalid and duplicate port entries plus orphan transitions", () => {
  const duplicate = cloneInventory();
  duplicate.ports.outputs[0].ref = "in-01";
  assert.match(validateCapabilityInventory(duplicate), /unique across all ports/);

  const badDirection = cloneInventory();
  badDirection.ports.inputs[0].direction = "output";
  assert.match(validateCapabilityInventory(badDirection), /direction must be input/);

  const orphanTransition = cloneInventory();
  orphanTransition.ports.transitions[0].portRef = "in-missing";
  assert.match(validateCapabilityInventory(orphanTransition), /declared port/);
});

test("validates transition links against completed trials", () => {
  const orphanTrial = cloneInventory();
  orphanTrial.ports.transitions[0].trialId = "trial-missing";
  assert.match(validateCapabilityInventory(orphanTrial), /declared trial/);

  const wrongKey = cloneInventory();
  wrongKey.ports.transitions[0].trialKey = "keys.wrong";
  assert.match(validateCapabilityInventory(wrongKey), /must match its trial/);

  const keyWithoutId = cloneInventory();
  keyWithoutId.ports.transitions[0].trialId = null;
  assert.match(validateCapabilityInventory(keyWithoutId), /requires a trialId/);
});

test("rejects malformed trials and inconsistent no-MIDI observations", () => {
  const impossibleCounts = cloneInventory();
  impossibleCounts.trials[0].meaningfulEventCount = 2;
  assert.match(validateCapabilityInventory(impossibleCounts), /event counts/);

  const missingObservation = cloneInventory();
  missingObservation.noMidiObserved = [];
  missingObservation.totals.noMidiObserved = 0;
  assert.match(validateCapabilityInventory(missingObservation), /missing its noMidiObserved entry/);

  const orphanObservation = cloneInventory();
  orphanObservation.noMidiObserved[0].trialId = "trial-missing";
  assert.match(validateCapabilityInventory(orphanObservation), /declared trial/);

  const longTrialObservation = cloneInventory();
  longTrialObservation.trials[0].observation = "x".repeat(2001);
  assert.match(validateCapabilityInventory(longTrialObservation), /observation is invalid/);

  const longNoMidiObservation = cloneInventory();
  longNoMidiObservation.noMidiObserved[0].observation = "x".repeat(2001);
  assert.match(validateCapabilityInventory(longNoMidiObservation), /observation is invalid/);
});

test("rejects unsafe or inconsistent output probes", () => {
  const loudProbe = cloneInventory();
  loudProbe.outputProbes[0].velocity = 127;
  assert.match(validateCapabilityInventory(loudProbe), /safe probe range/);

  const orphanProbe = cloneInventory();
  orphanProbe.outputProbes[0].outputRef = "out-missing";
  assert.match(validateCapabilityInventory(orphanProbe), /declared output port/);

  const inconsistentCleanup = cloneInventory();
  inconsistentCleanup.outputProbes[0].noteOffSent = false;
  assert.match(validateCapabilityInventory(inconsistentCleanup), /messagesSent|cleanupComplete/);

  const badClosed = cloneInventory();
  badClosed.outputProbes[0].outputClosed = "yes";
  assert.match(validateCapabilityInventory(badClosed), /outputClosed must be boolean/);

  const longCloseError = cloneInventory();
  longCloseError.outputProbes[0].closeError = "x".repeat(2001);
  assert.match(validateCapabilityInventory(longCloseError), /closeError is invalid/);
});

test("rejects malformed or unbounded output cleanup actions", () => {
  const badCounts = cloneInventory();
  badCounts.outputCleanupActions[0].messagesSent = 31;
  assert.match(validateCapabilityInventory(badCounts), /cleanup counts/);

  const tooMany = cloneInventory();
  tooMany.outputCleanupActions = Array.from(
    { length: CAPABILITY_SCHEMA_LIMITS.outputCleanupActions + 1 },
    () => ({})
  );
  assert.match(validateCapabilityInventory(tooMany), /item limit/);

  const badClosed = cloneInventory();
  badClosed.outputCleanupActions[0].outputClosed = 1;
  assert.match(validateCapabilityInventory(badClosed), /outputClosed must be boolean/);

  const longCloseError = cloneInventory();
  longCloseError.outputCleanupActions[0].closeError = "x".repeat(2001);
  assert.match(validateCapabilityInventory(longCloseError), /closeError is invalid/);
});

test("rejects raw events that reference undeclared ports or trials", () => {
  const badPort = cloneInventory();
  badPort.rawEvents[0].portRef = "in-missing";
  assert.match(validateCapabilityInventory(badPort), /declared input port/);

  const badTrial = cloneInventory();
  badTrial.rawEvents[0].trialId = "trial-missing";
  assert.match(validateCapabilityInventory(badTrial), /declared trial/);
});

test("enforces retained, dropped, total, port, and collection consistency", () => {
  const wrongRetained = cloneInventory();
  wrongRetained.totals.rawEventsRetained = 2;
  assert.match(validateCapabilityInventory(wrongRetained), /rawEvents\.length/);

  const wrongDropped = cloneInventory();
  wrongDropped.session.rawEventsDropped = 1;
  assert.match(validateCapabilityInventory(wrongDropped), /session\.rawEventsDropped/);

  const wrongPortTotal = cloneInventory();
  wrongPortTotal.ports.inputs[0].events = 2;
  wrongPortTotal.ports.inputs[0].notes = 2;
  assert.match(validateCapabilityInventory(wrongPortTotal), /input-port event total/);

  const wrongTrialTotal = cloneInventory();
  wrongTrialTotal.totals.trials = 1;
  assert.match(validateCapabilityInventory(wrongTrialTotal), /trials\.length/);
});
