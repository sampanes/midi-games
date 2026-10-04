// Pure logic for the "Color Keys" game. No DOM or Web MIDI here so it can be
// unit tested in Node.
//
// The game deliberately ignores MIDI channel and note range per control: a
// keyboard's controller preset can move keys and pads to any channel, and the
// octave buttons shift key notes. Only the pitch class (C, D, E, ...) matters,
// so every key and pad does something no matter how the keyboard is set up.

// One color per pitch class, rainbow order on the white keys (C red .. B pink).
// Black keys get in-between shades.
export const PITCH_CLASSES = [
  { name: "C", color: "#ff3b3b", colorName: "RED", white: true },
  { name: "C#", color: "#ff6a2b", colorName: "RED-ORANGE", white: false },
  { name: "D", color: "#ff9a1f", colorName: "ORANGE", white: true },
  { name: "D#", color: "#ffc61f", colorName: "GOLD", white: false },
  { name: "E", color: "#ffe81f", colorName: "YELLOW", white: true },
  { name: "F", color: "#3ddc4a", colorName: "GREEN", white: true },
  { name: "F#", color: "#22c9a0", colorName: "TEAL", white: false },
  { name: "G", color: "#2fa8ff", colorName: "BLUE", white: true },
  { name: "G#", color: "#4a6bff", colorName: "INDIGO", white: false },
  { name: "A", color: "#8a4dff", colorName: "PURPLE", white: true },
  { name: "A#", color: "#c04dff", colorName: "VIOLET", white: false },
  { name: "B", color: "#ff5ec8", colorName: "PINK", white: true }
];

export const WHITE_PITCH_CLASSES = PITCH_CLASSES
  .map((entry, index) => (entry.white ? index : null))
  .filter((index) => index !== null);

// Notes outside this window are ignored. Very low notes are used by some
// keyboards for transport buttons, very high ones for DAW knob-touch messages.
export const MIN_GAME_NOTE = 12;
export const MAX_GAME_NOTE = 103;

export const STARS_PER_ROUND = 8;

export function pitchClass(note) {
  return ((note % 12) + 12) % 12;
}

// Turn raw MIDI bytes into a game event, or null if the game does not care.
// Returns { type: "on" | "off", note, velocity, channel }.
export function noteEventFromBytes(data) {
  const bytes = Array.from(data ?? [], (value) => Number(value) & 0xff);
  if (bytes.length < 3) return null;
  const kind = bytes[0] & 0xf0;
  const channel = (bytes[0] & 0x0f) + 1;
  const note = bytes[1];
  const velocity = bytes[2];
  if (kind !== 0x90 && kind !== 0x80) return null;
  if (note < MIN_GAME_NOTE || note > MAX_GAME_NOTE) return null;
  const type = kind === 0x90 && velocity > 0 ? "on" : "off";
  return { type, note, velocity, channel };
}

// A keyboard plugged in by USB AND paired over Bluetooth sends every message on
// several ports at once. This drops a message if the exact same bytes arrived
// from a different port within windowMs. Repeats from the same port pass.
export function createMirrorFilter(windowMs = 60) {
  const lastSeen = new Map();
  return function accept(portId, data, atMs) {
    const key = Array.from(data ?? []).join(",");
    const previous = lastSeen.get(key);
    lastSeen.set(key, { portId, atMs });
    if (lastSeen.size > 512) {
      for (const [oldKey, value] of lastSeen) {
        if (atMs - value.atMs > windowMs) lastSeen.delete(oldKey);
      }
    }
    if (!previous) return true;
    return previous.portId === portId || atMs - previous.atMs > windowMs;
  };
}

// Next target pitch class: a white key, never the same as the last one.
export function pickNextTarget(previous, random = Math.random) {
  const choices = WHITE_PITCH_CLASSES.filter((index) => index !== previous);
  return choices[Math.floor(random() * choices.length) % choices.length];
}

// Game state machine. Returns a new state and a list of effects for the page
// to render/play, so the rules stay free of DOM and audio code.
export function createGame(random = Math.random) {
  return { target: pickNextTarget(null, random), stars: 0, rounds: 0, locked: false };
}

export function pressNote(state, note) {
  const pressed = pitchClass(note);
  if (state.locked || pressed !== state.target) {
    return { state, effects: [{ type: state.locked ? "play" : "miss", note }] };
  }
  const stars = state.stars + 1;
  if (stars >= STARS_PER_ROUND) {
    return {
      state: { ...state, stars, locked: true },
      effects: [{ type: "hit", note }, { type: "win" }]
    };
  }
  return {
    state: { ...state, stars, locked: true },
    effects: [{ type: "hit", note }, { type: "next-soon" }]
  };
}

export function advance(state, random = Math.random) {
  if (state.stars >= STARS_PER_ROUND) {
    return { target: pickNextTarget(state.target, random), stars: 0, rounds: state.rounds + 1, locked: false };
  }
  return { ...state, target: pickNextTarget(state.target, random), locked: false };
}

export function noteToFrequency(note) {
  return 440 * 2 ** ((note - 69) / 12);
}
