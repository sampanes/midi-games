import { CAPABILITY_TEST_PLAN } from "/midi/capability-test-plan.js";
import { parseMidiMessage, rangeValue } from "/midi/midi-parser.js";
import { panicMidiOutput, sendSafeNoteProbe } from "/midi/output-probe.js";

const MAX_RAW_EVENTS = 100000;
const MAX_RECENT_EVENTS = 200;
const MIRROR_WINDOW_MS = 12;
const OUTPUT_NOTE_LENGTH_MS = 300;
const SYSTEM_NOISE_TYPES = new Set(["timing-clock", "active-sensing"]);
const TEST_PLAN_BY_KEY = new Map(CAPABILITY_TEST_PLAN.map((step) => [step.key, step]));

const byId = (id) => document.getElementById(id);
const elements = {
  enableButton: byId("enable-button"),
  clearButton: byId("clear-button"),
  saveButton: byId("save-button"),
  statusText: byId("status-text"),
  backendLabel: byId("backend-label"),
  inputCount: byId("input-count"),
  outputCount: byId("output-count"),
  eventCount: byId("event-count"),
  rawCount: byId("raw-count"),
  signalCount: byId("signal-count"),
  trialCount: byId("trial-count"),
  sessionForm: byId("session-form"),
  trialSelect: byId("trial-select"),
  customTrialLabel: byId("custom-trial-label"),
  trialInstructions: byId("trial-instructions"),
  trialResult: byId("trial-result"),
  trialObservation: byId("trial-observation"),
  beginTrialButton: byId("begin-trial-button"),
  finishTrialButton: byId("finish-trial-button"),
  noMidiTrialButton: byId("no-midi-trial-button"),
  activeTrialStatus: byId("active-trial-status"),
  trialList: byId("trial-list"),
  outputSelect: byId("output-select"),
  outputAcknowledgement: byId("output-acknowledgement"),
  probeChannel: byId("probe-channel"),
  probeNote: byId("probe-note"),
  probeVelocity: byId("probe-velocity"),
  sendProbeButton: byId("send-probe-button"),
  panicButton: byId("panic-button"),
  probeResult: byId("probe-result"),
  probeNotes: byId("probe-notes"),
  recordProbeButton: byId("record-probe-button"),
  probeStatus: byId("probe-status"),
  portsBody: byId("ports-body"),
  signalsBody: byId("signals-body"),
  manualList: byId("manual-list"),
  recentList: byId("recent-list")
};

const query = new URLSearchParams(window.location.search);
const launcherBackend = query.get("backend") || "unknown";
elements.backendLabel.textContent = launcherBackend;

let midiAccess = null;
let captureStartedAt = new Date().toISOString();
let captureStartPerformanceMs = performance.now();
let activeTrial = null;
let pendingOutputProbe = null;
let acknowledgedOutputId = null;
let totalEvents = 0;
let rawEventsDropped = 0;
let possibleMirrorCount = 0;
let nextEventSequence = 1;
let nextTrialNumber = 1;
let nextMirrorNumber = 1;
let nextInputPortNumber = 1;
let nextOutputPortNumber = 1;
let renderPending = false;
let captureDirty = false;

const inputPortStats = new Map();
const outputPortStats = new Map();
const portRefs = new Map();
const observations = new Map();
const trials = [];
const manualObservations = [];
const outputProbes = [];
const outputCleanupActions = [];
const portTransitions = [];
const rawEvents = [];
const recentEvents = [];
const recentBySignature = new Map();
const openedOutputIds = new Set();
const activeOutputNotes = new Map();

populateTrialSelect();
updateTrialInstructions();

elements.enableButton.addEventListener("click", enableMidi);
elements.clearButton.addEventListener("click", clearCapture);
elements.saveButton.addEventListener("click", saveInventory);
elements.trialSelect.addEventListener("change", updateTrialInstructions);
elements.customTrialLabel.addEventListener("input", updateTrialInstructions);
elements.beginTrialButton.addEventListener("click", beginSelectedTrial);
elements.finishTrialButton.addEventListener("click", () => finishActiveTrial(elements.trialResult.value));
elements.noMidiTrialButton.addEventListener("click", recordSelectedNoMidi);
elements.outputSelect.addEventListener("change", handleOutputSelectionChange);
elements.outputAcknowledgement.addEventListener("change", handleOutputAcknowledgement);
elements.sendProbeButton.addEventListener("click", sendOutputProbe);
elements.panicButton.addEventListener("click", manualPanic);
elements.recordProbeButton.addEventListener("click", recordProbeResult);
elements.sessionForm.addEventListener("input", markCaptureDirty);
elements.sessionForm.addEventListener("change", markCaptureDirty);
window.addEventListener("beforeunload", warnBeforeUnsavedUnload);
window.addEventListener("pagehide", () => panicOpenedOutputs("Page closed"));

if (!("requestMIDIAccess" in navigator)) {
  setStatus("This browser does not expose the Web MIDI API. Open this page in Chrome or Edge.", "bad");
  elements.enableButton.disabled = true;
}

async function enableMidi() {
  elements.enableButton.disabled = true;
  setStatus("Requesting MIDI permission...");

  try {
    midiAccess = await navigator.requestMIDIAccess({ sysex: false });
    midiAccess.onstatechange = handlePortStateChange;
    await refreshPorts();
    elements.clearButton.disabled = false;
    elements.saveButton.disabled = false;
    elements.beginTrialButton.disabled = false;
    setStatus(
      `Listening to ${midiAccess.inputs.size} input${midiAccess.inputs.size === 1 ? "" : "s"}; ` +
      `${midiAccess.outputs.size} output${midiAccess.outputs.size === 1 ? "" : "s"} visible.`,
      "good"
    );
  } catch (error) {
    elements.enableButton.disabled = false;
    setStatus(`MIDI access failed: ${error.message || error}`, "bad");
  }
}

function handlePortStateChange(event) {
  const port = event.port;
  if (port) {
    portTransitions.push({
      atMs: relativeNow(),
      portRef: ensurePortRef(port),
      direction: port.type,
      name: port.name || "Unnamed MIDI port",
      manufacturer: port.manufacturer || "",
      state: port.state,
      connection: port.connection,
      trialId: activeTrial?.id ?? null,
      trialKey: activeTrial?.planKey ?? null
    });
    markCaptureDirty();
  }
  refreshPorts().catch((error) => setStatus(`Could not refresh MIDI ports: ${error.message || error}`, "bad"));
}

async function refreshPorts() {
  if (!midiAccess) return;

  const activeInputIds = new Set();
  const opening = [];
  for (const input of midiAccess.inputs.values()) {
    activeInputIds.add(input.id);
    ensureInputStats(input);
    input.onmidimessage = (event) => handleMidiMessage(input, event);
    if (input.connection !== "open") {
      opening.push(input.open().then(() => {
        ensureInputStats(input);
      }).catch((error) => {
        const stats = ensureInputStats(input);
        stats.openError = String(error.message || error);
      }));
    }
  }
  await Promise.all(opening);
  for (const [portId, stats] of inputPortStats) {
    stats.present = activeInputIds.has(portId);
  }

  const activeOutputIds = new Set();
  for (const output of midiAccess.outputs.values()) {
    activeOutputIds.add(output.id);
    ensureOutputStats(output);
  }
  for (const [portId, stats] of outputPortStats) {
    stats.present = activeOutputIds.has(portId);
  }

  renderOutputOptions();
  scheduleRender();
}

function ensurePortRef(port) {
  const key = `${port.type}:${port.id}`;
  if (!portRefs.has(key)) {
    const number = port.type === "input" ? nextInputPortNumber++ : nextOutputPortNumber++;
    portRefs.set(key, `${port.type === "input" ? "in" : "out"}-${String(number).padStart(2, "0")}`);
  }
  return portRefs.get(key);
}

function ensureInputStats(input) {
  if (!inputPortStats.has(input.id)) {
    inputPortStats.set(input.id, {
      ref: ensurePortRef(input),
      id: input.id,
      direction: "input",
      name: input.name || "Unnamed MIDI input",
      manufacturer: input.manufacturer || "",
      state: input.state,
      connection: input.connection,
      present: true,
      openError: null,
      firstSeenAtMs: relativeNow(),
      events: 0,
      notes: 0,
      controls: 0,
      other: 0,
      possibleMirrors: 0
    });
  }
  const stats = inputPortStats.get(input.id);
  stats.name = input.name || stats.name;
  stats.manufacturer = input.manufacturer || stats.manufacturer;
  stats.state = input.state;
  stats.connection = input.connection;
  stats.present = true;
  return stats;
}

function ensureOutputStats(output) {
  if (!outputPortStats.has(output.id)) {
    outputPortStats.set(output.id, {
      ref: ensurePortRef(output),
      id: output.id,
      direction: "output",
      name: output.name || "Unnamed MIDI output",
      manufacturer: output.manufacturer || "",
      state: output.state,
      connection: output.connection,
      present: true,
      openError: null,
      firstSeenAtMs: relativeNow(),
      messagesSent: 0
    });
  }
  const stats = outputPortStats.get(output.id);
  stats.name = output.name || stats.name;
  stats.manufacturer = output.manufacturer || stats.manufacturer;
  stats.state = output.state;
  stats.connection = output.connection;
  stats.present = true;
  return stats;
}

function handleMidiMessage(input, event) {
  const receivedAt = performance.now();
  const parsed = parseMidiMessage(event.data, event.timeStamp);
  if (!parsed) return;

  totalEvents += 1;
  markCaptureDirty();
  const stats = ensureInputStats(input);
  stats.events += 1;
  if (parsed.category === "note") stats.notes += 1;
  else if (parsed.category === "control-change") stats.controls += 1;
  else stats.other += 1;

  const observationKey = `${stats.ref}|${parsed.signalKey}`;
  let observation = observations.get(observationKey);
  if (!observation) {
    observation = {
      portRef: stats.ref,
      portId: input.id,
      portName: input.name || "Unnamed MIDI input",
      manufacturer: input.manufacturer || "",
      signalKey: parsed.signalKey,
      category: parsed.category,
      channel: parsed.channel ?? null,
      number: parsed.number ?? null,
      noteName: parsed.noteName ?? null,
      trialKeys: [],
      firstSeenAtMs: roundMilliseconds(receivedAt - captureStartPerformanceMs),
      lastSeenAtMs: roundMilliseconds(receivedAt - captureStartPerformanceMs),
      count: 0,
      minValue: null,
      maxValue: null,
      lastValue: null,
      lastMessageType: parsed.messageType,
      lastBytes: [],
      possibleMirrorCount: 0
    };
    observations.set(observationKey, observation);
  }

  observation.count += 1;
  observation.lastSeenAtMs = roundMilliseconds(receivedAt - captureStartPerformanceMs);
  observation.lastMessageType = parsed.messageType;
  observation.lastBytes = parsed.bytes;
  if (Number.isFinite(parsed.value)) observation.lastValue = parsed.value;
  const valueForRange = rangeValue(parsed);
  if (valueForRange !== null) {
    observation.minValue = observation.minValue === null ? valueForRange : Math.min(observation.minValue, valueForRange);
    observation.maxValue = observation.maxValue === null ? valueForRange : Math.max(observation.maxValue, valueForRange);
  }

  if (activeTrial && !observation.trialKeys.includes(activeTrial.planKey)) {
    observation.trialKeys.push(activeTrial.planKey);
  }

  const { bytes: ignoredBytes, timestamp: ignoredTimestamp, ...decoded } = parsed;
  const rawEvent = {
    sequence: nextEventSequence++,
    portRef: stats.ref,
    eventTimestampMs: roundMilliseconds(event.timeStamp - captureStartPerformanceMs),
    receivedAtMs: roundMilliseconds(receivedAt - captureStartPerformanceMs),
    callbackDelayMs: roundMilliseconds(receivedAt - event.timeStamp),
    bytes: parsed.bytes,
    parsed: decoded,
    trialId: activeTrial?.id ?? null,
    trialKey: activeTrial?.planKey ?? null,
    mirrorCandidateId: null
  };

  const isSystemNoise = parsed.category === "system" && SYSTEM_NOISE_TYPES.has(parsed.messageType);
  if (!isSystemNoise) detectPossibleMirror(stats.ref, parsed, observation, rawEvent);

  if (activeTrial) {
    activeTrial.eventCount += 1;
    if (!isSystemNoise) activeTrial.meaningfulEventCount += 1;
    activeTrial.portRefs.add(stats.ref);
    activeTrial.signalRefs.add(observationKey);
  }

  if (rawEvents.length < MAX_RAW_EVENTS) {
    rawEvents.push(rawEvent);
  } else {
    rawEventsDropped += 1;
    if (rawEventsDropped === 1) {
      setStatus(`Raw event limit ${MAX_RAW_EVENTS} reached; aggregates continue but later raw events are counted as dropped.`, "bad");
    }
  }

  if (!isSystemNoise) {
    recentEvents.unshift(rawEvent);
    recentEvents.splice(MAX_RECENT_EVENTS);
  }
  scheduleRender();
}

function detectPossibleMirror(portRef, parsed, observation, rawEvent) {
  const signature = parsed.bytes.join(",");
  const previous = recentBySignature.get(signature);
  const isMirror = Boolean(
    previous &&
    previous.portRef !== portRef &&
    Math.abs(parsed.timestamp - previous.timestamp) <= MIRROR_WINDOW_MS
  );

  if (isMirror) {
    possibleMirrorCount += 1;
    observation.possibleMirrorCount += 1;
    const candidateId = previous.rawEvent.mirrorCandidateId || `mirror-${String(nextMirrorNumber++).padStart(6, "0")}`;
    previous.rawEvent.mirrorCandidateId = candidateId;
    rawEvent.mirrorCandidateId = candidateId;
    const currentStats = [...inputPortStats.values()].find((item) => item.ref === portRef);
    if (currentStats) currentStats.possibleMirrors += 1;
    const previousStats = [...inputPortStats.values()].find((item) => item.ref === previous.portRef);
    if (previousStats) previousStats.possibleMirrors += 1;
    const previousObservation = observations.get(previous.observationKey);
    if (previousObservation) previousObservation.possibleMirrorCount += 1;
  }

  recentBySignature.set(signature, {
    portRef,
    timestamp: parsed.timestamp,
    observationKey: `${portRef}|${parsed.signalKey}`,
    rawEvent
  });
}

function populateTrialSelect() {
  elements.trialSelect.replaceChildren();
  const groups = new Map();
  for (const item of CAPABILITY_TEST_PLAN) {
    if (!groups.has(item.group)) {
      const group = document.createElement("optgroup");
      group.label = titleCase(item.group);
      groups.set(item.group, group);
      elements.trialSelect.append(group);
    }
    const option = document.createElement("option");
    option.value = item.key;
    option.textContent = item.label;
    groups.get(item.group).append(option);
  }
}

function selectedTrialDefinition() {
  const customLabel = elements.customTrialLabel.value.trim();
  if (customLabel) {
    return {
      key: `custom.${String(nextTrialNumber).padStart(3, "0")}`,
      group: "custom",
      label: customLabel,
      instructions: "Operate only the named control or mode, then finish the trial."
    };
  }
  return TEST_PLAN_BY_KEY.get(elements.trialSelect.value) || CAPABILITY_TEST_PLAN[0];
}

function updateTrialInstructions() {
  const definition = selectedTrialDefinition();
  const flags = [];
  if (definition.optional) flags.push("optional");
  if (definition.accessory) flags.push(`needs ${definition.accessory}`);
  if (definition.risk) flags.push(`caution: ${definition.risk}`);
  elements.trialInstructions.textContent = `${definition.instructions}${flags.length ? ` (${flags.join("; ")})` : ""}`;
}

function beginSelectedTrial() {
  if (!midiAccess) {
    setStatus("Enable MIDI before beginning a trial.", "bad");
    return;
  }
  if (activeTrial) {
    elements.activeTrialStatus.textContent = `Finish "${activeTrial.label}" before starting another trial.`;
    return;
  }

  const definition = selectedTrialDefinition();
  const id = `trial-${String(nextTrialNumber++).padStart(3, "0")}`;
  activeTrial = {
    id,
    planKey: definition.key,
    group: definition.group,
    label: definition.label,
    instructions: definition.instructions,
    startedAtMs: relativeNow(),
    startSequence: nextEventSequence,
    eventCount: 0,
    meaningfulEventCount: 0,
    portRefs: new Set(),
    signalRefs: new Set()
  };
  markCaptureDirty();
  elements.beginTrialButton.disabled = true;
  elements.finishTrialButton.disabled = false;
  elements.noMidiTrialButton.disabled = false;
  elements.activeTrialStatus.textContent = `ACTIVE: ${activeTrial.label}. Operate it at your own pace, then finish.`;
  setStatus(`Capturing trial: ${activeTrial.label}`, "good");
}

function finishActiveTrial(result) {
  if (!activeTrial) return;
  if (result === "no-midi-observed" && activeTrial.meaningfulEventCount > 0) {
    elements.activeTrialStatus.textContent = `${activeTrial.meaningfulEventCount} non-noise messages arrived during this trial. Finish it normally instead of recording no MIDI.`;
    return;
  }

  const completed = {
    id: activeTrial.id,
    planKey: activeTrial.planKey,
    group: activeTrial.group,
    label: activeTrial.label,
    instructions: activeTrial.instructions,
    result,
    observation: elements.trialObservation.value.trim(),
    startedAtMs: activeTrial.startedAtMs,
    endedAtMs: relativeNow(),
    startSequence: activeTrial.startSequence,
    endSequence: nextEventSequence - 1,
    eventCount: activeTrial.eventCount,
    meaningfulEventCount: activeTrial.meaningfulEventCount,
    portRefs: [...activeTrial.portRefs].sort(),
    signalRefs: [...activeTrial.signalRefs].sort()
  };
  trials.push(completed);
  if (result === "no-midi-observed") {
    manualObservations.push({
      trialId: completed.id,
      planKey: completed.planKey,
      label: completed.label,
      result,
      observation: completed.observation,
      recordedAtMs: completed.endedAtMs
    });
  }
  const finishedLabel = activeTrial.label;
  activeTrial = null;
  elements.customTrialLabel.value = "";
  elements.trialResult.value = "completed";
  elements.trialObservation.value = "";
  elements.beginTrialButton.disabled = false;
  elements.finishTrialButton.disabled = true;
  elements.noMidiTrialButton.disabled = true;
  elements.activeTrialStatus.textContent = `${finishedLabel}: ${result.replaceAll("-", " ")}.`;
  advanceTrialSelection(completed.planKey);
  updateTrialInstructions();
  scheduleRender();
}

function recordSelectedNoMidi() {
  if (activeTrial) {
    finishActiveTrial("no-midi-observed");
    return;
  }
  elements.activeTrialStatus.textContent = "Begin the trial, operate the physical control, then record no MIDI.";
}

function advanceTrialSelection(completedKey) {
  const currentIndex = CAPABILITY_TEST_PLAN.findIndex((item) => item.key === completedKey);
  const completedKeys = new Set(trials.map((trial) => trial.planKey));
  for (let offset = 1; offset <= CAPABILITY_TEST_PLAN.length; offset += 1) {
    const candidate = CAPABILITY_TEST_PLAN[(Math.max(currentIndex, -1) + offset) % CAPABILITY_TEST_PLAN.length];
    if (!completedKeys.has(candidate.key)) {
      elements.trialSelect.value = candidate.key;
      break;
    }
  }
}

function clearCapture() {
  const hasData = captureDirty || totalEvents > 0 || trials.length > 0 || outputProbes.length > 0;
  if (hasData && !window.confirm("Clear this unsaved capability capture?")) return;
  panicOpenedOutputs("Capture cleared");
  captureStartedAt = new Date().toISOString();
  captureStartPerformanceMs = performance.now();
  activeTrial = null;
  pendingOutputProbe = null;
  acknowledgedOutputId = null;
  totalEvents = 0;
  rawEventsDropped = 0;
  possibleMirrorCount = 0;
  nextEventSequence = 1;
  nextTrialNumber = 1;
  nextMirrorNumber = 1;
  observations.clear();
  trials.splice(0);
  manualObservations.splice(0);
  outputProbes.splice(0);
  outputCleanupActions.splice(0);
  portTransitions.splice(0);
  rawEvents.splice(0);
  recentEvents.splice(0);
  recentBySignature.clear();
  for (const stats of inputPortStats.values()) {
    stats.firstSeenAtMs = 0;
    stats.events = 0;
    stats.notes = 0;
    stats.controls = 0;
    stats.other = 0;
    stats.possibleMirrors = 0;
  }
  for (const stats of outputPortStats.values()) {
    stats.firstSeenAtMs = 0;
    stats.messagesSent = 0;
  }
  elements.finishTrialButton.disabled = true;
  elements.beginTrialButton.disabled = !midiAccess;
  elements.noMidiTrialButton.disabled = true;
  elements.recordProbeButton.disabled = true;
  elements.outputAcknowledgement.checked = false;
  elements.activeTrialStatus.textContent = "No trial is active.";
  elements.probeStatus.textContent = "No output probe sent.";
  captureDirty = false;
  setStatus("Capture cleared. Port visibility and controller-state form were kept.", "good");
  scheduleRender();
}

async function sendOutputProbe() {
  if (!midiAccess) return;
  const output = midiAccess.outputs.get(elements.outputSelect.value);
  if (!output) {
    elements.probeStatus.textContent = "Select one visible output first.";
    return;
  }
  if (!elements.outputAcknowledgement.checked || acknowledgedOutputId !== output.id) {
    elements.probeStatus.textContent = "Confirm the selected output and low audio volume first.";
    return;
  }

  const channel = boundedInteger(elements.probeChannel.value, 1, 16);
  const note = boundedInteger(elements.probeNote.value, 0, 127);
  const velocity = boundedInteger(elements.probeVelocity.value, 1, 32);
  if (channel === null || note === null || velocity === null) {
    elements.probeStatus.textContent = "Channel, note, or velocity is outside the allowed range.";
    return;
  }

  const stats = ensureOutputStats(output);
  const probe = {
    id: `probe-${String(outputProbes.length + 1).padStart(3, "0")}`,
    outputRef: stats.ref,
    channel,
    note,
    velocity,
    sentAtMs: relativeNow(),
    noteLengthMs: OUTPUT_NOTE_LENGTH_MS,
    result: "awaiting-observation",
    notes: "",
    noteOnSent: false,
    noteOffSent: false,
    allNotesOffSent: false,
    allSoundOffSent: false,
    cleanupComplete: false,
    sendError: null,
    cleanupError: null,
    outputClosed: false,
    closeError: null
  };
  outputProbes.push(probe);
  markCaptureDirty();
  pendingOutputProbe = probe;
  elements.sendProbeButton.disabled = true;

  const activeKey = `${output.id}:${channel}:${note}`;
  openedOutputIds.add(output.id);
  try {
    const sendResult = await sendSafeNoteProbe({
      output,
      channel,
      note,
      velocity,
      noteLengthMs: OUTPUT_NOTE_LENGTH_MS,
      onNoteOn: () => activeOutputNotes.set(activeKey, { outputId: output.id, channel, note }),
      onCleanup: (cleanup) => {
        if (cleanup.cleanupComplete) activeOutputNotes.delete(activeKey);
      }
    });
    Object.assign(probe, sendResult);
    stats.messagesSent += sendResult.messagesSent;
    if (sendResult.cleanupComplete) {
      try {
        await output.close();
        probe.outputClosed = true;
        openedOutputIds.delete(output.id);
      } catch (error) {
        probe.closeError = String(error.message || error);
      }
    }
    ensureOutputStats(output);
  } catch (error) {
    probe.sendError = String(error.message || error);
    probe.result = "send-error";
  }

  if (probe.cleanupError || (probe.noteOnSent && !probe.cleanupComplete)) {
    elements.probeStatus.textContent =
      `Cleanup was uncertain: ${probe.cleanupError || "unknown output error"}. ` +
      "Reconnect if needed, press Stop all test notes, and power-cycle the controller if sound continues.";
  } else if (probe.sendError) {
    elements.probeStatus.textContent = `Output probe failed: ${probe.sendError}`;
  } else if (probe.closeError) {
    elements.probeStatus.textContent =
      `The note and cleanup were sent, but the port did not close: ${probe.closeError}. ` +
      "Record the result; Stop all test notes can retry cleanup and release it.";
  } else {
    elements.probeStatus.textContent =
      `Sent and cleaned up note ${note} on channel ${channel} to ${stats.ref} (${stats.name}); ` +
      "the output was released. Record what happened.";
  }
  elements.recordProbeButton.disabled = false;
  updateOutputControls();
  scheduleRender();
}

function recordProbeResult() {
  if (!pendingOutputProbe) return;
  pendingOutputProbe.result = elements.probeResult.value;
  pendingOutputProbe.notes = elements.probeNotes.value.trim();
  pendingOutputProbe.observedAtMs = relativeNow();
  markCaptureDirty();
  elements.probeStatus.textContent = `Recorded ${pendingOutputProbe.outputRef}: ${pendingOutputProbe.result}.`;
  pendingOutputProbe = null;
  elements.probeNotes.value = "";
  elements.recordProbeButton.disabled = true;
  updateOutputControls();
}

async function manualPanic() {
  if (!midiAccess) return;
  const selectedOutput = midiAccess.outputs.get(elements.outputSelect.value);
  if (selectedOutput) {
    openedOutputIds.add(selectedOutput.id);
    try {
      await selectedOutput.open();
    } catch (error) {
      elements.probeStatus.textContent =
        `Could not open the selected output for cleanup: ${error.message || error}. ` +
        "Reconnect it and retry, then power-cycle the receiver if sound continues.";
    }
  }
  panicOpenedOutputs("Manual panic");
  markCaptureDirty();
  updateOutputControls();
  scheduleRender();
}

function panicOpenedOutputs(reason) {
  if (!midiAccess) return;
  let errorCount = 0;
  for (const outputId of openedOutputIds) {
    const output = midiAccess.outputs.get(outputId);
    if (!output) {
      const stats = outputPortStats.get(outputId);
      outputCleanupActions.push({
        atMs: relativeNow(),
        reason,
        outputRef: stats?.ref ?? "unavailable-output",
        clearCalled: false,
        noteOffsSent: 0,
        allNotesOffSent: 0,
        allSoundOffSent: 0,
        outputClosed: false,
        closeError: "Output is no longer visible; reconnect it and retry cleanup.",
        messagesSent: 0,
        errors: ["output unavailable"]
      });
      errorCount += 1;
      continue;
    }
    const active = [...activeOutputNotes.values()].filter((note) => note.outputId === outputId);
    const result = panicMidiOutput(output, active);
    const stats = ensureOutputStats(output);
    stats.messagesSent += result.messagesSent;
    errorCount += result.errors.length;
    const cleanupAction = {
      atMs: relativeNow(),
      reason,
      outputRef: stats.ref,
      ...result,
      outputClosed: false,
      closeError: null
    };
    outputCleanupActions.push(cleanupAction);
    if (result.errors.length === 0) {
      for (const [key, note] of activeOutputNotes) {
        if (note.outputId === outputId) activeOutputNotes.delete(key);
      }
      try {
        Promise.resolve(output.close())
          .then(() => {
            openedOutputIds.delete(outputId);
            cleanupAction.outputClosed = true;
            ensureOutputStats(output);
            updateOutputControls();
            scheduleRender();
          })
          .catch((error) => {
            cleanupAction.closeError = String(error.message || error);
            cleanupAction.errors.push(`close: ${cleanupAction.closeError}`);
          });
      } catch (error) {
        cleanupAction.closeError = String(error.message || error);
        cleanupAction.errors.push(`close: ${cleanupAction.closeError}`);
      }
    }
  }
  if (reason === "Manual panic") {
    elements.probeStatus.textContent = errorCount
      ? `Cleanup reported ${errorCount} error(s). Reconnect and retry, then power-cycle if sound continues.`
      : "Sent cleanup-only messages to every output opened by this page.";
  }
}

async function saveInventory() {
  if (activeTrial) {
    setStatus(`Finish the active trial "${activeTrial.label}" before saving.`, "bad");
    return;
  }
  if (pendingOutputProbe) {
    setStatus("Record the pending output-probe observation before saving.", "bad");
    return;
  }
  elements.saveButton.disabled = true;
  setStatus("Saving private capability census...");

  const payload = {
    schemaVersion: 2,
    session: {
      startedAt: captureStartedAt,
      savedAt: new Date().toISOString(),
      durationMs: relativeNow(),
      launcherBackend,
      sysexEnabled: false,
      browserUserAgent: navigator.userAgent,
      metadata: sessionMetadata(),
      rawEventLimit: MAX_RAW_EVENTS,
      rawEventsDropped,
      physicalInputLatencyMeasured: false
    },
    totals: {
      events: totalEvents,
      rawEventsRetained: rawEvents.length,
      rawEventsDropped,
      distinctSignals: observations.size,
      possibleMirrorCandidates: possibleMirrorCount,
      trials: trials.length,
      noMidiObserved: manualObservations.length,
      outputProbes: outputProbes.length
    },
    ports: {
      inputs: [...inputPortStats.values()],
      outputs: [...outputPortStats.values()],
      transitions: portTransitions
    },
    signals: [...observations.values()],
    trials,
    noMidiObserved: manualObservations,
    outputProbes,
    outputCleanupActions,
    rawEvents,
    testPlan: {
      version: 1,
      availableSteps: CAPABILITY_TEST_PLAN.length,
      completedPlanKeys: [...new Set(trials.map((trial) => trial.planKey))]
    },
    limitations: [
      "Physical control-to-software latency is not measured without an external physical or audio reference.",
      "Mirror candidates are preserved, not deduplicated, and require offline analysis.",
      "Web MIDI SysEx permission was not requested; unknown SysEx and device-identity protocols were not probed.",
      "Audio routing, physical MIDI OUT, and panel-only behavior require explicit manual observations."
    ],
    note: "Private local MIDI capability census. Do not publish raw hardware or performance data."
  };

  try {
    const response = await fetch("/api/save-inventory", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload)
    });
    const result = await response.json();
    if (!response.ok) throw new Error(result.error || `HTTP ${response.status}`);
    const reportMessage = result.reportRelativePath
      ? ` and analyzed to ${result.reportRelativePath}`
      : result.reportError
        ? `; raw census saved but analysis failed: ${result.reportError}`
        : "";
    setStatus(`Saved privately to ${result.relativePath}${reportMessage}`, result.reportError ? "bad" : "good");
    captureDirty = false;
  } catch (error) {
    setStatus(`Could not save census: ${error.message || error}`, "bad");
  } finally {
    elements.saveButton.disabled = false;
  }
}

function sessionMetadata() {
  const values = Object.fromEntries(new FormData(elements.sessionForm).entries());
  for (const [key, value] of Object.entries(values)) values[key] = String(value).trim();
  return values;
}

function renderOutputOptions() {
  const selectedId = elements.outputSelect.value;
  elements.outputSelect.replaceChildren();
  const placeholder = document.createElement("option");
  placeholder.value = "";
  placeholder.textContent = "Select exactly one output";
  elements.outputSelect.append(placeholder);
  const outputs = [...outputPortStats.values()].filter((port) => port.present).sort((a, b) => a.ref.localeCompare(b.ref));
  for (const port of outputs) {
    const option = document.createElement("option");
    option.value = port.id;
    option.textContent = `${port.ref}: ${port.name}`;
    elements.outputSelect.append(option);
  }
  if (outputs.some((port) => port.id === selectedId)) elements.outputSelect.value = selectedId;
  elements.outputAcknowledgement.checked = false;
  acknowledgedOutputId = null;
  elements.outputSelect.disabled = outputs.length === 0;
  updateOutputControls();
}

function updateOutputControls() {
  const hasOutput = Boolean(midiAccess?.outputs.get(elements.outputSelect.value));
  const acknowledgementMatches = elements.outputAcknowledgement.checked && acknowledgedOutputId === elements.outputSelect.value;
  elements.sendProbeButton.disabled = !hasOutput || !acknowledgementMatches || Boolean(pendingOutputProbe);
  elements.panicButton.disabled = !hasOutput && openedOutputIds.size === 0;
}

function handleOutputSelectionChange() {
  elements.outputAcknowledgement.checked = false;
  acknowledgedOutputId = null;
  updateOutputControls();
}

function handleOutputAcknowledgement() {
  acknowledgedOutputId = elements.outputAcknowledgement.checked ? elements.outputSelect.value : null;
  updateOutputControls();
}

function scheduleRender() {
  if (renderPending) return;
  renderPending = true;
  requestAnimationFrame(() => {
    renderPending = false;
    render();
  });
}

function render() {
  elements.inputCount.textContent = String([...inputPortStats.values()].filter((port) => port.present).length);
  elements.outputCount.textContent = String([...outputPortStats.values()].filter((port) => port.present).length);
  elements.eventCount.textContent = String(totalEvents);
  elements.rawCount.textContent = rawEventsDropped ? `${rawEvents.length} +${rawEventsDropped} dropped` : String(rawEvents.length);
  elements.signalCount.textContent = String(observations.size);
  elements.trialCount.textContent = String(trials.length);
  renderPorts();
  renderSignals();
  renderTrials();
  renderManualObservations();
  renderRecentEvents();
}

function renderPorts() {
  elements.portsBody.replaceChildren();
  const ports = [
    ...[...inputPortStats.values()].map((port) => ({ ...port, sortDirection: 0 })),
    ...[...outputPortStats.values()].map((port) => ({ ...port, sortDirection: 1 }))
  ].sort((a, b) => a.sortDirection - b.sortDirection || a.ref.localeCompare(b.ref));
  if (ports.length === 0) {
    appendEmptyRow(elements.portsBody, 8, "No MIDI ports visible.");
    return;
  }
  for (const port of ports) {
    const row = document.createElement("tr");
    appendCells(row, [
      port.ref,
      port.direction,
      port.name,
      port.openError ? `error: ${port.openError}` : `${port.state}/${port.connection}${port.present ? "" : " (gone)"}`,
      port.direction === "input" ? port.events : `${port.messagesSent} sent`,
      port.direction === "input" ? port.notes : "-",
      port.direction === "input" ? port.controls : "-",
      port.direction === "input" ? `${port.other}${port.possibleMirrors ? ` (${port.possibleMirrors} mirror flags)` : ""}` : "-"
    ]);
    elements.portsBody.append(row);
  }
}

function renderSignals() {
  elements.signalsBody.replaceChildren();
  const signals = [...observations.values()].sort((a, b) => {
    return a.portRef.localeCompare(b.portRef) || a.signalKey.localeCompare(b.signalKey);
  });
  if (signals.length === 0) {
    appendEmptyRow(elements.signalsBody, 6, "Operate a control to discover it.");
    return;
  }
  for (const signal of signals) {
    const range = signal.minValue === null
      ? "-"
      : signal.minValue === signal.maxValue
        ? String(signal.minValue)
        : `${signal.minValue}...${signal.maxValue}`;
    const labels = signal.trialKeys.slice(0, 3).map((key) => TEST_PLAN_BY_KEY.get(key)?.label || key);
    if (signal.trialKeys.length > 3) labels.push(`+${signal.trialKeys.length - 3} more`);
    const row = document.createElement("tr");
    appendCells(row, [
      labels.join(", ") || "unassigned",
      `${signal.portRef}: ${signal.portName}`,
      describeSignal(signal),
      `${signal.lastMessageType} / ${signal.lastValue ?? "-"}`,
      range,
      `${signal.count}${signal.possibleMirrorCount ? ` (${signal.possibleMirrorCount} mirror flags)` : ""}`
    ]);
    elements.signalsBody.append(row);
  }
}

function renderTrials() {
  elements.trialList.replaceChildren();
  if (trials.length === 0) {
    appendListItem(elements.trialList, "None yet.", "empty");
    return;
  }
  for (const trial of trials) {
    const observation = trial.observation ? `; ${trial.observation}` : "";
    appendListItem(
      elements.trialList,
      `${trial.label}: ${trial.result}; ${trial.eventCount} events on ${trial.portRefs.length} port(s)${observation}`
    );
  }
}

function renderManualObservations() {
  elements.manualList.replaceChildren();
  if (manualObservations.length === 0) {
    appendListItem(elements.manualList, "None recorded.", "empty");
    return;
  }
  for (const item of manualObservations) {
    appendListItem(
      elements.manualList,
      `${item.label}: no MIDI observed${item.observation ? `; ${item.observation}` : ""}`
    );
  }
}

function renderRecentEvents() {
  elements.recentList.replaceChildren();
  if (recentEvents.length === 0) {
    appendListItem(elements.recentList, "Waiting for MIDI.", "empty");
    return;
  }
  for (const event of recentEvents.slice(0, 30)) {
    appendListItem(
      elements.recentList,
      `${event.portRef} | ${event.trialKey || "no trial"} | ${event.parsed.messageType} | ` +
      `${event.parsed.signalKey} | value ${event.parsed.value ?? "-"} | [${event.bytes.join(" ")}]`
    );
  }
}

function describeSignal(signal) {
  if (signal.category === "note") return `${signal.noteName || "Note"} (${signal.number}), channel ${signal.channel}`;
  if (signal.category === "control-change") return `CC ${signal.number}, channel ${signal.channel}`;
  return `${signal.signalKey}${signal.channel ? `, channel ${signal.channel}` : ""}`;
}

function appendCells(row, values) {
  for (const value of values) {
    const cell = document.createElement("td");
    cell.textContent = String(value);
    row.append(cell);
  }
}

function appendEmptyRow(body, colspan, message) {
  const row = document.createElement("tr");
  const cell = document.createElement("td");
  cell.colSpan = colspan;
  cell.className = "empty";
  cell.textContent = message;
  row.append(cell);
  body.append(row);
}

function appendListItem(list, message, className = "") {
  const item = document.createElement("li");
  item.className = className;
  item.textContent = message;
  list.append(item);
}

function setStatus(message, tone = "") {
  elements.statusText.className = `status${tone ? ` ${tone}` : ""}`;
  elements.statusText.textContent = message;
}

function relativeNow() {
  return roundMilliseconds(performance.now() - captureStartPerformanceMs);
}

function roundMilliseconds(value) {
  return Number.isFinite(value) ? Math.round(value * 1000) / 1000 : null;
}

function boundedInteger(value, minimum, maximum) {
  const parsed = Number(value);
  return Number.isInteger(parsed) && parsed >= minimum && parsed <= maximum ? parsed : null;
}

function titleCase(value) {
  return String(value).replaceAll("-", " ").replace(/\b\w/g, (letter) => letter.toUpperCase());
}

function markCaptureDirty() {
  captureDirty = true;
}

function warnBeforeUnsavedUnload(event) {
  if (!captureDirty) return;
  event.preventDefault();
  event.returnValue = "";
}

render();
