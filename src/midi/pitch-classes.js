// One color per pitch class, rainbow order on the white keys (C red .. B pink);
// black keys get in-between shades. The song editor draws its piano roll with
// this table. The app's copy is pitchClasses in
// apps/key_games/lib/games/color_keys_rules.dart; keep the two the same.

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

export function pitchClass(note) {
  return ((note % 12) + 12) % 12;
}
