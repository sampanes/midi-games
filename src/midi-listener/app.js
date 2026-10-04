import { parseMidiMessage, rangeValue } from "/midi/midi-parser.js";

const MAX_RECENT_EVENTS = 200;
const MIRROR_WINDOW_MS = 12;
const SYSTEM_NOISE_TYPES = new Set(["timing-clock", "active-sensing"]);

const elements = {
  enableButton: document.querySelector("#enable-button"),
  clearButton: document.querySelector("#clear-button"),
  saveButton: document.querySelector("#save-button"),
  labelInput: document.querySelector("#label-input"),
  armButton: document.querySelector("#arm-button"),
  noMidiButton: document.querySelector("#no-midi-button"),
  statusText: document.querySelector("#status-text"),
  armedStatus: document.querySelector("#armed-status"),
  inputCount: document.querySelector("#input-count"),
  eventCount: document.querySelector("#event-count"),
  signalCount: document.querySelector("#signal-count"),
  mirrorCount: document.querySelector("#mirror-count"),
  portsBody: document.querySelector("#ports-body"),
  signalsBody: document.querySelector("#signals-body"),
  manualList: document.querySelector("#manual-list"),
  recentList: document.querySelector("#recent-list")
};

let midiAccess = null;
let armedLabel = null;
// The most recent captured label, so the same physical event arriving on a
// mirror port moments later receives the same label.
let lastCapturedLabel = null;
let totalEvents = 0;
let possibleMirrorCount = 0;
let renderPending = false;
const portStats = new Map();
const observations = new Map();
const manualObservations = [];
const recentEvents = [];
const recentBySignature = new Map();

elements.enableButton.addEventListener("click", enableMidi);
elements.clearButton.addEventListener("click", clearObservations);
elements.saveButton.addEventListener("click", saveInventory);
elements.armButton.addEventListener("click", armNextSignal);
elements.noMidiButton.addEventListener("click", recordNoMidi);

if (!("requestMIDIAccess" in navigator)) {
  setStatus("This browser does not expose the Web MIDI API. Open this page in Chrome or Edge.", "bad");
  elements.enableButton.disabled = true;
}

async function enableMidi() {
  elements.enableButton.disabled = true;
  setStatus("Requesting MIDI permission...");

  try {
    midiAccess = await navigator.requestMIDIAccess({ sysex: false });
    midiAccess.onstatechange = () => refreshPorts();
    await refreshPorts();
    elements.clearButton.disabled = false;
    elements.saveButton.disabled = false;
    elements.armButton.disabled = false;
    elements.noMidiButton.disabled = false;
    setStatus(`Listening to ${midiAccess.inputs.size} MIDI input${midiAccess.inputs.size === 1 ? "" : "s"}.`, "good");
  } catch (error) {
    elements.enableButton.disabled = false;
    setStatus(`MIDI access failed: ${error.message || error}`, "bad");
  }
}

async function refreshPorts() {
  if (!midiAccess) return;

  const activeIds = new Set();
  const opening = [];
  for (const input of midiAccess.inputs.values()) {
    activeIds.add(input.id);
    ensurePortStats(input);
    input.onmidimessage = (event) => handleMidiMessage(input, event);
    if (input.connection !== "open") {
      opening.push(input.open().then(() => {
        ensurePortStats(input);
      }).catch((error) => {
        const stats = ensurePortStats(input);
        stats.openError = String(error.message || error);
      }));
    }
  }

  await Promise.all(opening);
  for (const [portId, stats] of portStats) {
    stats.present = activeIds.has(portId);
  }
  scheduleRender();
}

function ensurePortStats(input) {
  if (!portStats.has(input.id)) {
    portStats.set(input.id, {
      id: input.id,
      name: input.name || "Unnamed MIDI input",
      manufacturer: input.manufacturer || "",
      state: input.state,
      connection: input.connection,
      present: true,
      openError: null,
      events: 0,
      notes: 0,
      controls: 0,
      other: 0,
      possibleMirrors: 0
    });
  }

  const stats = portStats.get(input.id);
  stats.name = input.name || stats.name;
  stats.manufacturer = input.manufacturer || stats.manufacturer;
  stats.state = input.state;
  stats.connection = input.connection;
  stats.present = true;
  return stats;
}

function handleMidiMessage(input, event) {
  const parsed = parseMidiMessage(event.data, event.timeStamp);
  if (!parsed) return;

  totalEvents += 1;
  const stats = ensurePortStats(input);
  stats.events += 1;
  if (parsed.category === "note") stats.notes += 1;
  else if (parsed.category === "control-change") stats.controls += 1;
  else stats.other += 1;

  const observationKey = `${input.id}|${parsed.signalKey}`;
  const now = new Date().toISOString();
  let observation = observations.get(observationKey);
  if (!observation) {
    observation = {
      portId: input.id,
      portName: input.name || "Unnamed MIDI input",
      manufacturer: input.manufacturer || "",
      signalKey: parsed.signalKey,
      category: parsed.category,
      channel: parsed.channel ?? null,
      number: parsed.number ?? null,
      noteName: parsed.noteName ?? null,
      label: "",
      firstSeen: now,
      lastSeen: now,
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
  observation.lastSeen = now;
  observation.lastMessageType = parsed.messageType;
  observation.lastBytes = parsed.bytes;
  if (Number.isFinite(parsed.value)) {
    observation.lastValue = parsed.value;
  }
  const valueForRange = rangeValue(parsed);
  if (valueForRange !== null) {
    observation.minValue = observation.minValue === null ? valueForRange : Math.min(observation.minValue, valueForRange);
    observation.maxValue = observation.maxValue === null ? valueForRange : Math.max(observation.maxValue, valueForRange);
  }

  const isSystemNoise = parsed.category === "system" && SYSTEM_NOISE_TYPES.has(parsed.messageType);
  const previousMirror = isSystemNoise ? null : detectPossibleMirror(input.id, parsed, observation);
  const signature = parsed.bytes.join(",");

  if (armedLabel && parsed.phase !== "release" && parsed.category !== "system") {
    observation.label = armedLabel;
    lastCapturedLabel = { label: armedLabel, signature, portId: input.id, timestamp: parsed.timestamp };
    // A mirror copy may have arrived on another port just before this one.
    const previousObservation = previousMirror ? observations.get(previousMirror.observationKey) : null;
    if (previousObservation && !previousObservation.label) {
      previousObservation.label = armedLabel;
    }
    armedLabel = null;
    elements.labelInput.value = "";
    elements.armedStatus.textContent = "Label captured. No label is armed.";
  } else if (
    lastCapturedLabel &&
    !observation.label &&
    lastCapturedLabel.signature === signature &&
    lastCapturedLabel.portId !== input.id &&
    Math.abs(parsed.timestamp - lastCapturedLabel.timestamp) <= MIRROR_WINDOW_MS
  ) {
    observation.label = lastCapturedLabel.label;
  }

  if (!isSystemNoise) {
    recentEvents.unshift({
      portId: input.id,
      portName: input.name || "Unnamed MIDI input",
      signalKey: parsed.signalKey,
      messageType: parsed.messageType,
      channel: parsed.channel ?? null,
      value: parsed.value ?? null,
      bytes: parsed.bytes,
      timestamp: event.timeStamp
    });
    recentEvents.splice(MAX_RECENT_EVENTS);
  }
  scheduleRender();
}

// Flags an event that repeats identical bytes from another port within the
// mirror window. Returns that earlier event when it qualifies, else null.
function detectPossibleMirror(portId, parsed, observation) {
  const signature = parsed.bytes.join(",");
  const previous = recentBySignature.get(signature);
  const isMirror = Boolean(
    previous &&
    previous.portId !== portId &&
    Math.abs(parsed.timestamp - previous.timestamp) <= MIRROR_WINDOW_MS
  );
  if (isMirror) {
    possibleMirrorCount += 1;
    observation.possibleMirrorCount += 1;
    const stats = portStats.get(portId);
    if (stats) stats.possibleMirrors += 1;
    const previousStats = portStats.get(previous.portId);
    if (previousStats) previousStats.possibleMirrors += 1;
    const previousObservation = observations.get(previous.observationKey);
    if (previousObservation) previousObservation.possibleMirrorCount += 1;
  }

  recentBySignature.set(signature, {
    portId,
    timestamp: parsed.timestamp,
    observationKey: `${portId}|${parsed.signalKey}`
  });
  return isMirror ? previous : null;
}

function armNextSignal() {
  const label = elements.labelInput.value.trim();
  if (!label) {
    elements.armedStatus.textContent = "Enter a physical label before arming.";
    elements.labelInput.focus();
    return;
  }

  armedLabel = label;
  elements.armedStatus.textContent = `Armed "${label}". Operate that physical control once.`;
}

function recordNoMidi() {
  const label = elements.labelInput.value.trim();
  if (!label) {
    elements.armedStatus.textContent = "Enter the physical button or control name first.";
    elements.labelInput.focus();
    return;
  }

  manualObservations.push({
    label,
    result: "no-midi-observed",
    recordedAt: new Date().toISOString()
  });
  armedLabel = null;
  elements.labelInput.value = "";
  elements.armedStatus.textContent = "Recorded as no MIDI observed.";
  scheduleRender();
}

function clearObservations() {
  totalEvents = 0;
  possibleMirrorCount = 0;
  armedLabel = null;
  lastCapturedLabel = null;
  observations.clear();
  manualObservations.splice(0);
  recentEvents.splice(0);
  recentBySignature.clear();
  for (const stats of portStats.values()) {
    stats.events = 0;
    stats.notes = 0;
    stats.controls = 0;
    stats.other = 0;
    stats.possibleMirrors = 0;
  }
  elements.armedStatus.textContent = "No label is armed.";
  setStatus(`Listening to ${midiAccess?.inputs.size ?? 0} MIDI inputs. Observations cleared.`, "good");
  scheduleRender();
}

async function saveInventory() {
  elements.saveButton.disabled = true;
  setStatus("Saving private inventory...");
  const payload = {
    schemaVersion: 1,
    savedAt: new Date().toISOString(),
    note: "Private local MIDI control inventory. Do not commit.",
    totals: {
      events: totalEvents,
      distinctSignals: observations.size,
      possibleMirrors: possibleMirrorCount,
      noMidiObserved: manualObservations.length
    },
    ports: [...portStats.values()],
    signals: [...observations.values()],
    noMidiObserved: manualObservations,
    recentEventSample: recentEvents
  };

  try {
    const response = await fetch("/api/save-inventory", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload)
    });
    const result = await response.json();
    if (!response.ok) throw new Error(result.error || `HTTP ${response.status}`);
    setStatus(`Saved privately to ${result.relativePath}`, "good");
  } catch (error) {
    setStatus(`Could not save inventory: ${error.message || error}`, "bad");
  } finally {
    elements.saveButton.disabled = false;
  }
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
  elements.inputCount.textContent = String([...portStats.values()].filter((port) => port.present).length);
  elements.eventCount.textContent = String(totalEvents);
  elements.signalCount.textContent = String(observations.size);
  elements.mirrorCount.textContent = String(possibleMirrorCount);
  renderPorts();
  renderSignals();
  renderManualObservations();
  renderRecentEvents();
}

function renderPorts() {
  elements.portsBody.replaceChildren();
  const ports = [...portStats.values()].sort((a, b) => a.name.localeCompare(b.name));
  if (ports.length === 0) {
    appendEmptyRow(elements.portsBody, 6, "No MIDI inputs opened.");
    return;
  }

  for (const port of ports) {
    const row = document.createElement("tr");
    appendCells(row, [
      port.name,
      port.openError ? `error: ${port.openError}` : `${port.state}/${port.connection}`,
      port.events,
      port.notes,
      port.controls,
      `${port.other}${port.possibleMirrors ? ` (${port.possibleMirrors} mirror flags)` : ""}`
    ]);
    elements.portsBody.append(row);
  }
}

function renderSignals() {
  elements.signalsBody.replaceChildren();
  const signals = [...observations.values()].sort((a, b) => {
    return (a.label || a.portName).localeCompare(b.label || b.portName) || a.signalKey.localeCompare(b.signalKey);
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
    const row = document.createElement("tr");
    appendCells(row, [
      signal.label || "-",
      signal.portName,
      describeSignal(signal),
      `${signal.lastMessageType} / ${signal.lastValue ?? "-"}`,
      range,
      `${signal.count}${signal.possibleMirrorCount ? ` (${signal.possibleMirrorCount} mirror flags)` : ""}`
    ]);
    elements.signalsBody.append(row);
  }
}

function renderManualObservations() {
  elements.manualList.replaceChildren();
  if (manualObservations.length === 0) {
    appendListItem(elements.manualList, "None recorded.", "empty");
    return;
  }

  for (const item of manualObservations) {
    appendListItem(elements.manualList, `${item.label}: no MIDI observed`);
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
      `${event.portName} | ${event.messageType} | ${event.signalKey} | value ${event.value ?? "-"} | [${event.bytes.join(" ")}]`
    );
  }
}

function describeSignal(signal) {
  if (signal.category === "note") {
    return `${signal.noteName || "Note"} (${signal.number}), channel ${signal.channel}`;
  }
  if (signal.category === "control-change") {
    return `CC ${signal.number}, channel ${signal.channel}`;
  }
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

render();
