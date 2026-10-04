import test from "node:test";
import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import {
  analyzeMidiCapabilities,
  formatCapabilityReportMarkdown,
  summarizeNumericValues
} from "../src/midi/capability-analysis.js";

function midiEvent(sequence, portRef, eventTimestampMs, bytes, trialId = "trial-1", extra = {}) {
  return {
    sequence,
    portRef,
    eventTimestampMs,
    receivedAtMs: eventTimestampMs + 1.5,
    callbackDelayMs: 1.5,
    bytes,
    trialId,
    trialKey: "synthetic",
    ...extra
  };
}

function inventory(rawEvents, overrides = {}) {
  return {
    schemaVersion: 2,
    ports: {
      inputs: [
        { ref: "input-a", id: "browser-opaque-a", name: "Synthetic A", manufacturer: "Fixture" },
        { ref: "input-b", id: "browser-opaque-b", name: "Synthetic B", manufacturer: "Fixture" }
      ],
      outputs: [{ ref: "output-a", id: "browser-opaque-output", name: "Synthetic output", manufacturer: "Fixture" }]
    },
    trials: [
      { id: "trial-1", planKey: "synthetic", label: "First trial", result: "observed" },
      { id: "trial-2", planKey: "synthetic", label: "Second trial", result: "observed" }
    ],
    rawEvents,
    ...overrides
  };
}

test("summarizes ports, messages, signals, trials, values, and trial-bounded steps", () => {
  const values = [0, 2, 4, 4, 6, 10];
  const events = values.map((value, index) => midiEvent(
    index + 1,
    "input-a",
    index * 10,
    [0xb0, 74, value]
  ));
  events.push(midiEvent(7, "input-a", 100, [0xb0, 74, 100], "trial-2"));
  events.push(midiEvent(8, "input-b", 110, [0xc1, 9], "trial-2"));

  const analysis = analyzeMidiCapabilities(inventory(events));
  assert.equal(analysis.eventCount, 8);
  assert.equal(analysis.portSummaries.find((row) => row.portRef === "input-a").eventCount, 7);
  assert.equal(analysis.portSummaries.find((row) => row.portRef === "output-a").eventCount, 0);
  assert.equal(analysis.messageSummaries.find((row) => row.messageType === "control-change").eventCount, 7);

  const signal = analysis.signalSummaries.find((row) => row.signalKey === "cc:1:74");
  assert.equal(signal.portRef, "input-a");
  assert.deepEqual(signal.valueSummary.distinctValues, [0, 2, 4, 6, 10, 100]);
  assert.equal(signal.valueSummary.range, 100);
  assert.equal(signal.valueSummary.stepSummary.smallestObservedStep, 2);
  assert.equal(signal.valueSummary.stepSummary.transitionCount, 5);
  assert.equal(signal.valueSummary.stepSummary.zeroTransitionCount, 1);
  assert.equal(signal.valueSummary.stepSummary.modalAbsoluteTransition, 2);

  assert.equal(analysis.trialSummaries.find((row) => row.trialId === "trial-1").eventCount, 6);
  assert.equal(analysis.trialSummaries.find((row) => row.trialId === "trial-2").eventCount, 2);
});

test("numeric summaries retain missing counts and do not bridge missing values", () => {
  const summary = summarizeNumericValues([0, 2, null, 10, 10]);
  assert.equal(summary.count, 4);
  assert.equal(summary.missingCount, 1);
  assert.equal(summary.min, 0);
  assert.equal(summary.max, 10);
  assert.equal(summary.median, 6);
  assert.equal(summary.stepSummary.transitionCount, 2);
  assert.equal(summary.stepSummary.zeroTransitionCount, 1);
});

test("pairs notes within each port and trial and reports concurrency and unmatched events", () => {
  const events = [
    midiEvent(1, "input-a", 0, [0x80, 60, 64]),
    midiEvent(2, "input-a", 10, [0x90, 60, 30]),
    midiEvent(3, "input-a", 20, [0x90, 64, 40]),
    midiEvent(4, "input-a", 30, [0x80, 60, 50]),
    midiEvent(5, "input-a", 40, [0x90, 60, 60]),
    midiEvent(6, "input-a", 50, [0x80, 64, 45]),
    midiEvent(7, "input-a", 60, [0x80, 60, 20], "trial-2")
  ];
  const analysis = analyzeMidiCapabilities(inventory(events));
  const notes = analysis.noteSummary.perPort[0];
  assert.equal(notes.noteOnCount, 3);
  assert.equal(notes.noteOffCount, 4);
  assert.equal(notes.pairedCount, 2);
  assert.equal(notes.unmatchedNoteOnCount, 1);
  assert.equal(notes.unmatchedNoteOffCount, 2);
  assert.equal(notes.maxConcurrentNotes, 2);
  assert.equal(notes.maxConcurrentDistinctNotes, 2);
  assert.equal(notes.durationSummary.median, 25);
  assert.equal(analysis.noteSummary.perTrial.length, 2);
});

test("keeps attack ranges separate from release velocities", () => {
  const events = [
    midiEvent(1, "input-a", 0, [0x90, 60, 20]),
    midiEvent(2, "input-a", 10, [0x80, 60, 64]),
    midiEvent(3, "input-a", 20, [0x90, 60, 100]),
    midiEvent(4, "input-a", 30, [0x90, 60, 0])
  ];
  const analysis = analyzeMidiCapabilities(inventory(events));
  const signal = analysis.signalSummaries.find((row) => row.signalKey === "note:1:60");
  assert.deepEqual(signal.valueSummary.distinctValues, [20, 100]);
  assert.deepEqual(signal.attackVelocitySummary.distinctValues, [20, 100]);
  assert.deepEqual(signal.releaseVelocitySummary.distinctValues, [0, 64]);
  assert.equal(signal.valueSummary.min, 20);
  assert.equal(signal.valueSummary.max, 100);
});

test("computes one-to-one mirror coverage and signed skew from exact raw bytes", () => {
  const events = [
    midiEvent(1, "input-a", 0, [0xb0, 1, 10]),
    midiEvent(2, "input-a", 20, [0xb0, 2, 20]),
    midiEvent(3, "input-a", 40, [0xb0, 3, 30]),
    midiEvent(4, "input-b", 2, [0xb0, 1, 10]),
    midiEvent(5, "input-b", 25, [0xb0, 2, 20]),
    midiEvent(6, "input-b", 37, [0xb0, 3, 30]),
    midiEvent(7, "input-b", 60, [0xb0, 4, 40])
  ];
  const analysis = analyzeMidiCapabilities(inventory(events), {
    mirrorWindowMs: 5,
    mirrorMatchThreshold: 0.75,
    mirrorMinimumMatches: 3,
    mirrorMinimumSignatures: 3
  });
  const pair = analysis.mirrorPairs[0];
  assert.equal(pair.matchedCount, 3);
  assert.equal(pair.matchRateA, 1);
  assert.equal(pair.matchRateB, 0.75);
  assert.equal(pair.strictMatchRate, 0.75);
  assert.equal(pair.skewSummary.median, 2);
  assert.equal(pair.absoluteSkewSummary.median, 3);
  assert.equal(pair.isCandidate, true);
});

test("never reuses repeated events during mirror matching", () => {
  const events = [
    midiEvent(1, "input-a", 0, [0xb0, 1, 10]),
    midiEvent(2, "input-a", 5, [0xb0, 1, 10]),
    midiEvent(3, "input-b", 1, [0xb0, 1, 10]),
    midiEvent(4, "input-b", 6, [0xb0, 1, 10])
  ];
  const pair = analyzeMidiCapabilities(inventory(events), {
    mirrorWindowMs: 2,
    mirrorMinimumMatches: 1,
    mirrorMinimumSignatures: 1
  }).mirrorPairs[0];
  assert.equal(pair.matchedCount, 2);
  assert.equal(pair.strictMatchRate, 1);
});

test("does not match identical bytes across different trials", () => {
  const events = [
    midiEvent(1, "input-a", 0, [0xb0, 1, 10], "trial-1"),
    midiEvent(2, "input-b", 1, [0xb0, 1, 10], "trial-2")
  ];
  const pair = analyzeMidiCapabilities(inventory(events), {
    mirrorWindowMs: 5,
    mirrorMinimumMatches: 1,
    mirrorMinimumSignatures: 1
  }).mirrorPairs[0];
  assert.equal(pair.matchedCount, 0);
  assert.equal(pair.isCandidate, false);
});

test("pairs repeated same-note instances FIFO without inflating distinct-note polyphony", () => {
  const events = [
    midiEvent(1, "input-a", 0, [0x90, 60, 50]),
    midiEvent(2, "input-a", 10, [0x90, 60, 60]),
    midiEvent(3, "input-a", 20, [0x80, 60, 40]),
    midiEvent(4, "input-a", 30, [0x80, 60, 30])
  ];
  const notes = analyzeMidiCapabilities(inventory(events)).noteSummary.perPort[0];
  assert.equal(notes.pairedCount, 2);
  assert.equal(notes.repeatedNoteOnCount, 1);
  assert.equal(notes.maxConcurrentNotes, 2);
  assert.equal(notes.maxConcurrentDistinctNotes, 1);
  assert.equal(notes.durationSummary.median, 20);
});

test("handles missing optional fields and rejects truncated channel messages without inventing notes", () => {
  const analysis = analyzeMidiCapabilities({
    schemaVersion: 2,
    rawEvents: [
      {},
      midiEvent(2, "input-a", 1, [0x90, 60], "trial-1", {
        parsed: {
          category: "note",
          messageType: "note-on",
          phase: "press",
          channel: 1,
          number: 60,
          velocity: 0,
          value: 0,
          signalKey: "note:1:60"
        }
      }),
      { sequence: 3, portRef: "input-a", bytes: new Uint8Array([0xc0, 8]) },
      { sequence: 4, portRef: "input-a", bytes: [0xb0, 7, 999] }
    ]
  });
  assert.equal(analysis.eventCount, 4);
  assert.equal(analysis.noteSummary.totals.noteOnCount, 0);
  assert.equal(analysis.messageSummaries.find((row) => row.messageType === "truncated").eventCount, 2);
  assert.ok(analysis.limitations.some((item) => item.includes("truncated or invalid")));
  assert.ok(analysis.limitations.some((item) => item.includes("lack a portRef")));
});

test("summarizes session metadata, trial observations, no-MIDI results, outputs, cleanup, and transitions", () => {
  const analysis = analyzeMidiCapabilities(inventory([
    midiEvent(1, "input-a", 12, [0xb0, 1, 64])
  ], {
    session: {
      startedAt: "2026-01-01T00:00:00.000Z",
      savedAt: "2026-01-01T00:01:00.000Z",
      durationMs: 60000,
      launcherBackend: "WinRT",
      sysexEnabled: false,
      physicalInputLatencyMeasured: false,
      rawEventLimit: 100000,
      rawEventsDropped: 0,
      metadata: {
        connectionMode: "usb-only",
        firmwareVersion: "016",
        preset: "3",
        keyChannel: "10",
        padChannel: "10",
        keyVelocityCurve: "2",
        padVelocityCurve: "3",
        padAftertouch: "on",
        pedalMode: "sustain",
        octaveState: "centered",
        activeModes: "ARP off",
        notes: "<screen>|stable\nsecond line",
        blankValue: ""
      }
    },
    trials: [
      {
        id: "trial-1",
        planKey: "setup.global-settings",
        group: "setup",
        label: "Read GLOBE state",
        result: "local-only-effect",
        observation: "display changed",
        startedAtMs: 10,
        endedAtMs: 20,
        eventCount: 1,
        meaningfulEventCount: 0,
        portRefs: ["input-a"],
        signalRefs: ["input-a|cc:1:1"]
      },
      {
        id: "trial-2",
        planKey: "buttons.bt",
        label: "BT button",
        result: "no-midi-observed",
        observation: "light toggled locally",
        startedAtMs: 30,
        endedAtMs: 40,
        eventCount: 0,
        meaningfulEventCount: 0,
        portRefs: [],
        signalRefs: []
      }
    ],
    noMidiObserved: [{
      trialId: "trial-2",
      planKey: "buttons.bt",
      label: "BT button",
      result: "no-midi-observed",
      observation: "light toggled locally",
      recordedAtMs: 40
    }],
    ports: {
      inputs: [{ ref: "input-a", name: "Synthetic A", manufacturer: "Fixture" }],
      outputs: [{ ref: "output-a", name: "Synthetic output", manufacturer: "Fixture" }],
      transitions: [
        {
          atMs: 15,
          portRef: "input-a",
          direction: "input",
          name: "Synthetic A",
          state: "connected",
          connection: "open",
          trialId: "trial-1",
          trialKey: "setup.global-settings"
        },
        {
          atMs: 16,
          portRef: "input-a",
          direction: "input",
          state: "connected",
          connection: "open",
          trialId: null,
          trialKey: null
        }
      ]
    },
    outputProbes: [
      {
        id: "probe-001",
        outputRef: "output-a",
        channel: 1,
        note: 60,
        velocity: 16,
        result: "internal-synth-audible",
        notes: "quiet patch",
        noteOnSent: true,
        noteOffSent: true,
        allNotesOffSent: true,
        allSoundOffSent: true,
        messagesSent: 4,
        cleanupComplete: true,
        outputClosed: true
      },
      {
        id: "probe-002",
        outputRef: "output-a",
        channel: 2,
        note: 64,
        velocity: 8,
        result: "other",
        notes: "uncertain",
        noteOnSent: true,
        noteOffSent: false,
        allNotesOffSent: true,
        allSoundOffSent: true,
        messagesSent: 3,
        cleanupComplete: false,
        cleanupError: "Note Off failed",
        outputClosed: false,
        closeError: "close failed"
      }
    ],
    outputCleanupActions: [
      {
        atMs: 50,
        reason: "Manual panic",
        outputRef: "output-a",
        clearCalled: true,
        noteOffsSent: 1,
        allNotesOffSent: 16,
        allSoundOffSent: 16,
        messagesSent: 33,
        errors: []
      },
      {
        atMs: 55,
        reason: "Page closed",
        outputRef: "output-a",
        clearCalled: false,
        noteOffsSent: 0,
        allNotesOffSent: 15,
        allSoundOffSent: 16,
        messagesSent: 31,
        errors: ["clear failed"]
      }
    ]
  }));

  assert.equal(analysis.sessionSummary.metadata.keyChannel, "10");
  assert.equal(Object.hasOwn(analysis.sessionSummary.metadata, "blankValue"), false);
  const globeTrial = analysis.trialSummaries.find((trial) => trial.trialId === "trial-1");
  assert.equal(globeTrial.label, "Read GLOBE state");
  assert.equal(globeTrial.status, "local-only-effect");
  assert.equal(globeTrial.observation, "display changed");
  assert.equal(globeTrial.declaredMeaningfulEventCount, 0);
  assert.equal(analysis.trialSummaries.find((trial) => trial.trialId === "trial-2").noMidiObserved, true);
  assert.equal(analysis.noMidiObservations[0].observation, "light toggled locally");
  assert.equal(analysis.portTransitions[0].trialCorrelation, "explicit");
  assert.equal(analysis.portTransitions[0].correlatedTrialLabel, "Read GLOBE state");
  assert.equal(analysis.portTransitions[1].trialCorrelation, "explicit-none");
  assert.equal(analysis.portTransitions[1].correlatedTrialId, null);
  assert.equal(analysis.outputProbeSummaries[0].cleanupStatus, "complete");
  assert.equal(analysis.outputProbeSummaries[0].outputCloseStatus, "closed");
  assert.equal(analysis.outputProbeSummaries[1].cleanupStatus, "incomplete");
  assert.equal(analysis.outputProbeSummaries[1].outputCloseStatus, "close-error");
  assert.equal(analysis.outputCleanupActions[0].cleanupStatus, "complete");
  assert.equal(analysis.outputCleanupActions[1].cleanupStatus, "errors");
  assert.ok(analysis.limitations.some((item) => item.includes("lack confirmed complete note cleanup")));
  assert.ok(analysis.limitations.some((item) => item.includes("output-port close problem")));

  const report = formatCapabilityReportMarkdown(analysis);
  assert.match(report, /## Session and GLOBE metadata/);
  assert.match(report, /GLOBE key channel \| 10/);
  assert.match(report, /Read GLOBE state/);
  assert.match(report, /local-only-effect/);
  assert.match(report, /display changed/);
  assert.match(report, /## Explicit no-MIDI observations/);
  assert.match(report, /light toggled locally/);
  assert.match(report, /## Port transitions and trial correlation/);
  assert.match(report, /explicit-none/);
  assert.match(report, /## Output probes/);
  assert.match(report, /close-error/);
  assert.match(report, /## Output cleanup actions/);
  assert.match(report, /Manual panic/);
  assert.match(report, /&lt;screen&gt;\\\|stable second line/);
});

test("treats raw MIDI bytes as authoritative and reports supplied parse mismatches", () => {
  const event = midiEvent(1, "input-a", 0, [0x90, 60, 91], "trial-1", {
    parsed: {
      category: "control-change",
      messageType: "control-change",
      phase: "change",
      channel: 9,
      number: 74,
      value: 1,
      velocity: 1,
      signalKey: "cc:9:74"
    }
  });
  const analysis = analyzeMidiCapabilities(inventory([event]));
  assert.equal(analysis.signalSummaries.some((signal) => signal.signalKey === "note:1:60"), true);
  assert.equal(analysis.signalSummaries.some((signal) => signal.signalKey === "cc:9:74"), false);
  assert.equal(analysis.messageSummaries[0].messageType, "note-on");
  assert.equal(analysis.signalSummaries[0].valueSummary.max, 91);
  assert.equal(analysis.parseDiagnostics.rawDecodedEventCount, 1);
  assert.equal(analysis.parseDiagnostics.mismatchEventCount, 1);
  assert.deepEqual(analysis.parseDiagnostics.mismatches[0].fields, [
    "category",
    "messageType",
    "phase",
    "channel",
    "number",
    "value",
    "velocity",
    "signalKey"
  ]);
  assert.ok(analysis.limitations.some((item) => item.includes("raw-byte decoding was used")));
  const report = formatCapabilityReportMarkdown(analysis);
  assert.match(report, /## Raw-byte decode verification/);
  assert.match(report, /Mismatch: signalKey \| 1/);
});

test("correlates only legacy unambiguous transitions by time and lets explicit trial context win", () => {
  const analysis = analyzeMidiCapabilities(inventory([], {
    trials: [
      { id: "trial-a", planKey: "a", label: "A", startedAtMs: 0, endedAtMs: 20 },
      { id: "trial-b", planKey: "b", label: "B", startedAtMs: 10, endedAtMs: 30 },
      { id: "trial-c", planKey: "c", label: "C", startedAtMs: 40, endedAtMs: 50 }
    ],
    ports: {
      inputs: [],
      outputs: [],
      transitions: [
        { atMs: 15, portRef: "input-a" },
        { atMs: 45, portRef: "input-a" },
        { atMs: 45, portRef: "input-a", trialId: null, trialKey: null },
        { atMs: 45, portRef: "input-a", trialId: "missing", trialKey: "c" }
      ]
    }
  }));
  assert.equal(analysis.portTransitions[0].trialCorrelation, "ambiguous-time-range");
  assert.equal(analysis.portTransitions[0].correlatedTrialId, null);
  assert.equal(analysis.portTransitions[1].trialCorrelation, "time-range");
  assert.equal(analysis.portTransitions[1].correlatedTrialId, "trial-c");
  assert.equal(analysis.portTransitions[2].trialCorrelation, "explicit-none");
  assert.equal(analysis.portTransitions[2].correlatedTrialId, null);
  assert.equal(analysis.portTransitions[3].trialCorrelation, "explicit-unresolved");
  assert.equal(analysis.portTransitions[3].correlatedTrialId, "missing");
});

test("ignores malformed optional metadata collections without throwing or claiming cleanup success", () => {
  const analysis = analyzeMidiCapabilities({
    schemaVersion: 2,
    session: { metadata: [] },
    ports: { inputs: [null, "bad"], outputs: {}, transitions: [null, "bad", {}] },
    trials: [null, "bad"],
    noMidiObserved: [null, "bad"],
    outputProbes: [null, "bad", {}],
    outputCleanupActions: [null, "bad", { clearCalled: false, messagesSent: 1 }],
    rawEvents: []
  });
  assert.deepEqual(analysis.trials, []);
  assert.deepEqual(analysis.noMidiObservations, []);
  assert.equal(analysis.outputProbeSummaries.length, 1);
  assert.equal(analysis.outputProbeSummaries[0].cleanupStatus, "unknown");
  assert.equal(analysis.outputCleanupActions.length, 1);
  assert.equal(analysis.outputCleanupActions[0].cleanupStatus, "partial");
  assert.equal(analysis.portTransitions.length, 1);
  assert.doesNotThrow(() => formatCapabilityReportMarkdown(analysis));
});

test("renders stable Markdown without a source path", () => {
  const analysis = analyzeMidiCapabilities(inventory([
    midiEvent(1, "input-a", 0, [0x90, 60, 80]),
    midiEvent(2, "input-a", 50, [0x80, 60, 64])
  ]));
  const report = formatCapabilityReportMarkdown(analysis);
  assert.match(report, /^# MIDI capability analysis/m);
  assert.match(report, /## Note integrity and polyphony/);
  assert.match(report, /source path is intentionally omitted/i);
  assert.doesNotMatch(report, /[A-Z]:\\/i);
});

test("returns an explicit empty analysis for a missing inventory object", () => {
  const analysis = analyzeMidiCapabilities(null);
  assert.equal(analysis.eventCount, 0);
  assert.deepEqual(analysis.portSummaries, []);
  assert.deepEqual(analysis.mirrorPairs, []);
  assert.equal(analysis.noteSummary.totals.pairedCount, 0);
  assert.ok(analysis.limitations.some((item) => item.includes("schemaVersion 2")));
});

test("CLI prints and writes reports without echoing the absolute inventory path", async (context) => {
  const temporaryDirectory = await mkdtemp(join(tmpdir(), "midi-capability-test-"));
  context.after(() => rm(temporaryDirectory, { recursive: true, force: true }));
  const inputPath = join(temporaryDirectory, "private-fixture.json");
  const outputPath = join(temporaryDirectory, "reports", "summary.md");
  await writeFile(inputPath, JSON.stringify(inventory([
    midiEvent(1, "input-a", 0, [0xb0, 7, 100])
  ])), "utf8");
  const scriptPath = fileURLToPath(new URL("../scripts/analyze-midi-capabilities.mjs", import.meta.url));

  const printed = execFileSync(process.execPath, [scriptPath, inputPath], { encoding: "utf8" });
  assert.match(printed, /^# MIDI capability analysis/);
  assert.equal(printed.includes(inputPath), false);

  const status = execFileSync(process.execPath, [scriptPath, inputPath, "--output", outputPath], { encoding: "utf8" });
  assert.equal(status.includes(inputPath), false);
  assert.match(status, /summary\.md/);
  assert.match(await readFile(outputPath, "utf8"), /^# MIDI capability analysis/);

  const overwriteAttempt = spawnSync(process.execPath, [scriptPath, inputPath, "--output", inputPath], { encoding: "utf8" });
  assert.equal(overwriteAttempt.status, 1);
  assert.match(overwriteAttempt.stderr, /must not overwrite/);
  assert.equal(overwriteAttempt.stderr.includes(inputPath), false);
  assert.equal(JSON.parse(await readFile(inputPath, "utf8")).schemaVersion, 2);
});
