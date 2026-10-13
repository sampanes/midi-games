// Song editor page: a piano roll of every note in a MIDI file. The notes the
// user keeps (and the ones they add) become the song's canon tune for the
// Key Games song mode. Rules live in roll.js; this file draws and listens.

import { PITCH_CLASSES, pitchClass } from "../games/color-keys.js";
import {
  addNote,
  dropNote,
  dropPart,
  keepNote,
  keepPart,
  lowerBound,
  nextStep,
  onsetTimes,
  removeAdded,
  toggleNote,
  tuneNotes,
  uniqueSorted
} from "./roll.js";

const GUTTER = 34;
const RULER = 34;
const MIN_ROW = 13;
const MAX_ROW = 22;
const TAP_SLOP = 14;
const BRUSH_SLOP = 6;
const ZOOMS = [0.02, 0.03, 0.045, 0.065, 0.09, 0.12, 0.17, 0.24, 0.34, 0.48];
const PLAY_AHEAD_MS = 150;
const REACTION_MS = 60;
const LAST_SONG_KEY = "song-editor:last";

const HINTS = {
  tap: "Tap a note to keep or drop it. Tap empty space or the top strip to move the start point.",
  keep: "Drag over notes to keep them (one per moment). Switch to Tap to scroll.",
  drop: "Drag over notes to drop them. Switch to Tap to scroll.",
  add: "Tap a spot or press keys: notes land on the song's own beats and syllables."
};

const $ = (id) => document.getElementById(id);
const canvas = $("roll");
const ctx = canvas.getContext("2d");
const scroller = $("scroller");
const spacer = $("spacer");

const app = {
  songs: [],
  song: null,
  notes: [],
  order: [],
  starts: [],
  maxLen: 0,
  lyrics: [],
  lyricText: [],
  onsets: [],
  hidden: new Set(),
  tune: { kept: new Set(), added: [] },
  undo: [],
  dirty: false,
  mode: "tap",
  listen: "tune",
  zoomIndex: 5,
  rowH: 14,
  low: 48,
  high: 84,
  duration: 1000,
  cursor: 0,
  playing: null,
  octave: 4,
  view: { w: 0, h: 0, dpr: 1 }
};

// ---------- sound ----------

let audio = null;

function ensureAudio() {
  if (audio) {
    if (audio.ctx.state === "suspended") audio.ctx.resume();
    return audio;
  }
  const ac = new (window.AudioContext || window.webkitAudioContext)();
  const comp = ac.createDynamicsCompressor();
  const master = ac.createGain();
  master.gain.value = 0.3;
  master.connect(comp);
  comp.connect(ac.destination);
  audio = { ctx: ac, master, voices: new Set() };
  return audio;
}

function frequency(note) {
  return 440 * 2 ** ((note - 69) / 12);
}

// One note. With dur null it holds until the returned release is called.
function voice(note, when, dur, level) {
  const { ctx: ac, master, voices } = ensureAudio();
  const osc = ac.createOscillator();
  const gain = ac.createGain();
  osc.type = "triangle";
  osc.frequency.value = frequency(note);
  gain.gain.setValueAtTime(0, when);
  gain.gain.linearRampToValueAtTime(level, when + 0.012);
  gain.gain.setTargetAtTime(level * 0.55, when + 0.012, 0.18);
  osc.connect(gain);
  gain.connect(master);
  osc.start(when);
  const item = { osc, gain };
  voices.add(item);
  osc.onended = () => voices.delete(item);
  const release = (at = ac.currentTime) => {
    gain.gain.cancelScheduledValues(at);
    gain.gain.setTargetAtTime(0, at, 0.04);
    osc.stop(at + 0.3);
  };
  if (dur !== null) release(when + Math.max(dur, 0.08));
  return release;
}

function blip(note, ms = 260) {
  const { ctx: ac } = ensureAudio();
  voice(note, ac.currentTime, ms / 1000, 0.9);
}

function silence() {
  if (!audio) return;
  for (const { osc, gain } of audio.voices) {
    const now = audio.ctx.currentTime;
    gain.gain.cancelScheduledValues(now);
    gain.gain.setTargetAtTime(0, now, 0.02);
    try { osc.stop(now + 0.1); } catch { /* already stopped */ }
  }
}

// ---------- tune edits ----------

function setTune(next) {
  app.undo.push(app.tune);
  if (app.undo.length > 300) app.undo.shift();
  app.tune = next;
  app.dirty = true;
  updateChrome();
  render();
}

function undo() {
  const last = app.undo.pop();
  if (!last) return;
  app.tune = last;
  app.dirty = true;
  updateChrome();
  render();
}

function addContext() {
  return { onsets: app.onsets, lyrics: app.lyrics, hidden: app.hidden };
}

function tuneList() {
  return tuneNotes(app.notes, app.tune.kept, app.tune.added);
}

// ---------- geometry ----------

const zoom = () => ZOOMS[app.zoomIndex];
const xOf = (t) => GUTTER + t * zoom() - scroller.scrollLeft;
const yOf = (n) => RULER + (app.high - n) * app.rowH - scroller.scrollTop;
const timeAt = (x) => (x - GUTTER + scroller.scrollLeft) / zoom();
const noteAtY = (y) => app.high - Math.floor((y - RULER + scroller.scrollTop) / app.rowH);

function contentSize() {
  return {
    w: GUTTER + app.duration * zoom() + 160,
    h: RULER + (app.high - app.low + 1) * app.rowH
  };
}

function resize() {
  const rect = $("rollWrap").getBoundingClientRect();
  const dpr = window.devicePixelRatio || 1;
  app.view = { w: rect.width, h: rect.height, dpr };
  canvas.width = Math.round(rect.width * dpr);
  canvas.height = Math.round(rect.height * dpr);
  const rows = app.high - app.low + 1;
  app.rowH = Math.max(MIN_ROW, Math.min(MAX_ROW, Math.floor((rect.height - RULER) / rows)));
  const size = contentSize();
  spacer.style.width = `${size.w}px`;
  spacer.style.height = `${size.h}px`;
  render();
}

function setZoom(index) {
  const next = Math.max(0, Math.min(ZOOMS.length - 1, index));
  if (next === app.zoomIndex) return;
  const center = timeAt(app.view.w / 2);
  app.zoomIndex = next;
  const size = contentSize();
  spacer.style.width = `${size.w}px`;
  scroller.scrollLeft = Math.max(0, center * zoom() + GUTTER - app.view.w / 2);
  render();
}

function scrollToTime(t, at = 0.3) {
  scroller.scrollLeft = Math.max(0, GUTTER + t * zoom() - app.view.w * at);
}

// ---------- drawing ----------

let frameQueued = false;

function render() {
  if (frameQueued) return;
  frameQueued = true;
  requestAnimationFrame(() => {
    frameQueued = false;
    draw();
  });
}

function noteRect(s, e, n) {
  const x = xOf(s);
  const w = Math.max(3, (e - s) * zoom() - 1);
  return { x, y: yOf(n) + 1, w, h: app.rowH - 2 };
}

function draw() {
  const { w, h, dpr } = app.view;
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  ctx.fillStyle = "#14111c";
  ctx.fillRect(0, 0, w, h);
  if (!app.song) return;

  // Rows: black keys darker, a line under every C.
  for (let n = app.low; n <= app.high; n++) {
    const y = yOf(n);
    if (y + app.rowH < RULER || y > h) continue;
    ctx.fillStyle = PITCH_CLASSES[pitchClass(n)].white ? "#211c2b" : "#19151f";
    ctx.fillRect(GUTTER, y, w - GUTTER, app.rowH);
    if (pitchClass(n) === 0) {
      ctx.fillStyle = "#3a3248";
      ctx.fillRect(GUTTER, y + app.rowH - 1, w - GUTTER, 1);
    }
  }

  // Second lines.
  const t0 = Math.max(0, timeAt(GUTTER));
  const t1 = timeAt(w);
  const step = zoom() < 0.04 ? 5000 : 1000;
  ctx.fillStyle = "#2b2438";
  for (let t = Math.ceil(t0 / step) * step; t <= t1; t += step) {
    ctx.fillRect(Math.round(xOf(t)), RULER, 1, h - RULER);
  }

  // Background notes (shown parts, not in the tune), then the tune on top.
  const kept = app.tune.kept;
  const from = lowerBound(app.starts, t0 - app.maxLen);
  for (let k = from; k < app.order.length; k++) {
    const i = app.order[k];
    const [s, e, n, part] = app.notes[i];
    if (s > t1) break;
    if (kept.has(i) || app.hidden.has(part) || e < t0) continue;
    const r = noteRect(s, e, n);
    if (r.y + r.h < RULER || r.y > h) continue;
    ctx.fillStyle = "rgba(150, 138, 176, 0.42)";
    ctx.fillRect(r.x, r.y, r.w, r.h);
  }
  for (const note of tuneList()) {
    if (note.e < t0 || note.s > t1) continue;
    const r = noteRect(note.s, note.e, note.n);
    if (r.y + r.h < RULER || r.y > h) continue;
    ctx.fillStyle = PITCH_CLASSES[pitchClass(note.n)].color;
    ctx.fillRect(r.x, r.y, r.w, r.h);
    ctx.strokeStyle = note.i === null ? "#ffffff" : "rgba(0, 0, 0, 0.55)";
    ctx.lineWidth = note.i === null ? 2 : 1;
    ctx.strokeRect(r.x + 0.5, r.y + 0.5, r.w - 1, r.h - 1);
  }

  // Start point, and the playhead while playing.
  const playAt = app.playing ? songNow() : null;
  drawLine(app.cursor, "#ffffff", 1.5);
  if (playAt !== null) drawLine(playAt, "#ffc61f", 2);

  // Ruler: seconds and lyric syllables.
  ctx.fillStyle = "#1f1a2a";
  ctx.fillRect(0, 0, w, RULER);
  ctx.fillStyle = "#3a3248";
  ctx.fillRect(0, RULER - 1, w, 1);
  ctx.font = "10px system-ui, sans-serif";
  ctx.textBaseline = "top";
  ctx.fillStyle = "#a49cb4";
  const labelStep = zoom() < 0.04 ? 10000 : 5000;
  for (let t = Math.ceil(t0 / labelStep) * labelStep; t <= t1; t += labelStep) {
    const sec = Math.round(t / 1000);
    ctx.fillText(`${Math.floor(sec / 60)}:${String(sec % 60).padStart(2, "0")}`, xOf(t) + 2, 2);
  }
  ctx.font = "11px system-ui, sans-serif";
  let lastRight = -Infinity;
  for (const [t, text] of app.lyricText) {
    if (t < t0 - 2000 || t > t1) continue;
    const x = xOf(t);
    ctx.fillStyle = "#6c5f86";
    ctx.fillRect(x, RULER - 7, 1, 6);
    const width = ctx.measureText(text).width;
    if (x > lastRight + 3) {
      ctx.fillStyle = "#e6dcf5";
      ctx.fillText(text, x + 1, 15);
      lastRight = x + width;
    }
  }
  drawCursorMark(app.cursor, "#ffffff");
  if (playAt !== null) drawCursorMark(playAt, "#ffc61f");

  // Gutter: note names.
  ctx.fillStyle = "#1f1a2a";
  ctx.fillRect(0, RULER, GUTTER, h - RULER);
  ctx.fillRect(0, 0, GUTTER, RULER);
  ctx.font = "10px system-ui, sans-serif";
  ctx.textBaseline = "middle";
  for (let n = app.low; n <= app.high; n++) {
    const y = yOf(n);
    if (y + app.rowH < RULER || y > h) continue;
    const pc = pitchClass(n);
    if (pc !== 0 && app.rowH < 15) continue;
    if (!PITCH_CLASSES[pc].white) continue;
    ctx.fillStyle = pc === 0 ? "#f1edf7" : "#7d7490";
    ctx.fillText(`${PITCH_CLASSES[pc].name}${pc === 0 ? Math.floor(n / 12) - 1 : ""}`, 4, y + app.rowH / 2);
  }
}

function drawLine(t, color, width) {
  const x = xOf(t);
  if (x < GUTTER || x > app.view.w) return;
  ctx.fillStyle = color;
  ctx.fillRect(x - width / 2, RULER, width, app.view.h - RULER);
}

function drawCursorMark(t, color) {
  const x = xOf(t);
  if (x < GUTTER || x > app.view.w) return;
  ctx.fillStyle = color;
  ctx.beginPath();
  ctx.moveTo(x - 6, RULER - 9);
  ctx.lineTo(x + 6, RULER - 9);
  ctx.lineTo(x, RULER - 1);
  ctx.fill();
}

// ---------- hit testing ----------

// The note nearest to a point (canvas coordinates), within slop pixels:
// {i} for a file note, {a} for an added note, or null.
function noteAt(px, py, slop) {
  const t = timeAt(px);
  const pad = slop / zoom();
  let best = null;
  let bestD = slop + 0.001;
  const consider = (s, e, n, hit) => {
    const r = noteRect(s, e, n);
    const dx = Math.max(r.x - px, 0, px - (r.x + r.w));
    const dy = Math.max(r.y - py, 0, py - (r.y + r.h));
    const d = Math.hypot(dx, dy);
    if (d < bestD) {
      bestD = d;
      best = hit;
    }
  };
  const from = lowerBound(app.starts, t - pad - app.maxLen);
  for (let k = from; k < app.order.length; k++) {
    const i = app.order[k];
    const [s, e, n, part] = app.notes[i];
    if (s > t + pad) break;
    if (app.hidden.has(part) && !app.tune.kept.has(i)) continue;
    consider(s, e, n, { i });
  }
  app.tune.added.forEach((note, a) => consider(note.s, note.e, note.n, { a }));
  return best;
}

// ---------- touches on the roll ----------

let press = null;

function local(event) {
  const rect = scroller.getBoundingClientRect();
  return { x: event.clientX - rect.left, y: event.clientY - rect.top };
}

function onRollDown(event) {
  if (!app.song) return;
  const p = local(event);
  press = { id: event.pointerId, x: p.x, y: p.y, time: performance.now(), moved: false, last: p };
  if ((app.mode === "keep" || app.mode === "drop") && p.y > RULER) {
    scroller.setPointerCapture(event.pointerId);
    press.brush = true;
    press.changed = false;
    press.before = app.tune;
    brushAt(p);
  }
}

function onRollMove(event) {
  if (!press || press.id !== event.pointerId) return;
  const p = local(event);
  if (Math.hypot(p.x - press.x, p.y - press.y) > 10) press.moved = true;
  if (!press.brush) return;
  // Fill in between move events so a fast drag does not skip notes.
  const steps = Math.max(1, Math.ceil(Math.hypot(p.x - press.last.x, p.y - press.last.y) / 5));
  for (let k = 1; k <= steps; k++) {
    brushAt({
      x: press.last.x + ((p.x - press.last.x) * k) / steps,
      y: press.last.y + ((p.y - press.last.y) * k) / steps
    });
  }
  press.last = p;
}

function brushAt(p) {
  const hit = noteAt(p.x, p.y, BRUSH_SLOP);
  if (!hit) return;
  let next = app.tune;
  if (app.mode === "keep" && hit.i !== undefined && !next.kept.has(hit.i)) {
    next = keepNote(app.notes, next, hit.i);
    blip(app.notes[hit.i][2], 120);
  } else if (app.mode === "drop") {
    if (hit.i !== undefined && next.kept.has(hit.i)) next = dropNote(next, hit.i);
    else if (hit.a !== undefined) next = removeAdded(next, hit.a);
  }
  if (next === app.tune) return;
  app.tune = next;
  press.changed = true;
  app.dirty = true;
  updateChrome();
  render();
}

function onRollUp(event) {
  if (!press || press.id !== event.pointerId) return;
  const done = press;
  press = null;
  if (done.brush) {
    if (done.changed) {
      app.undo.push(done.before);
      updateChrome();
    }
    return;
  }
  if (done.moved || performance.now() - done.time > 600) return;
  tapAt(local(event));
}

function onRollCancel(event) {
  if (press && press.id === event.pointerId) {
    if (press.brush && press.changed) app.undo.push(press.before);
    press = null;
  }
}

function tapAt(p) {
  if (p.y <= RULER) {
    moveCursor(Math.max(0, timeAt(p.x)));
    return;
  }
  const hit = noteAt(p.x, p.y, TAP_SLOP);
  if (app.mode === "add") {
    if (hit && hit.a !== undefined) {
      setTune(removeAdded(app.tune, hit.a));
      return;
    }
    const pitch = noteAtY(p.y);
    if (pitch < app.low || pitch > app.high) return;
    const result = addNote(app.notes, app.tune, pitch, Math.max(0, timeAt(p.x)), addContext());
    setTune(result.state);
    blip(pitch);
    return;
  }
  if (app.mode !== "tap") return;
  if (!hit) {
    moveCursor(Math.max(0, timeAt(p.x)));
    return;
  }
  if (hit.a !== undefined) {
    setTune(removeAdded(app.tune, hit.a));
    return;
  }
  const wasKept = app.tune.kept.has(hit.i);
  setTune(toggleNote(app.notes, app.tune, hit.i));
  if (!wasKept) blip(app.notes[hit.i][2]);
}

function moveCursor(t) {
  if (app.playing) {
    stop();
    app.cursor = t;
    play();
  } else {
    app.cursor = t;
  }
  render();
}

// ---------- playback ----------

function songNow() {
  const p = app.playing;
  return p.from + (audio.ctx.currentTime - p.t0) * 1000;
}

function play() {
  if (!app.song) return;
  const ac = ensureAudio().ctx;
  const events = tuneList().map((n) => ({ s: n.s, e: n.e, n: n.n, level: 0.9 }));
  if (app.listen === "all") {
    app.notes.forEach(([s, e, n, part], i) => {
      if (app.tune.kept.has(i) || app.hidden.has(part) || app.song.parts[part].drums) return;
      events.push({ s, e, n, level: 0.16 });
    });
  }
  events.sort((a, b) => a.s - b.s);
  const lastEnd = events.reduce((m, ev) => Math.max(m, ev.e), 0);
  app.playing = {
    from: app.cursor,
    t0: ac.currentTime + 0.06,
    events,
    next: lowerBound(events.map((ev) => ev.s), app.cursor),
    lastEnd,
    timer: setInterval(pump, 25)
  };
  pump();
  $("playButton").textContent = "Stop";
  $("playButton").classList.add("on");
  requestAnimationFrame(follow);
}

function pump() {
  const p = app.playing;
  if (!p) return;
  const now = songNow();
  while (p.next < p.events.length && p.events[p.next].s < now + PLAY_AHEAD_MS) {
    const ev = p.events[p.next++];
    const when = p.t0 + (ev.s - p.from) / 1000;
    if (when >= audio.ctx.currentTime - 0.02) {
      voice(ev.n, Math.max(when, audio.ctx.currentTime), (ev.e - ev.s) / 1000, ev.level);
    }
  }
}

function follow() {
  if (!app.playing) return;
  const now = songNow();
  if (now > app.playing.lastEnd + 400) {
    stop();
    return;
  }
  const x = xOf(now);
  if (x > app.view.w * 0.75 || x < GUTTER) scrollToTime(now, 0.25);
  render();
  requestAnimationFrame(follow);
}

function stop() {
  if (!app.playing) return;
  clearInterval(app.playing.timer);
  app.playing = null;
  silence();
  $("playButton").textContent = "Play";
  $("playButton").classList.remove("on");
  render();
}

// ---------- keys (on screen, computer, MIDI) ----------

const held = new Map();

function keyDown(note) {
  if (held.has(note)) return;
  const { ctx: ac } = ensureAudio();
  held.set(note, voice(note, ac.currentTime, null, 0.9));
  markKey(note, true);
  if (app.mode !== "add" || !app.song) return;
  const t = app.playing ? Math.max(0, songNow() - REACTION_MS) : app.cursor;
  const result = addNote(app.notes, app.tune, note, t, addContext());
  setTune(result.state);
  if (!app.playing) {
    app.cursor = nextStep(result.start, app.onsets, app.lyrics);
    const x = xOf(app.cursor);
    if (x > app.view.w * 0.8 || x < GUTTER) scrollToTime(app.cursor);
    showNoteRow(note);
    render();
  }
}

function keyUp(note) {
  const release = held.get(note);
  if (!release) return;
  held.delete(note);
  release();
  markKey(note, false);
}

function showNoteRow(note) {
  if (note < app.low || note > app.high) return;
  const y = yOf(note);
  if (y < RULER || y + app.rowH > app.view.h) {
    scroller.scrollTop = Math.max(0, RULER + (app.high - note) * app.rowH - app.view.h / 2);
  }
}

function buildPiano() {
  const piano = $("piano");
  piano.textContent = "";
  const base = 12 * (app.octave + 1);
  const whites = [];
  for (let n = base; n < base + 24; n++) if (PITCH_CLASSES[pitchClass(n)].white) whites.push(n);
  whites.push(base + 24);
  const width = 100 / whites.length;
  whites.forEach((n, k) => {
    const key = document.createElement("div");
    key.className = "key white";
    key.dataset.note = n;
    key.style.left = `${k * width}%`;
    key.style.width = `${width}%`;
    const pc = pitchClass(n);
    key.textContent = pc === 0 ? `C${Math.floor(n / 12) - 1}` : PITCH_CLASSES[pc].name;
    key.style.borderBottom = `4px solid ${PITCH_CLASSES[pc].color}`;
    piano.appendChild(key);
  });
  for (let n = base; n < base + 24; n++) {
    if (PITCH_CLASSES[pitchClass(n)].white) continue;
    const below = whites.indexOf(n - 1);
    const key = document.createElement("div");
    key.className = "key black";
    key.dataset.note = n;
    key.style.left = `${(below + 1) * width - width * 0.31}%`;
    key.style.width = `${width * 0.62}%`;
    piano.appendChild(key);
  }
  for (const note of held.keys()) markKey(note, true);
}

function markKey(note, down) {
  const key = $("piano").querySelector(`[data-note="${note}"]`);
  if (key) key.classList.toggle("down", down);
}

const pointerKeys = new Map();

function pianoDown(event) {
  const key = event.target.closest(".key");
  if (!key) return;
  event.preventDefault();
  const note = Number(key.dataset.note);
  pointerKeys.set(event.pointerId, note);
  keyDown(note);
}

function pianoUp(event) {
  const note = pointerKeys.get(event.pointerId);
  if (note === undefined) return;
  pointerKeys.delete(event.pointerId);
  keyUp(note);
}

// Computer keys like the Key Games app: A S D F G H J K = C D E F G A B C.
const COMPUTER_KEYS = { a: 0, w: 1, s: 2, e: 3, d: 4, f: 5, t: 6, g: 7, y: 8, h: 9, u: 10, j: 11, k: 12 };

function onKey(event, down) {
  if (event.target instanceof HTMLInputElement || document.querySelector(".sheet:not([hidden])")) return;
  if (event.ctrlKey || event.metaKey) {
    if (down && event.key === "z") {
      event.preventDefault();
      undo();
    }
    return;
  }
  const key = event.key.toLowerCase();
  if (down && key === " ") {
    event.preventDefault();
    app.playing ? stop() : play();
    return;
  }
  if (down && (key === "z" || key === "x")) {
    setOctave(app.octave + (key === "z" ? -1 : 1));
    return;
  }
  if (!(key in COMPUTER_KEYS) || event.repeat) return;
  const note = 12 * (app.octave + 1) + COMPUTER_KEYS[key];
  down ? keyDown(note) : keyUp(note);
}

function setOctave(octave) {
  app.octave = Math.max(1, Math.min(6, octave));
  buildPiano();
}

async function connectMidi() {
  if (!navigator.requestMIDIAccess) {
    toast("This browser has no MIDI support.", true);
    return;
  }
  try {
    const access = await navigator.requestMIDIAccess();
    const listen = () => {
      let count = 0;
      for (const input of access.inputs.values()) {
        count++;
        input.onmidimessage = ({ data }) => {
          const kind = data[0] & 0xf0;
          if (kind === 0x90 && data[2] > 0) keyDown(data[1]);
          else if (kind === 0x80 || kind === 0x90) keyUp(data[1]);
        };
      }
      $("midiButton").textContent = count ? `MIDI keyboard on (${count})` : "No MIDI keyboard found";
    };
    access.onstatechange = listen;
    listen();
  } catch {
    toast("MIDI was not allowed.", true);
  }
}

// ---------- loading and saving ----------

async function getJson(url, options) {
  const response = await fetch(url, options);
  const body = await response.json();
  if (!response.ok) throw new Error(body.error || response.statusText);
  return body;
}

async function loadSongs() {
  app.songs = (await getJson("/api/songs")).songs;
  renderSongList();
}

async function openSong(id) {
  stop();
  let song;
  try {
    song = await getJson(`/api/song?id=${encodeURIComponent(id)}`);
  } catch (error) {
    toast(`Could not open it: ${error.message}`, true);
    if (!app.song) $("songButton").click();
    return;
  }
  app.song = song;
  app.notes = song.notes;
  app.order = song.notes.map((_, i) => i).sort((a, b) => song.notes[a][0] - song.notes[b][0]);
  app.starts = app.order.map((i) => song.notes[i][0]);
  app.maxLen = song.notes.reduce((m, n) => Math.max(m, n[1] - n[0]), 0);
  app.lyricText = song.lyrics;
  app.lyrics = uniqueSorted(song.lyrics.map((l) => l[0]));
  app.hidden = new Set(song.parts.map((p, k) => (p.drums ? k : -1)).filter((k) => k >= 0));
  app.onsets = onsetTimes(app.notes, app.hidden);
  app.tune = song.saved
    ? { kept: new Set(song.saved.kept), added: song.saved.added.map(([s, e, n]) => ({ s, e, n })) }
    : { kept: new Set(song.auto), added: [] };
  app.undo = [];
  app.dirty = false;

  const pitched = song.notes.filter((n) => !song.parts[n[3]].drums).map((n) => n[2]);
  const tune = tuneList();
  const pitches = pitched.length ? pitched : [60, 72];
  app.low = Math.max(0, Math.min(...pitches) - 2);
  app.high = Math.min(127, Math.max(...pitches) + 2);
  app.duration = song.notes.reduce((m, n) => Math.max(m, n[1]), 1000);
  app.cursor = tune.length ? tune[0].s : 0;
  const sorted = tune.map((n) => n.n).sort((x, y) => x - y);
  const middle = sorted.length ? sorted[Math.floor(sorted.length / 2)] : 60;
  // Two octaves of keys with the tune's middle note in them.
  setOctave(Math.floor((middle - 6) / 12) - 1);

  $("empty").hidden = true;
  try { localStorage.setItem(LAST_SONG_KEY, id); } catch { /* private window */ }
  resize();
  scrollToTime(app.cursor, 0.15);
  if (tune.length) showNoteRow(middle);
  else scroller.scrollTop = 0;
  updateChrome();
  render();
}

function updateChrome() {
  const song = app.song;
  const ready = Boolean(song);
  for (const id of ["playButton", "saveButton", "partsButton"]) $(id).disabled = !ready;
  $("undoButton").disabled = app.undo.length === 0;
  if (!song) return;
  $("songTitle").textContent = song.title;
  const where = song.source === "downloads" ? "Downloads" : song.group;
  const state = app.dirty ? "not saved" : song.saved ? "saved tune" : "auto pick";
  $("songSub").textContent = `${where} - ${song.file} - ${state}`;
  const count = app.tune.kept.size + app.tune.added.length;
  $("count").textContent = `${count} notes`;
}

function openSave() {
  const song = app.song;
  $("saveTitle").value = song.title;
  $("saveGroup").value = song.group;
  const list = $("groupList");
  list.textContent = "";
  for (const group of song.groups) {
    const option = document.createElement("option");
    option.value = group;
    list.appendChild(option);
  }
  $("saveNote").textContent = song.source === "downloads"
    ? "This file is in Downloads: saving copies it into your songs folder."
    : "The app picks up the saved tune on its next build.";
  showSheet("saveSheet");
}

async function saveTune() {
  const song = app.song;
  const body = {
    title: $("saveTitle").value.trim(),
    group: $("saveGroup").value.trim(),
    kept: [...app.tune.kept].sort((a, b) => a - b),
    added: app.tune.added.map((n) => [n.s, n.e, n.n])
  };
  $("saveConfirm").disabled = true;
  try {
    const result = await getJson(`/api/save?id=${encodeURIComponent(song.id)}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body)
    });
    song.id = result.id;
    song.source = "songs";
    song.file = result.file;
    song.title = body.title || song.title;
    song.group = body.group || song.group;
    song.saved = { kept: body.kept, added: body.added };
    app.dirty = false;
    try { localStorage.setItem(LAST_SONG_KEY, song.id); } catch { /* private window */ }
    hideSheets();
    updateChrome();
    toast(`Saved: ${result.notes} notes in the app's version.`);
    loadSongs().catch(() => {});
  } catch (error) {
    toast(`Not saved: ${error.message}`, true);
  } finally {
    $("saveConfirm").disabled = false;
  }
}

// ---------- sheets ----------

function showSheet(id) {
  hideSheets();
  $(id).hidden = false;
}

function hideSheets() {
  for (const sheet of document.querySelectorAll(".sheet")) sheet.hidden = true;
}

function renderSongList() {
  const list = $("songList");
  const query = $("songSearch").value.trim().toLowerCase();
  list.textContent = "";
  const match = (s) => !query || `${s.title} ${s.file} ${s.group}`.toLowerCase().includes(query);
  const groups = new Map();
  for (const song of app.songs.filter(match)) {
    const head = song.source === "downloads" ? "Downloads" : song.group;
    if (!groups.has(head)) groups.set(head, []);
    groups.get(head).push(song);
  }
  const heads = [...groups.keys()].sort((a, b) =>
    (a === "Downloads") - (b === "Downloads") || a.localeCompare(b));
  for (const head of heads) {
    const title = document.createElement("div");
    title.className = "group-head";
    title.textContent = head;
    list.appendChild(title);
    for (const song of groups.get(head).sort((a, b) => a.title.localeCompare(b.title))) {
      const row = document.createElement("button");
      row.type = "button";
      row.className = "song-row";
      const name = document.createElement("span");
      name.textContent = song.title;
      if (song.edited) {
        const badge = document.createElement("span");
        badge.className = "badge";
        badge.textContent = "edited";
        name.appendChild(badge);
      }
      const file = document.createElement("span");
      file.className = "file";
      file.textContent = song.file;
      row.append(name, file);
      row.addEventListener("click", () => {
        if (app.dirty && !window.confirm("Leave this song without saving?")) return;
        hideSheets();
        openSong(song.id);
      });
      list.appendChild(row);
    }
  }
  if (!list.firstChild) list.textContent = "No MIDI files found.";
}

function renderParts() {
  const list = $("partList");
  list.textContent = "";
  app.song.parts.forEach((part, k) => {
    const row = document.createElement("div");
    row.className = "part-row";
    const info = document.createElement("div");
    info.className = "info";
    const name = document.createElement("div");
    name.className = "name";
    name.textContent = part.name || part.instrument;
    const meta = document.createElement("div");
    meta.className = "meta";
    const inTune = app.notes.filter((n, i) => n[3] === k && app.tune.kept.has(i)).length;
    meta.textContent = `${part.instrument}, ch ${part.channel}, ${part.count} notes, ${inTune} in the tune`;
    info.append(name, meta);
    const show = button(app.hidden.has(k) ? "Show" : "Shown", () => {
      app.hidden.has(k) ? app.hidden.delete(k) : app.hidden.add(k);
      app.onsets = onsetTimes(app.notes, app.hidden);
      renderParts();
      render();
    });
    show.classList.toggle("on", !app.hidden.has(k));
    const keep = button("Keep", () => {
      setTune(keepPart(app.notes, app.tune, k));
      renderParts();
    });
    const drop = button("Drop", () => {
      setTune(dropPart(app.notes, app.tune, k));
      renderParts();
    });
    if (part.drums) keep.disabled = true;
    row.append(info, show, keep, drop);
    list.appendChild(row);
  });
}

function button(label, onClick) {
  const el = document.createElement("button");
  el.type = "button";
  el.textContent = label;
  el.addEventListener("click", onClick);
  return el;
}

let toastTimer = null;

function toast(text, bad = false) {
  const el = $("toast");
  el.textContent = text;
  el.classList.toggle("bad", bad);
  el.hidden = false;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => { el.hidden = true; }, 3500);
}

function setMode(mode) {
  app.mode = mode;
  for (const b of document.querySelectorAll("#modes button")) b.classList.toggle("on", b.dataset.mode === mode);
  scroller.classList.toggle("brush", mode === "keep" || mode === "drop");
  $("hint").textContent = HINTS[mode];
}

// ---------- wiring ----------

scroller.addEventListener("scroll", render, { passive: true });
scroller.addEventListener("pointerdown", onRollDown);
scroller.addEventListener("pointermove", onRollMove);
scroller.addEventListener("pointerup", onRollUp);
scroller.addEventListener("pointercancel", onRollCancel);
scroller.addEventListener("wheel", (event) => {
  if (!event.ctrlKey) return;
  event.preventDefault();
  setZoom(app.zoomIndex + (event.deltaY < 0 ? 1 : -1));
}, { passive: false });

$("piano").addEventListener("pointerdown", pianoDown);
for (const type of ["pointerup", "pointercancel", "pointerleave"]) $("piano").addEventListener(type, pianoUp);
$("octDown").addEventListener("click", () => setOctave(app.octave - 1));
$("octUp").addEventListener("click", () => setOctave(app.octave + 1));

$("songButton").addEventListener("click", () => {
  showSheet("songSheet");
  loadSongs().catch((error) => toast(`Could not list songs: ${error.message}`, true));
});
$("songSearch").addEventListener("input", renderSongList);
$("playButton").addEventListener("click", () => (app.playing ? stop() : play()));
$("undoButton").addEventListener("click", undo);
$("zoomIn").addEventListener("click", () => setZoom(app.zoomIndex + 1));
$("zoomOut").addEventListener("click", () => setZoom(app.zoomIndex - 1));
$("partsButton").addEventListener("click", () => {
  renderParts();
  showSheet("partsSheet");
});
$("saveButton").addEventListener("click", openSave);
$("saveConfirm").addEventListener("click", saveTune);
$("autoButton").addEventListener("click", () => {
  setTune({ kept: new Set(app.song.auto), added: [] });
  renderParts();
});
$("clearButton").addEventListener("click", () => {
  setTune({ kept: new Set(), added: [] });
  renderParts();
});
$("midiButton").addEventListener("click", connectMidi);
for (const b of document.querySelectorAll("[data-close]")) b.addEventListener("click", hideSheets);
for (const b of document.querySelectorAll("#modes button")) b.addEventListener("click", () => setMode(b.dataset.mode));
for (const b of document.querySelectorAll("#listen button")) {
  b.addEventListener("click", () => {
    app.listen = b.dataset.listen;
    for (const other of document.querySelectorAll("#listen button")) other.classList.toggle("on", other === b);
    if (app.playing) {
      stop();
      play();
    }
  });
}
window.addEventListener("keydown", (event) => onKey(event, true));
window.addEventListener("keyup", (event) => onKey(event, false));
window.addEventListener("beforeunload", (event) => {
  if (app.dirty) event.preventDefault();
});
new ResizeObserver(resize).observe($("rollWrap"));

setMode("tap");
buildPiano();
updateChrome();
// ?song=songs/name.mid opens that song; otherwise the last one opened.
let last = new URLSearchParams(location.search).get("song");
try { last = last || localStorage.getItem(LAST_SONG_KEY); } catch { /* private window */ }
if (last) openSong(last);
else $("songButton").click();
