import {
  PITCH_CLASSES,
  STARS_PER_ROUND,
  advance,
  createGame,
  createMirrorFilter,
  noteEventFromBytes,
  noteToFrequency,
  pitchClass,
  pressNote
} from "/games/color-keys.js";

const byId = (id) => document.getElementById(id);
const el = {
  canvas: byId("sparks"),
  prompt: byId("prompt"),
  target: byId("target"),
  targetName: byId("target-name"),
  stars: byId("stars"),
  round: byId("round"),
  midiStatus: byId("midi-status"),
  soundGate: byId("sound-gate"),
  soundButton: byId("sound-button")
};

// ---- Sound (Web Audio, so it plays through the PC and streams to the TV) ----

const audio = new AudioContext();
const master = audio.createGain();
master.gain.value = 0.5;
master.connect(audio.destination);
const voices = new Map();

function noteOn(note, velocity) {
  noteOff(note);
  const now = audio.currentTime;
  const level = 0.12 + (velocity / 127) * 0.18;
  const env = audio.createGain();
  env.gain.setValueAtTime(0, now);
  env.gain.linearRampToValueAtTime(level, now + 0.01);
  env.gain.exponentialRampToValueAtTime(level * 0.35, now + 0.6);
  env.connect(master);
  const frequency = noteToFrequency(note);
  const oscillators = [
    ["triangle", frequency, 1],
    ["sine", frequency * 2, 0.3]
  ].map(([type, hz, gain]) => {
    const osc = audio.createOscillator();
    const g = audio.createGain();
    osc.type = type;
    osc.frequency.value = hz;
    g.gain.value = gain;
    osc.connect(g).connect(env);
    osc.start(now);
    return osc;
  });
  voices.set(note, { env, oscillators });
}

function noteOff(note) {
  const voice = voices.get(note);
  if (!voice) return;
  voices.delete(note);
  const now = audio.currentTime;
  voice.env.gain.cancelScheduledValues(now);
  voice.env.gain.setValueAtTime(voice.env.gain.value, now);
  voice.env.gain.exponentialRampToValueAtTime(0.0001, now + 0.35);
  for (const osc of voice.oscillators) osc.stop(now + 0.4);
}

function blip(note, startIn, length = 0.18, level = 0.18) {
  const start = audio.currentTime + startIn;
  const env = audio.createGain();
  env.gain.setValueAtTime(0, start);
  env.gain.linearRampToValueAtTime(level, start + 0.01);
  env.gain.exponentialRampToValueAtTime(0.0001, start + length);
  env.connect(master);
  const osc = audio.createOscillator();
  osc.type = "square";
  osc.frequency.value = noteToFrequency(note);
  osc.connect(env);
  osc.start(start);
  osc.stop(start + length + 0.05);
}

const playCheer = (note) => [0, 4, 7, 12].forEach((step, i) => blip(note + 12 + step, i * 0.07));
const playFanfare = () => [72, 76, 79, 84, 79, 84].forEach((n, i) => blip(n, 0.3 + i * 0.12, 0.25));

// Short hint tone so kids also hear the target, in a comfortable octave.
function playHint(pc) {
  const note = 60 + pc;
  noteOn(note, 60);
  setTimeout(() => noteOff(note), 450);
}

function updateSoundGate() {
  el.soundGate.hidden = audio.state === "running";
}

async function unlockSound() {
  try { await audio.resume(); } catch { /* still locked */ }
  updateSoundGate();
}

el.soundButton.addEventListener("click", unlockSound);
window.addEventListener("keydown", unlockSound);
window.addEventListener("pointerdown", unlockSound);
audio.addEventListener("statechange", updateSoundGate);
// Launched with an autoplay flag this succeeds at once; otherwise the gate shows.
unlockSound();
setTimeout(updateSoundGate, 500);

// ---- Sparks (canvas particles) ----

const ctx = el.canvas.getContext("2d");
const sparks = [];

function resize() {
  el.canvas.width = window.innerWidth * devicePixelRatio;
  el.canvas.height = window.innerHeight * devicePixelRatio;
}
window.addEventListener("resize", resize);
resize();

function burst(note, count, big = false) {
  const color = PITCH_CLASSES[pitchClass(note)].color;
  const w = el.canvas.width;
  const h = el.canvas.height;
  // Low notes on the left, high on the right, like the keyboard.
  const x = big ? w / 2 : w * (0.08 + 0.84 * Math.min(1, Math.max(0, (note - 36) / 60)));
  const y = big ? h / 2 : h * 0.85;
  for (let i = 0; i < count; i++) {
    const angle = big ? Math.random() * Math.PI * 2 : -Math.PI / 2 + (Math.random() - 0.5) * 1.6;
    const speed = (big ? 8 : 6) + Math.random() * (big ? 16 : 10);
    sparks.push({
      x, y,
      vx: Math.cos(angle) * speed * devicePixelRatio,
      vy: Math.sin(angle) * speed * devicePixelRatio,
      life: 1,
      size: (6 + Math.random() * 10) * devicePixelRatio,
      color: big ? PITCH_CLASSES[Math.floor(Math.random() * 12)].color : color
    });
  }
  if (sparks.length > 1500) sparks.splice(0, sparks.length - 1500);
}

function frame() {
  ctx.clearRect(0, 0, el.canvas.width, el.canvas.height);
  for (let i = sparks.length - 1; i >= 0; i--) {
    const s = sparks[i];
    s.x += s.vx;
    s.y += s.vy;
    s.vy += 0.25 * devicePixelRatio;
    s.life -= 0.012;
    if (s.life <= 0) { sparks.splice(i, 1); continue; }
    ctx.globalAlpha = s.life;
    ctx.fillStyle = s.color;
    ctx.beginPath();
    ctx.arc(s.x, s.y, s.size * s.life, 0, Math.PI * 2);
    ctx.fill();
  }
  ctx.globalAlpha = 1;
  requestAnimationFrame(frame);
}
requestAnimationFrame(frame);

// ---- Game ----

let game = createGame();

function renderGame({ hint = true } = {}) {
  const entry = PITCH_CLASSES[game.target];
  el.target.style.background = entry.color;
  el.target.style.boxShadow = `0 0 10vh ${entry.color}`;
  el.targetName.textContent = entry.colorName;
  el.stars.replaceChildren(...Array.from({ length: STARS_PER_ROUND }, (_, i) => {
    const star = document.createElement("div");
    star.className = i < game.stars ? "star lit" : "star";
    return star;
  }));
  el.round.textContent = game.rounds > 0 ? `Rounds won: ${game.rounds}` : "";
  if (hint && audio.state === "running") playHint(game.target);
}

function flash(className) {
  el.target.classList.remove("hit", "miss");
  void el.target.offsetWidth;
  el.target.classList.add(className);
  setTimeout(() => el.target.classList.remove(className), 300);
}

function handleNoteOn(note, velocity) {
  noteOn(note, velocity);
  burst(note, 14);
  const result = pressNote(game, note);
  game = result.state;
  for (const effect of result.effects) {
    if (effect.type === "hit") {
      flash("hit");
      burst(note, 60, true);
      playCheer(note);
      renderGame({ hint: false });
    } else if (effect.type === "miss") {
      flash("miss");
    } else if (effect.type === "next-soon") {
      setTimeout(() => { game = advance(game); renderGame(); }, 1200);
    } else if (effect.type === "win") {
      el.prompt.textContent = "YOU DID IT!";
      playFanfare();
      for (let i = 0; i < 6; i++) setTimeout(() => burst(48 + i * 7, 120, true), i * 250);
      setTimeout(() => {
        game = advance(game);
        el.prompt.textContent = "Find";
        renderGame();
      }, 4000);
    }
  }
}

// Computer keyboard fallback for testing without the MIDI keyboard:
// a s d f g h j = C D E F G A B.
const TYPING_KEYS = { a: 60, s: 62, d: 64, f: 65, g: 67, h: 69, j: 71 };
window.addEventListener("keydown", (event) => {
  const note = TYPING_KEYS[event.key];
  if (note === undefined || event.repeat) return;
  handleNoteOn(note, 80);
});
window.addEventListener("keyup", (event) => {
  const note = TYPING_KEYS[event.key];
  if (note !== undefined) noteOff(note);
});

// ---- MIDI ----

const acceptMessage = createMirrorFilter(60);
let midiAccess = null;

function onMidiMessage(input, event) {
  if (!acceptMessage(input.id, event.data, event.timeStamp)) return;
  const parsed = noteEventFromBytes(event.data);
  if (!parsed) return;
  if (parsed.type === "on") handleNoteOn(parsed.note, parsed.velocity);
  else noteOff(parsed.note);
}

function refreshInputs() {
  const names = [];
  for (const input of midiAccess.inputs.values()) {
    input.onmidimessage = (event) => onMidiMessage(input, event);
    if (input.state === "connected") names.push(input.name || input.id);
  }
  el.midiStatus.textContent = names.length
    ? `Listening: ${names.join(", ")}`
    : "No keyboard found. Turn it on (and pair Bluetooth), it will appear here.";
}

async function startMidi() {
  if (!("requestMIDIAccess" in navigator)) {
    el.midiStatus.textContent = "This browser has no Web MIDI. Use Chrome or Edge. Typing a s d f g h j works.";
    return;
  }
  try {
    midiAccess = await navigator.requestMIDIAccess({ sysex: false });
    midiAccess.onstatechange = refreshInputs;
    refreshInputs();
  } catch (error) {
    el.midiStatus.textContent = `MIDI blocked (${error.message || error}) Typing a s d f g h j works.`;
  }
}

renderGame({ hint: false });
startMidi();
