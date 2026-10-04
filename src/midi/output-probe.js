const DEFAULT_NOTE_LENGTH_MS = 300;

export async function sendSafeNoteProbe({
  output,
  channel,
  note,
  velocity,
  noteLengthMs = DEFAULT_NOTE_LENGTH_MS,
  wait = defaultWait,
  onNoteOn = () => {},
  onCleanup = () => {}
}) {
  validateProbeArguments(output, channel, note, velocity, noteLengthMs);
  const result = {
    noteOnSent: false,
    noteOffSent: false,
    allNotesOffSent: false,
    allSoundOffSent: false,
    messagesSent: 0,
    sendError: null,
    cleanupError: null,
    cleanupComplete: false
  };

  try {
    await output.open();
    output.send([0x90 | (channel - 1), note, velocity]);
    result.noteOnSent = true;
    result.messagesSent += 1;
    onNoteOn();
    await wait(noteLengthMs);
  } catch (error) {
    result.sendError = errorMessage(error);
  } finally {
    const cleanupErrors = [];
    sendAndRecord(
      output,
      [0x80 | (channel - 1), note, 0],
      () => { result.noteOffSent = true; },
      result,
      cleanupErrors,
      "Note Off"
    );
    sendAndRecord(
      output,
      [0xb0 | (channel - 1), 123, 0],
      () => { result.allNotesOffSent = true; },
      result,
      cleanupErrors,
      "All Notes Off"
    );
    sendAndRecord(
      output,
      [0xb0 | (channel - 1), 120, 0],
      () => { result.allSoundOffSent = true; },
      result,
      cleanupErrors,
      "All Sound Off"
    );
    result.cleanupError = cleanupErrors.length ? cleanupErrors.join("; ") : null;
    result.cleanupComplete = result.noteOffSent && result.allNotesOffSent && result.allSoundOffSent;
    onCleanup(result);
  }

  return result;
}

export function panicMidiOutput(output, activeNotes = []) {
  const result = {
    clearCalled: false,
    noteOffsSent: 0,
    allNotesOffSent: 0,
    allSoundOffSent: 0,
    messagesSent: 0,
    errors: []
  };

  try {
    output.clear();
    result.clearCalled = true;
  } catch (error) {
    result.errors.push(`clear: ${errorMessage(error)}`);
  }

  for (const active of activeNotes) {
    try {
      output.send([0x80 | (active.channel - 1), active.note, 0]);
      result.noteOffsSent += 1;
      result.messagesSent += 1;
    } catch (error) {
      result.errors.push(`note ${active.note} off: ${errorMessage(error)}`);
    }
  }

  for (let channel = 1; channel <= 16; channel += 1) {
    try {
      output.send([0xb0 | (channel - 1), 123, 0]);
      result.allNotesOffSent += 1;
      result.messagesSent += 1;
    } catch (error) {
      result.errors.push(`channel ${channel} All Notes Off: ${errorMessage(error)}`);
    }
    try {
      output.send([0xb0 | (channel - 1), 120, 0]);
      result.allSoundOffSent += 1;
      result.messagesSent += 1;
    } catch (error) {
      result.errors.push(`channel ${channel} All Sound Off: ${errorMessage(error)}`);
    }
  }
  return result;
}

function sendAndRecord(output, bytes, markSent, result, errors, label) {
  try {
    output.send(bytes);
    markSent();
    result.messagesSent += 1;
  } catch (error) {
    errors.push(`${label}: ${errorMessage(error)}`);
  }
}

function validateProbeArguments(output, channel, note, velocity, noteLengthMs) {
  if (!output || typeof output.open !== "function" || typeof output.send !== "function") {
    throw new TypeError("A MIDI output with open() and send() is required");
  }
  if (!Number.isInteger(channel) || channel < 1 || channel > 16) throw new RangeError("channel must be 1 through 16");
  if (!Number.isInteger(note) || note < 0 || note > 127) throw new RangeError("note must be 0 through 127");
  if (!Number.isInteger(velocity) || velocity < 1 || velocity > 32) throw new RangeError("safe-probe velocity must be 1 through 32");
  if (!Number.isFinite(noteLengthMs) || noteLengthMs < 1 || noteLengthMs > 2000) throw new RangeError("noteLengthMs must be 1 through 2000");
}

function defaultWait(milliseconds) {
  return new Promise((resolve) => globalThis.setTimeout(resolve, milliseconds));
}

function errorMessage(error) {
  return String(error?.message || error || "unknown error");
}
