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

  void _onNote(NoteEvent event) {
    final backControl = settings.backControl.value;
    if (backControl != null && backControl.matchesNote(event)) {
      if (event.on) back();
      return;
    }
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
    final backControl = settings.backControl.value;
    if (backControl != null && backControl.matchesButton(event) && event.value > 0) back();
  }

  bool _onKey(KeyEvent event) {
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.backspace) {
      if (event is KeyDownEvent) back();
      return true;
    }
    return handleComputerKey(event, _onNote);
  }
}
