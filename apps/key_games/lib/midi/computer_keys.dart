// Computer keys for testing on a PC without the MIDI keyboard: A S D F G H J K
// play one octave of white keys from middle C.

import 'package:flutter/services.dart';

import 'midi_input.dart';

final _computerKeys = {
  LogicalKeyboardKey.keyA: 60,
  LogicalKeyboardKey.keyS: 62,
  LogicalKeyboardKey.keyD: 64,
  LogicalKeyboardKey.keyF: 65,
  LogicalKeyboardKey.keyG: 67,
  LogicalKeyboardKey.keyH: 69,
  LogicalKeyboardKey.keyJ: 71,
  LogicalKeyboardKey.keyK: 72,
};

// Use as a HardwareKeyboard handler; returns true when the key was a note.
bool handleComputerKey(KeyEvent event, void Function(NoteEvent) onNote) {
  final note = _computerKeys[event.logicalKey];
  if (note == null || event is KeyRepeatEvent) return false;
  onNote(NoteEvent(note, 100, on: event is KeyDownEvent));
  return true;
}
