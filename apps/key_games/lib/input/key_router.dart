// One owner of every key the player presses: notes from the MIDI keyboard,
// the computer keys A to K, Escape and Backspace, and the Back control (a
// pad or button picked in Settings). Pages register a [KeyHandler] through
// NoteFocus; only the handler of the page on top of the Navigator gets
// notes, so a key pressed on one page can never act on another.
//
// Picks (menu letters, the end-of-game keys) wait out a short settle after
// every page change, so the key that opened a page does not also pick
// something on it. Game notes are not delayed. The Back control is swallowed
// here and never reaches a game.
//
// Until a Back control is picked, any pad goes back. A pad is a note on
// another channel than the keys: the keys' channel is the channel of the
// last note above [highestPadNote], which only a key can play (pads send
// notes 36-51; keys and pads usually sit on different channels). Until a
// key has been played, or when keys and pads share a channel, no note is a
// pad.

import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/settings.dart';
import '../audio/synth.dart';
import '../games/color_keys_rules.dart';
import '../midi/computer_keys.dart';
import '../midi/midi_input.dart';

const keySettle = Duration(milliseconds: 600);

// The highest note a pad sends; any note above it is a key.
const highestPadNote = 51;

class KeyHandler {
  KeyHandler({this.route, this.picks = const {}, this.onNote});

  ModalRoute<Object?>? route;

  // Pitch class (0-11) -> what pressing any key of that letter does.
  Map<int, VoidCallback> picks;

  // Every other note, on and off, for a game to play.
  void Function(NoteEvent event)? onNote;

  bool get isCurrent => route?.isCurrent ?? true;
}

class KeyRouter extends NavigatorObserver {
  KeyRouter({required this.midi, required this.settings, this.synth, this.settle = keySettle});

  final MidiInput midi;
  final Settings settings;

  // Sounds a short blip for each pick; null for silent picks.
  final Synth? synth;
  final Duration settle;

  final List<KeyHandler> _handlers = [];
  StreamSubscription<NoteEvent>? _noteSub;
  StreamSubscription<ButtonEvent>? _buttonSub;

  // When the page on top last changed; picks wait out [settle] after it.
  DateTime _changedAt = clock.now();

  // The MIDI channel the keys play on; null until a key above the pads.
  int? _keyChannel;

  // True while the Back control is being picked: that page reads the MIDI
  // notes itself, so none of them go back or reach a page here.
  bool learning = false;

  void start() {
    _noteSub = midi.notes.listen(_onNote);
    _buttonSub = midi.buttons.listen(_onButton);
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    unawaited(_noteSub?.cancel());
    unawaited(_buttonSub?.cancel());
  }

  void attach(KeyHandler handler) {
    _handlers.add(handler);
    _pageChanged();
  }

  void detach(KeyHandler handler) => _handlers.remove(handler);

  // The handler of the page on top, or null while nothing is listening.
  KeyHandler? get top {
    for (final handler in _handlers.reversed) {
      if (handler.isCurrent) return handler;
    }
    return null;
  }

  bool get settling => clock.now().difference(_changedAt) < settle;

  void _pageChanged() => _changedAt = clock.now();

  // Leaves the page on top, as the on-screen back button would.
  void back() => unawaited(navigator?.maybePop());

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => _pageChanged();

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _pageChanged();

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) => _pageChanged();

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) => _pageChanged();

  // A note from the MIDI keyboard.
  void _onNote(NoteEvent event) {
    if (event.note > highestPadNote) _keyChannel = event.channel;
    if (learning) return;
    final backControl = settings.backControl.value;
    final goesBack = backControl != null
        ? backControl.matchesNote(event)
        : _keyChannel != null && event.channel != _keyChannel;
    if (goesBack) {
      if (event.on) back();
      return;
    }
    _route(event);
  }

  // A note for the page on top: a pick, or a note for its game.
  void _route(NoteEvent event) {
    if (!isGameNote(event.note)) return;
    final handler = top;
    if (handler == null) return;
    if (event.on) {
      final pick = handler.picks[pitchClass(event.note)];
      if (pick != null) {
        if (settling) return;
        synth?.blip(event.note, velocity: 80, lengthMs: 140);
        pick();
        return;
      }
    }
    handler.onNote?.call(event);
  }

  void _onButton(ButtonEvent event) {
    if (learning) return;
    final backControl = settings.backControl.value;
    if (backControl != null && backControl.matchesButton(event) && event.value > 0) back();
  }

  bool _onKey(KeyEvent event) {
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.backspace) {
      if (event is KeyDownEvent) back();
      return true;
    }
    // Computer keys are keys, never pads.
    return handleComputerKey(event, _route);
  }
}
