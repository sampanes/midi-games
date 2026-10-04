const NOTE_NAMES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"];

export function midiNoteName(noteNumber) {
  if (!Number.isInteger(noteNumber) || noteNumber < 0 || noteNumber > 127) {
    return null;
  }

  const octave = Math.floor(noteNumber / 12) - 1;
  return `${NOTE_NAMES[noteNumber % 12]}${octave}`;
}

// The value that should feed a signal's observed min/max range. Note releases
// carry a release velocity (often a fixed 64) that would otherwise pollute the
// press-velocity range, so they are excluded.
export function rangeValue(parsed) {
  if (!parsed || parsed.phase === "release") {
    return null;
  }
  return Number.isFinite(parsed.value) ? parsed.value : null;
}

export function parseMidiMessage(data, timestamp = 0) {
  const bytes = Array.from(data ?? [], (value) => Number(value) & 0xff);
  if (bytes.length === 0) {
    return null;
  }

  const status = bytes[0];
  if (status < 0x80) {
    return {
      category: "invalid",
      messageType: "invalid",
      phase: "event",
      signalKey: `invalid:${status}`,
      value: status,
      bytes,
      timestamp
    };
  }

  if (status >= 0xf0) {
    return {
      category: "system",
      messageType: systemMessageName(status),
      phase: "event",
      signalKey: `system:${status.toString(16).padStart(2, "0")}`,
      value: bytes[1] ?? null,
      bytes,
      timestamp
    };
  }

  const family = status & 0xf0;
  const channel = (status & 0x0f) + 1;
  const expectedLength = family === 0xc0 || family === 0xd0 ? 2 : 3;
  if (bytes.length < expectedLength) {
    return {
      category: "invalid",
      messageType: "invalid-length",
      phase: "event",
      channel,
      signalKey: `invalid-length:${status.toString(16)}`,
      value: null,
      expectedLength,
      bytes,
      timestamp
    };
  }
  const data1 = bytes[1] ?? 0;
  const data2 = bytes[2] ?? 0;

  switch (family) {
    case 0x80:
      return noteEvent("note-off", "release", channel, data1, data2, bytes, timestamp);
    case 0x90:
      return data2 === 0
        ? noteEvent("note-off", "release", channel, data1, data2, bytes, timestamp)
        : noteEvent("note-on", "press", channel, data1, data2, bytes, timestamp);
    case 0xa0:
      return {
        category: "poly-aftertouch",
        messageType: "poly-aftertouch",
        phase: "change",
        channel,
        number: data1,
        noteName: midiNoteName(data1),
        value: data2,
        signalKey: `poly-aftertouch:${channel}:${data1}`,
        bytes,
        timestamp
      };
    case 0xb0:
      return {
        category: "control-change",
        messageType: "control-change",
        phase: "change",
        channel,
        number: data1,
        value: data2,
        signalKey: `cc:${channel}:${data1}`,
        bytes,
        timestamp
      };
    case 0xc0:
      return {
        category: "program-change",
        messageType: "program-change",
        phase: "change",
        channel,
        number: data1,
        value: data1,
        signalKey: `program:${channel}`,
        bytes,
        timestamp
      };
    case 0xd0:
      return {
        category: "channel-pressure",
        messageType: "channel-pressure",
        phase: "change",
        channel,
        value: data1,
        signalKey: `channel-pressure:${channel}`,
        bytes,
        timestamp
      };
    case 0xe0: {
      const rawValue = (data2 << 7) | data1;
      return {
        category: "pitch-bend",
        messageType: "pitch-bend",
        phase: "change",
        channel,
        value: rawValue - 8192,
        rawValue,
        signalKey: `pitch-bend:${channel}`,
        bytes,
        timestamp
      };
    }
    default:
      return {
        category: "unknown",
        messageType: "unknown",
        phase: "event",
        channel,
        signalKey: `unknown:${status.toString(16)}`,
        value: data1,
        bytes,
        timestamp
      };
  }
}

function noteEvent(messageType, phase, channel, noteNumber, velocity, bytes, timestamp) {
  return {
    category: "note",
    messageType,
    phase,
    channel,
    number: noteNumber,
    noteName: midiNoteName(noteNumber),
    velocity,
    value: velocity,
    signalKey: `note:${channel}:${noteNumber}`,
    bytes,
    timestamp
  };
}

function systemMessageName(status) {
  const names = {
    0xf0: "system-exclusive",
    0xf1: "time-code-quarter-frame",
    0xf2: "song-position",
    0xf3: "song-select",
    0xf6: "tune-request",
    0xf8: "timing-clock",
    0xfa: "start",
    0xfb: "continue",
    0xfc: "stop",
    0xfe: "active-sensing",
    0xff: "system-reset"
  };

  return names[status] ?? `system-${status.toString(16)}`;
}
