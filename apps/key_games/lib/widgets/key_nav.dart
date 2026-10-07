// Keyboard-only navigation, for a TV box where nobody can touch the screen:
// - Menus: every choice wears a note letter (KeyBadge); pressing any key of
//   that letter, in any octave, picks it.
// - Back: hold the lowest and highest C of the keyboard together (two Cs
//   three octaves apart), or press Escape on a computer keyboard.
// Only the page on top reacts, and a page that has just come back to the top
// waits a moment, so the keys that closed a game do not also pick something.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../games/color_keys_rules.dart';
import '../midi/computer_keys.dart';
import '../midi/midi_input.dart';

const backChordSpan = 36;
const _settle = Duration(milliseconds: 600);

// True when pressing [note] while [held] are down makes the back chord.
bool isBackChord(Set<int> held, int note) =>
    pitchClass(note) == 0 &&
    (held.contains(note - backChordSpan) || held.contains(note + backChordSpan));

class KeyNav extends StatefulWidget {
  const KeyNav({super.key, required this.midi, this.picks = const {}, required this.child});

  final MidiInput midi;

  // Pitch class (0-11) -> action.
  final Map<int, VoidCallback> picks;
  final Widget child;

  @override
  State<KeyNav> createState() => _KeyNavState();
}

class _KeyNavState extends State<KeyNav> {
  StreamSubscription<NoteEvent>? _sub;
  final Set<int> _held = {};
  ModalRoute<Object?>? _route;
  DateTime _hiddenAt = DateTime(2000);

  @override
  void initState() {
    super.initState();
    _sub = widget.midi.notes.listen(_onNote);
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    unawaited(_sub?.cancel());
    super.dispose();
  }

  bool get _onTop {
    final now = DateTime.now();
    if (!(_route?.isCurrent ?? true)) {
      _hiddenAt = now;
      return false;
    }
    return now.difference(_hiddenAt) > _settle;
  }

  void _onNote(NoteEvent event) {
    if (!isGameNote(event.note)) return;
    if (!event.on) {
      _held.remove(event.note);
      return;
    }
    final chord = isBackChord(_held, event.note);
    _held.add(event.note);
    if (!mounted || !_onTop) return;
    if (chord) {
      unawaited(Navigator.maybePop(context));
      return;
    }
    widget.picks[pitchClass(event.note)]?.call();
  }

  bool _onKey(KeyEvent event) {
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.backspace) {
      if (event is KeyDownEvent && mounted && _onTop) unawaited(Navigator.maybePop(context));
      return true;
    }
    return handleComputerKey(event, _onNote);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

// The note letter that picks a menu choice, in its color.
class KeyBadge extends StatelessWidget {
  const KeyBadge({super.key, required this.pc, this.size = 44});

  final int pc;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = Color(pitchClasses[pc].argb);
    final dark = color.computeLuminance() > 0.5;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: size * 0.06),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: size * 0.4)],
      ),
      child: Text(
        pitchClasses[pc].name,
        style: TextStyle(
          fontSize: size * 0.5,
          fontWeight: FontWeight.w900,
          color: dark ? const Color(0xFF2A2233) : Colors.white,
        ),
      ),
    );
  }
}
