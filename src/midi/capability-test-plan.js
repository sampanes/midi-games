function step(key, group, label, instructions, flags = {}) {
  return Object.freeze({ key, group, label, instructions, ...flags });
}

function numberedSteps(count, makeStep) {
  return Array.from({ length: count }, (_, index) => makeStep(index + 1));
}

const setupSteps = [
  step(
    "setup.identity",
    "setup",
    "Record device identity",
    "Record the exact model name, firmware version, battery state, connected cables, browser version, and visible MIDI input and output names."
  ),
  step(
    "setup.global-settings",
    "setup",
    "Record GLOBE settings",
    "Read and record the selected preset, key channel, pad channel, key velocity curve, pad velocity curve, pad-aftertouch setting, and pedal mode without changing them."
  ),
  step(
    "setup.neutral-state",
    "setup",
    "Set a neutral starting state",
    "Disable Arp latch and Note Repeat latch before turning those modes off; stop Sequencer playback; release sustain; turn off Scale and Chord; center the octave; select the base knob and fader banks and pads 1-16; then record whether Patch is on or off."
  ),
  step(
    "idle.untouched",
    "idle",
    "Observe the untouched controller",
    "Keep hands and feet off every control until the event display is stable, then record any active sensing, clock, jitter, or other unsolicited messages before continuing."
  )
];

const keySteps = [
  step(
    "keys.bulk-sweep",
    "keys",
    "Play all 37 keys in order",
    "With the octave centered, play every physical key once from the lowest key to the highest key, releasing each before playing the next."
  ),
  step(
    "keys.velocity",
    "keys",
    "Test key velocity",
    "Play the lowest key, a middle key, and the highest key gently, normally, and firmly; fully release each key between presses."
  ),
  step(
    "keys.hold-release",
    "keys",
    "Test held keys and releases",
    "Hold a low key and a high key together, vary neither key, then release them separately so press, hold, and release behavior can be distinguished."
  ),
  step(
    "keys.chords",
    "keys",
    "Test chords and polyphony",
    "Play a two-note interval, a three-note chord, a wide six-note chord, and as many keys as can be pressed comfortably at once; release each chord together."
  )
];

const basePadSteps = numberedSteps(16, (pad) => step(
  `pads.base.${String(pad).padStart(2, "0")}`,
  "pads",
  `Pad ${pad}`,
  `Select pads 1-16. Strike physical pad ${pad} gently, normally, and firmly, then hold it while varying pressure before release.`
));

const bankedPadSteps = numberedSteps(16, (physicalPad) => {
  const logicalPad = physicalPad + 16;
  return step(
    `pads.bank.${String(logicalPad).padStart(2, "0")}`,
    "pads",
    `Pad ${logicalPad}`,
    `Select the pad bank by engaging Knob Bank and Fader Bank together. Strike physical pad ${physicalPad} gently, normally, and firmly, then hold it while varying pressure before release.`
  );
});

const baseKnobSteps = numberedSteps(8, (knob) => step(
  `knobs.base.${String(knob).padStart(2, "0")}`,
  "knobs",
  `Knob ${knob}`,
  `Select the base knob bank. Turn physical knob ${knob} slowly through several rotations clockwise, reverse through several rotations, then make a few quick movements in both directions.`
));

const bankedKnobSteps = numberedSteps(8, (physicalKnob) => {
  const logicalKnob = physicalKnob + 8;
  return step(
    `knobs.bank.${String(logicalKnob).padStart(2, "0")}`,
    "knobs",
    `Knob ${logicalKnob}`,
    `Select the second knob bank. Turn physical knob ${physicalKnob} slowly through several rotations clockwise, reverse through several rotations, then make a few quick movements in both directions.`
  );
});

const baseFaderSteps = numberedSteps(4, (fader) => step(
  `faders.base.${String(fader).padStart(2, "0")}`,
  "faders",
  `Fader ${fader}`,
  `Select the base fader bank. Move physical fader ${fader} to minimum, maximum, and minimum again, pausing at several intermediate positions and then leaving it untouched.`
));

const bankedFaderSteps = numberedSteps(4, (physicalFader) => {
  const logicalFader = physicalFader + 4;
  return step(
    `faders.bank.${String(logicalFader).padStart(2, "0")}`,
    "faders",
    `Fader ${logicalFader}`,
    `Select the second fader bank. Move physical fader ${physicalFader} to minimum, maximum, and minimum again, pausing at several intermediate positions and then leaving it untouched.`
  );
});

const wheelAndPedalSteps = [
  step(
    "wheels.pitch",
    "wheels",
    "Pitch wheel",
    "Move the pitch wheel from center to minimum, through center to maximum, and release it several ways, including slowly and quickly."
  ),
  step(
    "wheels.mod",
    "wheels",
    "Modulation wheel",
    "Move the modulation wheel from minimum to maximum and back, pausing at several intermediate positions and then leaving it untouched."
  ),
  step(
    "pedal.sustain",
    "pedal",
    "Sustain pedal mode",
    "Set the GLOBE pedal setting to sustain, then press and release the connected pedal while no other control is moving.",
    { optional: true, accessory: "Compatible sustain or switch pedal" }
  ),
  step(
    "pedal.expression",
    "pedal",
    "Expression pedal mode",
    "Set the GLOBE pedal setting to expression, then sweep the connected pedal through its full travel in both directions and leave it untouched.",
    { optional: true, accessory: "Compatible expression pedal" }
  )
];

const documentedButtons = [
  ["knob-bank", "Knob Bank"],
  ["fader-bank", "Fader Bank"],
  ["octave-down", "Octave -"],
  ["octave-up", "Octave +"],
  ["left", "Left"],
  ["right", "Right"],
  ["arp", "Arp"],
  ["note-repeat", "Note Repeat"],
  ["scale", "Scale"],
  ["chord", "Chord"],
  ["globe", "GLOBE"],
  ["bt", "BT"],
  ["patch", "Patch"],
  ["para", "Para"],
  ["fx", "FX"],
  ["seq", "Seq"],
  ["seq-play", "Seq Play"],
  ["seq-rec", "Seq Rec"]
];

const buttonSteps = documentedButtons.map(([key, label]) => step(
  `buttons.${key}`,
  "buttons",
  `${label} button`,
  `With no other control moving, press and release the ${label} button. Record its messages or explicitly record "No MIDI observed," then restore the prior mode if the button latched.`,
  key === "bt"
    ? { risk: "Changing Bluetooth state can interrupt the capture; save the current inventory first." }
    : key === "seq-rec"
      ? { risk: "Recording can alter the selected sequencer pattern; use an expendable pattern slot." }
      : {}
));

const transportSteps = [
  step(
    "transport.usb-only",
    "transport",
    "USB-only canonical pass",
    "Disconnect Bluetooth MIDI, keep USB connected, then play the lowest, middle, and highest keys; strike pads 1 and 16; move both wheels; move fader 1; and turn knob 1."
  ),
  step(
    "transport.usb-and-bluetooth",
    "transport",
    "USB and Bluetooth mirror pass",
    "Connect USB and Bluetooth MIDI together, repeat the canonical control pass in the same order, and preserve every raw event from every input for mirror comparison."
  ),
  step(
    "transport.bluetooth-only",
    "transport",
    "Bluetooth-only canonical pass",
    "Save the active capture, unplug USB data while the keyboard runs from its battery, reconnect Bluetooth MIDI if needed, and repeat the canonical control pass.",
    { risk: "Unplugging USB changes the available ports and can interrupt capture; save first." }
  ),
  step(
    "transport.rapid-notes",
    "transport",
    "Rapid note stress",
    "Play fast scales, repeated notes, alternating low and high notes, and dense chords over each available transport while preserving event order and timestamps."
  ),
  step(
    "transport.simultaneous-controls",
    "transport",
    "Simultaneous-control stress",
    "Move a wheel or fader while playing keys, then turn an encoder while striking pads, and check for dropped, reordered, or stuck events."
  ),
  step(
    "transport.bluetooth-distance",
    "transport",
    "Bluetooth distance check",
    "With the keyboard on battery power, repeat the canonical pass from the intended play location in another room and compare delivery with the nearby Bluetooth pass.",
    { optional: true }
  )
];

const modeSteps = [
  step(
    "modes.octave-down",
    "modes",
    "Octave-down transform",
    "Play the same low, middle, and high physical keys at each available octave-down setting, recording the displayed octave and emitted notes."
  ),
  step(
    "modes.octave-up",
    "modes",
    "Octave-up transform",
    "Play the same low, middle, and high physical keys at each available octave-up setting, recording the displayed octave and emitted notes."
  ),
  step(
    "modes.scale",
    "modes",
    "Scale transform",
    "Choose one documented scale, play notes inside and outside that scale, and compare emitted notes with Scale off."
  ),
  step(
    "modes.chord",
    "modes",
    "Chord transform",
    "Choose a basic chord setting, press one low, middle, and high key separately, and compare every generated note with Chord off."
  ),
  step(
    "modes.arp",
    "modes",
    "Arpeggiator transform",
    "Enable Arp with latch off, hold a chord, change one Arp parameter, release the chord, and record generated notes and any clock or transport messages."
  ),
  step(
    "modes.note-repeat",
    "modes",
    "Note Repeat transform",
    "Enable Note Repeat with latch off, hold one pad and then two pads, change one repeat parameter, release them, and record generated notes and any clock messages."
  ),
  step(
    "modes.sequencer-play",
    "modes",
    "Sequencer playback",
    "Select a disposable or known pattern, start and stop playback, and record notes, clock, start, continue, and stop messages on every input."
  ),
  step(
    "modes.sequencer-record",
    "modes",
    "Sequencer recording",
    "Use an expendable pattern slot, record a short key-and-pad phrase, play it back, and compare the emitted events with the performed events.",
    { optional: true, risk: "This step changes the selected sequencer pattern; use a slot that may be overwritten." }
  ),
  step(
    "modes.patch",
    "modes",
    "Patch and local synth behavior",
    "Play the same key and pad with Patch off and on, observing MIDI traffic separately from sound at the keyboard audio output.",
    { optional: true, accessory: "Wired headphones or powered speaker" }
  ),
  step(
    "modes.para-fx",
    "modes",
    "PARA and FX behavior",
    "Open PARA and FX separately, adjust each available parameter with its documented knob, and record whether changes emit MIDI or remain local.",
    { optional: true, risk: "Parameter changes can alter the current internal-synth preset." }
  )
];

const presetSteps = numberedSteps(8, (preset) => step(
  `presets.${String(preset).padStart(2, "0")}`,
  "presets",
  `Preset ${preset} fingerprint`,
  `Select preset ${preset}. Play the lowest, middle, and highest keys; strike pads 1 and 16; operate all eight knobs and four faders; and move both wheels before restoring the prior preset.`
));

const manualCapabilitySteps = [
  step(
    "presets.export",
    "presets",
    "Export preset configuration",
    "Use MIDI Suite to export or document all editable mappings and retain the export only in the private project area.",
    { optional: true, accessory: "Compatible MIDI Suite application" }
  ),
  step(
    "output.usb-ports",
    "output",
    "Map USB MIDI outputs",
    "After reasserting the neutral state, use the recorded key channel and send one capped-velocity note-on with matching note-off, All Notes Off, and All Sound Off through USB outputs 0, 1, and 2 separately; record sound, lights, display changes, and external MIDI activity.",
    { risk: "Test one verified endpoint at a time, keep audio volume low, disconnect unintended MIDI receivers, and power-cycle if cleanup cannot silence it." }
  ),
  step(
    "output.bluetooth",
    "output",
    "Map Bluetooth MIDI output",
    "After reasserting the neutral state, use the recorded key channel and send one capped-velocity note-on with matching note-off, All Notes Off, and All Sound Off through Bluetooth MIDI OUT; record sound, lights, and display changes.",
    { risk: "Verify the exact Bluetooth endpoint, keep audio volume low, and power-cycle if cleanup cannot silence it." }
  ),
  step(
    "output.pad-lights",
    "output",
    "Probe host-controlled pad lights",
    "After an input trial identifies one physical pad's actual channel and note, send one conservative note-on and matching note-off using that exact pair while observing whether that same pad lights.",
    { optional: true, risk: "Host-controlled lighting is undocumented. Do not scan notes or channels, and do not send undocumented SysEx or firmware data." }
  ),
  step(
    "output.clock-sync",
    "output",
    "Probe MIDI clock synchronization",
    "Send Start, steady MIDI Clock, Stop, and Continue through each candidate output while Arp or Sequencer is active, then record which destinations respond.",
    { optional: true, risk: "Stop playback and send All Notes Off after each output probe." }
  ),
  step(
    "output.physical-midi",
    "output",
    "Map the physical MIDI OUT jack",
    "Connect the correct Type-A adapter to a trusted MIDI input, operate representative controls, and test whether host-sent output is also forwarded to the jack.",
    { optional: true, accessory: "Type-A 3.5 mm-to-DIN MIDI adapter and MIDI input interface" }
  ),
  step(
    "audio.host-playback",
    "audio",
    "Test host audio playback",
    "Select the keyboard audio endpoint as the computer output, play a quiet known sound, and confirm where it is heard and whether Patch changes it.",
    { optional: true, accessory: "Wired headphones or powered speaker", risk: "Begin with computer and keyboard volume low." }
  ),
  step(
    "audio.usb-recording",
    "audio",
    "Test USB audio recording",
    "Select the keyboard recording endpoint, play the internal synth and host audio separately, and record which sources appear in the captured audio.",
    { optional: true, accessory: "Audio recording application" }
  ),
  step(
    "reliability.hot-reconnect",
    "reliability",
    "USB hot reconnect",
    "Save the capture, disconnect and reconnect USB, then verify input and output ports reopen and a canonical key press produces exactly one logical event.",
    { risk: "Save first because disconnecting USB interrupts active ports." }
  ),
  step(
    "reliability.bluetooth-reconnect",
    "reliability",
    "Bluetooth reconnect",
    "Save the capture, disconnect and reconnect Bluetooth MIDI, then verify the prior port returns and the canonical control pass still works.",
    { risk: "Save first because changing Bluetooth state interrupts the active port." }
  ),
  step(
    "reliability.power-cycle",
    "reliability",
    "Controller power cycle",
    "Save the capture, power the keyboard off and on, then record restored preset, bank, mode, MIDI ports, and control mappings.",
    { risk: "Save first and stop any sounding notes before removing power." }
  ),
  step(
    "reliability.browser-reload",
    "reliability",
    "Browser reload and permission recovery",
    "Save the capture, reload the listener, grant MIDI permission if requested, and verify that every expected input can be reopened."
  ),
  step(
    "reliability.single-client",
    "reliability",
    "Single-client contention",
    "After saving, open one trusted MIDI application alongside the listener and record which ports can be shared, which fail to open, and how recovery works after closing the other application.",
    { optional: true, accessory: "Trusted MIDI application", risk: "Another application may temporarily take exclusive ownership of a MIDI port." }
  ),
  step(
    "reliability.stuck-note-recovery",
    "reliability",
    "Stuck-note recovery",
    "Interrupt a sounding test only in a controlled low-volume setup, then verify that explicit note-off, All Notes Off, reconnect, and power-cycle recovery paths silence it.",
    { optional: true, risk: "Use low volume and a disposable synth state because this deliberately exercises interruption recovery." }
  )
];

export const CAPABILITY_TEST_PLAN = Object.freeze([
  ...setupSteps,
  ...keySteps,
  ...basePadSteps,
  ...bankedPadSteps,
  ...baseKnobSteps,
  ...bankedKnobSteps,
  ...baseFaderSteps,
  ...bankedFaderSteps,
  ...wheelAndPedalSteps,
  ...buttonSteps,
  ...transportSteps,
  ...modeSteps,
  ...presetSteps,
  ...manualCapabilitySteps
]);
