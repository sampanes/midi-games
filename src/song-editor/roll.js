// Pure rules for the song editor. No DOM here so it can be unit tested in Node.
//
// A song is every note of a MIDI file: notes[i] = [startMs, endMs, note, part].
// The tune is the file notes the user keeps (a Set of indices) plus notes
// they added by hand ({s, e, n}). The tune is one line a child plays: one note
// per moment, so keeping or adding a note drops whatever else the tune had at
// that moment (that is how a note is picked out of a chord).

// Notes starting this close together count as the same moment.
export const SAME_MOMENT_MS = 40;

// A note added near a lyric syllable starts on it (sung parts follow lyrics).
export const LYRIC_SNAP_MS = 350;

// Length of an added note when nothing in the song says how long it is.
export const DEFAULT_ADDED_MS = 500;
export const MIN_ADDED_MS = 80;

// Sorted, unique values.
export function uniqueSorted(values) {
  return [...new Set(values)].sort((a, b) => a - b);
}

// Index of the first value >= t in a sorted array.
export function lowerBound(sorted, t) {
  let lo = 0;
  let hi = sorted.length;
  while (lo < hi) {
    const mid = (lo + hi) >> 1;
    if (sorted[mid] < t) lo = mid + 1;
    else hi = mid;
  }
  return lo;
}

export function nearest(sorted, t) {
  if (sorted.length === 0) return null;
  const i = lowerBound(sorted, t);
  if (i === 0) return sorted[0];
  if (i === sorted.length) return sorted[i - 1];
  return t - sorted[i - 1] <= sorted[i] - t ? sorted[i - 1] : sorted[i];
}

// First value after t (strictly later), or null.
export function nextAfter(sorted, t) {
  const i = lowerBound(sorted, t + 1);
  return i < sorted.length ? sorted[i] : null;
}

// Start times notes may snap to: the song's own note starts in the parts
// shown (hidden parts, like drums, are left out so a hi-hat does not count).
export function onsetTimes(notes, hidden = new Set()) {
  return uniqueSorted(notes.filter((n) => !hidden.has(n[3])).map((n) => n[0]));
}

// Where a note placed at t starts: on a lyric syllable if one is close,
// otherwise on the nearest note start, otherwise at t itself.
export function snapStart(t, onsets, lyrics) {
  const syllable = nearest(lyrics, t);
  if (syllable !== null && Math.abs(syllable - t) <= LYRIC_SNAP_MS) return syllable;
  const onset = nearest(onsets, t);
  return onset === null ? Math.round(t) : onset;
}

// The tune, in time order: [{s, e, n, i}] with i the file note index, or
// null for an added note (then a is its index in added).
export function tuneNotes(notes, kept, added) {
  const tune = [];
  for (const i of kept) {
    const [s, e, n] = notes[i];
    tune.push({ s, e, n, i, a: null });
  }
  added.forEach((note, a) => tune.push({ s: note.s, e: note.e, n: note.n, i: null, a }));
  return tune.sort((x, y) => x.s - y.s || y.n - x.n);
}

function sameMoment(a, b) {
  return Math.abs(a - b) <= SAME_MOMENT_MS;
}

// The tune without anything at time t.
function clearMoment(notes, state, t) {
  return {
    kept: new Set([...state.kept].filter((i) => !sameMoment(notes[i][0], t))),
    added: state.added.filter((note) => !sameMoment(note.s, t)),
  };
}

export function keepNote(notes, state, i) {
  const cleared = clearMoment(notes, state, notes[i][0]);
  cleared.kept.add(i);
  return cleared;
}

export function dropNote(state, i) {
  const kept = new Set(state.kept);
  kept.delete(i);
  return { kept, added: state.added };
}

export function removeAdded(state, a) {
  return { kept: state.kept, added: state.added.filter((_, index) => index !== a) };
}

// Tap on a file note: keep it, or drop it if it is already in the tune.
export function toggleNote(notes, state, i) {
  return state.kept.has(i) ? dropNote(state, i) : keepNote(notes, state, i);
}

// Add [pitch] near time t. The start snaps to a lyric syllable or a note
// start. If the song has that very note there, it is kept instead (a real
// note beats a made-up one). An added note lasts until the next tune note or
// syllable, and no longer than the longest note starting with it (the chord
// it sits on). Parts in [hidden] (drums) are not looked at. Returns
// {state, start, end}.
export function addNote(notes, state, pitch, t, { onsets, lyrics, hidden = new Set() }) {
  const start = snapStart(t, onsets, lyrics);
  const shown = (n) => !hidden.has(n[3]) && sameMoment(n[0], start);
  const real = notes.findIndex((n) => n[2] === pitch && shown(n));
  if (real >= 0) {
    return { state: keepNote(notes, state, real), start: notes[real][0], end: notes[real][1] };
  }
  const cleared = clearMoment(notes, state, start);
  let end = start + DEFAULT_ADDED_MS;
  const under = notes.filter(shown);
  if (under.length > 0) end = Math.max(...under.map((n) => n[1]));
  const tuneStarts = uniqueSorted(tuneNotes(notes, cleared.kept, cleared.added).map((n) => n.s));
  for (const next of [nextAfter(tuneStarts, start), nextAfter(lyrics, start)]) {
    if (next !== null) end = Math.min(end, next);
  }
  end = Math.max(end, start + MIN_ADDED_MS);
  const added = [...cleared.added, { s: start, e: end, n: pitch }];
  return { state: { kept: cleared.kept, added }, start, end };
}

// Where the cursor goes after a note is entered at [start] while stopped, so
// the next key press lands on the next syllable (or note start).
export function nextStep(start, onsets, lyrics) {
  const source = lyrics.length > 0 ? lyrics : onsets;
  const next = nextAfter(source, start + SAME_MOMENT_MS);
  return next === null ? start : next;
}

// Keep a whole part: its highest note at each moment.
export function keepPart(notes, state, part) {
  const indices = notes
    .map((n, i) => i)
    .filter((i) => notes[i][3] === part)
    .sort((a, b) => notes[a][0] - notes[b][0] || notes[b][2] - notes[a][2]);
  let next = state;
  let last = null;
  for (const i of indices) {
    if (last !== null && sameMoment(notes[i][0], last)) continue;
    next = keepNote(notes, next, i);
    last = notes[i][0];
  }
  return next;
}

export function dropPart(notes, state, part) {
  return { kept: new Set([...state.kept].filter((i) => notes[i][3] !== part)), added: state.added };
}
