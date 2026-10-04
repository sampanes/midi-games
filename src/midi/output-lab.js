import { sendSafeNoteProbe } from "./output-probe.js";

// Generic starting point: 16 chromatic notes from 36, a common drum-pad
// layout. Edit it in the page to the notes your pads actually send.
export const DEFAULT_PAD_NOTES = Array.from({ length: 16 }, (_, index) => 36 + index);

export const OUTPUT_LAB_KIND = "output-lab";
export const OUTPUT_LAB_SCHEMA_VERSION = 1;
const MAX_LOG_ENTRIES = 5000;

export function programChangeBytes(channel, program) {
  if (!Number.isInteger(channel) || channel < 1 || channel > 16) throw new RangeError("channel must be 1 through 16");
  if (!Number.isInteger(program) || program < 0 || program > 127) throw new RangeError("program must be 0 through 127");
  return [0xc0 | (channel - 1), program];
}

// Program Change has no note to release, so no cleanup is sent.
export async function sendProgramChange({ output, channel, program }) {
  const bytes = programChangeBytes(channel, program);
  const result = { bytes, sent: false, sendError: null };
  try {
    await output.open();
    output.send(bytes);
    result.sent = true;
  } catch (error) {
    result.sendError = String(error?.message || error || "unknown error");
  }
  return result;
}

export function parsePadNotes(text) {
  const notes = String(text ?? "")
    .split(/[\s,]+/)
    .filter(Boolean)
    .map(Number);
  if (notes.length === 0 || notes.length > 32) throw new RangeError("enter 1 to 32 notes");
  for (const note of notes) {
    if (!Number.isInteger(note) || note < 0 || note > 127) throw new RangeError(`invalid note: ${note}`);
  }
  return notes;
}

// Plays each note in turn through the safe probe (velocity capped at 32,
// every note followed by Note Off, All Notes Off, All Sound Off).
export async function runPadSweep({
  output,
  channel,
  notes,
  velocity,
  holdMs = 400,
  gapMs = 250,
  wait = (ms) => new Promise((resolve) => globalThis.setTimeout(resolve, ms)),
  onStep = () => {},
  shouldStop = () => false
}) {
  const steps = [];
  for (let index = 0; index < notes.length; index += 1) {
    if (shouldStop()) break;
    const note = notes[index];
    onStep({ index, note });
    const result = await sendSafeNoteProbe({ output, channel, note, velocity, noteLengthMs: holdMs, wait });
    steps.push({ index, note, ...result });
    if (result.sendError || !result.cleanupComplete) break;
    await wait(gapMs);
  }
  return { completed: steps.length === notes.length, steps };
}

export function validateOutputLabLog(log) {
  if (!log || typeof log !== "object" || Array.isArray(log)) return "Log must be a JSON object";
  if (log.kind !== OUTPUT_LAB_KIND) return "Log kind must be output-lab";
  if (log.schemaVersion !== OUTPUT_LAB_SCHEMA_VERSION) return "Unsupported output-lab schemaVersion";
  for (const field of ["actions", "incoming"]) {
    if (!Array.isArray(log[field])) return `${field} must be an array`;
    if (log[field].length > MAX_LOG_ENTRIES) return `${field} has too many entries`;
  }
  return null;
}
