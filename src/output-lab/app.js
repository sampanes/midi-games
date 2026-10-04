import { parseMidiMessage } from "/midi/midi-parser.js";
import { panicMidiOutput, sendSafeNoteProbe } from "/midi/output-probe.js";
import {
  DEFAULT_PAD_NOTES,
  OUTPUT_LAB_KIND,
  OUTPUT_LAB_SCHEMA_VERSION,
  parsePadNotes,
  runPadSweep,
  sendProgramChange
} from "/midi/output-lab.js";

const MAX_INCOMING = 2000;
const byId = (id) => document.getElementById(id);
const el = {
  enable: byId("enable-button"),
  panic: byId("panic-button"),
  save: byId("save-button"),
  status: byId("status-text"),
  output: byId("output-select"),
  ack: byId("ack"),
  padChannel: byId("pad-channel"),
  padVelocity: byId("pad-velocity"),
  padHold: byId("pad-hold"),
  padNotes: byId("pad-notes"),
  sweep: byId("sweep-button"),
  stopSweep: byId("stop-sweep-button"),
  sweepStatus: byId("sweep-status"),
  noteChannel: byId("note-channel"),
  noteNumber: byId("note-number"),
  noteVelocity: byId("note-velocity"),
  note: byId("note-button"),
  pcChannel: byId("pc-channel"),
  pcProgram: byId("pc-program"),
  pc: byId("pc-button"),
  pending: byId("pending-text"),
  result: byId("result-select"),
  resultNotes: byId("result-notes"),
  record: byId("record-button"),
  actionList: byId("action-list"),
  incomingList: byId("incoming-list")
};

const startedAt = performance.now();
const actions = [];
const incoming = [];
const usedOutputIds = new Set();
let midiAccess = null;
let busy = false;
let stopRequested = false;
let pendingAction = null;

el.padNotes.value = DEFAULT_PAD_NOTES.join(", ");
el.enable.addEventListener("click", enable);
el.output.addEventListener("change", () => { el.ack.checked = false; updateControls(); });
el.ack.addEventListener("change", updateControls);
el.sweep.addEventListener("click", padSweep);
el.stopSweep.addEventListener("click", () => { stopRequested = true; });
el.note.addEventListener("click", testNote);
el.pc.addEventListener("click", programChange);
el.record.addEventListener("click", recordResult);
el.panic.addEventListener("click", () => panicAll("manual"));
el.save.addEventListener("click", save);
window.addEventListener("pagehide", () => panicAll("page closed"));

if (!("requestMIDIAccess" in navigator)) {
  setStatus("This browser has no Web MIDI. Use Chrome or Edge via the start script.", "bad");
  el.enable.disabled = true;
}

const now = () => Math.round((performance.now() - startedAt) * 10) / 10;

async function enable() {
  el.enable.disabled = true;
  try {
    midiAccess = await navigator.requestMIDIAccess({ sysex: false });
    midiAccess.onstatechange = refreshPorts;
    refreshPorts();
    el.save.disabled = false;
    setStatus(`Ready: ${midiAccess.outputs.size} outputs, ${midiAccess.inputs.size} inputs.`, "good");
  } catch (error) {
    el.enable.disabled = false;
    setStatus(`MIDI access failed: ${error.message || error}`, "bad");
  }
}

function refreshPorts() {
  for (const input of midiAccess.inputs.values()) {
    input.onmidimessage = (event) => onIncoming(input, event);
  }
  const selected = el.output.value;
  el.output.replaceChildren(new Option("Select one output", ""));
  for (const output of midiAccess.outputs.values()) {
    el.output.append(new Option(output.name || output.id, output.id));
  }
  if (midiAccess.outputs.get(selected)) el.output.value = selected;
  else el.ack.checked = false;
  el.output.disabled = midiAccess.outputs.size === 0;
  updateControls();
}

function onIncoming(input, event) {
  if (incoming.length >= MAX_INCOMING) return;
  const parsed = parseMidiMessage(event.data, event.timeStamp);
  if (!parsed || parsed.messageType === "timing-clock" || parsed.messageType === "active-sensing") return;
  incoming.push({
    atMs: now(),
    port: input.name || input.id,
    bytes: parsed.bytes,
    signalKey: parsed.signalKey,
    duringAction: pendingAction?.id ?? null
  });
  render();
}

function selectedOutput() {
  if (!midiAccess || !el.ack.checked) return null;
  return midiAccess.outputs.get(el.output.value) ?? null;
}

function updateControls() {
  const ready = Boolean(selectedOutput()) && !busy && !pendingAction;
  el.sweep.disabled = !ready;
  el.note.disabled = !ready;
  el.pc.disabled = !ready;
  el.stopSweep.disabled = !busy;
  el.panic.disabled = !midiAccess;
  el.record.disabled = !pendingAction;
  el.pending.textContent = pendingAction
    ? `Waiting for your result on ${pendingAction.id}: ${pendingAction.summary}`
    : "Nothing waiting for a result.";
}

function intField(input, min, max) {
  const value = Number(input.value);
  return Number.isInteger(value) && value >= min && value <= max ? value : null;
}

function beginAction(type, output, details, summary) {
  const action = {
    id: `action-${String(actions.length + 1).padStart(3, "0")}`,
    type,
    output: output.name || output.id,
    atMs: now(),
    ...details,
    summary,
    result: "awaiting-observation",
    notes: ""
  };
  actions.push(action);
  usedOutputIds.add(output.id);
  pendingAction = action;
  render();
  return action;
}

async function padSweep() {
  const output = selectedOutput();
  const channel = intField(el.padChannel, 1, 16);
  const velocity = intField(el.padVelocity, 1, 32);
  const holdMs = intField(el.padHold, 50, 2000);
  let notes;
  try { notes = parsePadNotes(el.padNotes.value); } catch (error) {
    el.sweepStatus.textContent = error.message;
    return;
  }
  if (!output || channel === null || velocity === null || holdMs === null) {
    el.sweepStatus.textContent = "Check the output, channel, velocity (1-32), and hold time.";
    return;
  }
  const action = beginAction("pad-sweep", output, { channel, velocity, holdMs, notes },
    `pad sweep ch ${channel} vel ${velocity} on ${output.name}`);
  busy = true;
  stopRequested = false;
  updateControls();
  try {
    const sweep = await runPadSweep({
      output, channel, notes, velocity, holdMs,
      onStep: ({ index, note }) => { el.sweepStatus.textContent = `Now: pad ${index + 1} (note ${note})`; },
      shouldStop: () => stopRequested
    });
    action.completed = sweep.completed;
    action.stepsSent = sweep.steps.length;
    action.cleanupComplete = sweep.steps.every((step) => step.cleanupComplete);
    const failure = sweep.steps.find((step) => step.sendError || step.cleanupError);
    action.error = failure ? (failure.sendError || failure.cleanupError) : null;
    el.sweepStatus.textContent = action.error
      ? `Stopped on an error: ${action.error}. Press Stop all sound.`
      : `${sweep.completed ? "Finished" : "Stopped"} after ${sweep.steps.length} pads. Record what you saw.`;
  } catch (error) {
    action.error = String(error.message || error);
    el.sweepStatus.textContent = `Sweep failed: ${action.error}`;
  } finally {
    busy = false;
    render();
  }
}

async function testNote() {
  const output = selectedOutput();
  const channel = intField(el.noteChannel, 1, 16);
  const note = intField(el.noteNumber, 0, 127);
  const velocity = intField(el.noteVelocity, 1, 32);
  if (!output || channel === null || note === null || velocity === null) {
    setStatus("Check the output, channel, note, and velocity (1-32).", "bad");
    return;
  }
  const action = beginAction("test-note", output, { channel, note, velocity },
    `note ${note} ch ${channel} vel ${velocity} on ${output.name}`);
  busy = true;
  updateControls();
  try {
    const result = await sendSafeNoteProbe({ output, channel, note, velocity });
    action.cleanupComplete = result.cleanupComplete;
    action.error = result.sendError || result.cleanupError;
  } catch (error) {
    action.error = String(error.message || error);
  } finally {
    busy = false;
    render();
  }
}

async function programChange() {
  const output = selectedOutput();
  const channel = intField(el.pcChannel, 1, 16);
  const program = intField(el.pcProgram, 0, 127);
  if (!output || channel === null || program === null) {
    setStatus("Check the output, channel, and program (0-127).", "bad");
    return;
  }
  const action = beginAction("program-change", output, { channel, program },
    `Program Change ${program} ch ${channel} on ${output.name}`);
  busy = true;
  updateControls();
  try {
    const result = await sendProgramChange({ output, channel, program });
    action.bytes = result.bytes;
    action.error = result.sendError;
  } finally {
    busy = false;
    render();
  }
}

function recordResult() {
  if (!pendingAction) return;
  pendingAction.result = el.result.value;
  pendingAction.notes = el.resultNotes.value.trim();
  pendingAction.observedAtMs = now();
  pendingAction = null;
  el.resultNotes.value = "";
  render();
}

function panicAll(reason) {
  if (!midiAccess) return;
  stopRequested = true;
  for (const id of usedOutputIds) {
    const output = midiAccess.outputs.get(id);
    if (!output) continue;
    const result = panicMidiOutput(output, []);
    actions.push({
      id: `cleanup-${String(actions.length + 1).padStart(3, "0")}`,
      type: "panic",
      output: output.name || output.id,
      atMs: now(),
      reason,
      messagesSent: result.messagesSent,
      errors: result.errors,
      result: "cleanup",
      notes: ""
    });
  }
  render();
}

async function save() {
  el.save.disabled = true;
  const log = {
    kind: OUTPUT_LAB_KIND,
    schemaVersion: OUTPUT_LAB_SCHEMA_VERSION,
    savedAt: new Date().toISOString(),
    browserUserAgent: navigator.userAgent,
    actions,
    incoming
  };
  try {
    const response = await fetch("/api/save-inventory", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(log)
    });
    const body = await response.json();
    if (!response.ok) throw new Error(body.error || `HTTP ${response.status}`);
    setStatus(`Saved privately to ${body.relativePath}`, "good");
  } catch (error) {
    setStatus(`Could not save: ${error.message || error}`, "bad");
  } finally {
    el.save.disabled = false;
  }
}

function render() {
  updateControls();
  fillList(el.actionList, [...actions].reverse().slice(0, 50).map((a) =>
    `${a.id} | ${a.type} | ${a.summary || a.reason || ""} | ${a.result}${a.notes ? ` | ${a.notes}` : ""}${a.error ? ` | ERROR ${a.error}` : ""}`
  ), "No actions yet.");
  fillList(el.incomingList, [...incoming].reverse().slice(0, 30).map((m) =>
    `${m.atMs} ms | ${m.port} | ${m.signalKey} | [${m.bytes.join(" ")}]${m.duringAction ? ` | during ${m.duringAction}` : ""}`
  ), "Nothing received.");
}

function fillList(list, lines, emptyText) {
  list.replaceChildren();
  if (lines.length === 0) {
    const item = document.createElement("li");
    item.className = "empty";
    item.textContent = emptyText;
    list.append(item);
    return;
  }
  for (const line of lines) {
    const item = document.createElement("li");
    item.textContent = line;
    list.append(item);
  }
}

function setStatus(message, tone = "") {
  el.status.className = `status${tone ? ` ${tone}` : ""}`;
  el.status.textContent = message;
}
