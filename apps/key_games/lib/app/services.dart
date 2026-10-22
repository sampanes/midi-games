// What lives for the whole run and every screen needs: the synth, the MIDI
// keyboard, the key router and the settings. Screens read them with
// AppServices.of(context), so a page's constructor takes only what makes it
// different (a song, a difficulty).

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../audio/synth.dart';
import '../input/key_router.dart';
import '../midi/midi_input.dart';
import 'settings.dart';

class AppServices {
  AppServices({required this.synth, required this.midi, required this.settings})
      : router = KeyRouter(midi: midi, settings: settings, synth: synth);

  // Everything started, for the real app.
  static Future<AppServices> boot() async {
    final settings = await Settings.load();
    final services = AppServices(synth: Synth(), midi: MidiInput(), settings: settings);
    unawaited(services.synth.start());
    unawaited(services.midi.start());
    services.router.start();
    return services;
  }

  final Synth synth;
  final MidiInput midi;
  final Settings settings;
  final KeyRouter router;

  // True while a MIDI keyboard is connected. A widget that asks is rebuilt
  // when one connects or goes away.
  static bool hasKeyboard(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_KeyboardScope>()?.connected ?? false;

  static AppServices of(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<_ServicesScope>();
    assert(scope != null, 'No AppServices above this widget: wrap the tree in KeyGamesApp.');
    return scope!.services;
  }

  Widget provide({required Widget child}) => _ServicesScope(
        services: this,
        child: ValueListenableBuilder<List<String>>(
          valueListenable: midi.connected,
          builder: (context, names, child) =>
              _KeyboardScope(connected: names.isNotEmpty, child: child!),
          child: child,
        ),
      );

  void dispose() {
    router.dispose();
    midi.dispose();
  }
}

class _ServicesScope extends InheritedWidget {
  const _ServicesScope({required this.services, required super.child});

  final AppServices services;

  @override
  bool updateShouldNotify(_ServicesScope oldWidget) => oldWidget.services != services;
}

class _KeyboardScope extends InheritedWidget {
  const _KeyboardScope({required this.connected, required super.child});

  final bool connected;

  @override
  bool updateShouldNotify(_KeyboardScope oldWidget) => oldWidget.connected != connected;
}
