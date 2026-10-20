// Shared test setup: the app's services with a silent synth, no MIDI
// devices, nothing remembered, and the key router listening.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:key_games/app/services.dart';
import 'package:key_games/app/settings.dart';
import 'package:key_games/audio/synth.dart';
import 'package:key_games/main.dart';
import 'package:key_games/midi/midi_input.dart';
import 'package:shared_preferences/shared_preferences.dart';

// A synth that writes down what it was asked to play instead of sounding.
class RecordingSynth extends Synth {
  final List<String> events = [];
  final Set<int> sounding = {};

  @override
  void noteOn(int note, int velocity) {
    events.add('on $note');
    sounding.add(note);
  }

  @override
  void noteOff(int note) {
    events.add('off $note');
    sounding.remove(note);
  }

  @override
  void noteOffNow(int note) {
    events.add('cut $note');
    sounding.remove(note);
  }

  @override
  void blip(int note, {int velocity = 90, int lengthMs = 160}) {
    events.add('blip $note');
  }

  @override
  void tune(List<int> notes, {int stepMs = 110, int lengthMs = 220}) {
    events.add('tune ${notes.join(',')}');
  }
}

// Services for one test. The synth is never started, so it stays silent;
// the MIDI input never starts looking for devices, and notes are fed to it
// with MidiInput.feed. Disposed when the test ends.
Future<AppServices> testServices({Synth? synth, MidiInput? midi}) async {
  SharedPreferences.setMockInitialValues({});
  final services = AppServices(
    synth: synth ?? Synth(),
    midi: midi ?? MidiInput(),
    settings: await Settings.load(),
  );
  services.router.start();
  addTearDown(services.dispose);
  return services;
}

// Pumps [home] (the home menu when null) inside the real app shell. The
// router ignores menu picks for keySettle after a page appears, so a test
// that presses a letter straight away pumps that long first.
Future<AppServices> pumpApp(
  WidgetTester tester,
  Widget? home, {
  Synth? synth,
  MidiInput? midi,
  double textScale = 1,
}) async {
  final services = await testServices(synth: synth, midi: midi);
  await tester.pumpWidget(KeyGamesApp(
    services: services,
    home: home,
    builder: textScale == 1
        ? null
        : (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
  ));
  await tester.pump();
  return services;
}

// A phone held upright, or on its side.
void usePhone(WidgetTester tester, {bool landscape = false}) {
  tester.view.physicalSize = landscape ? const Size(2316, 1080) : const Size(1080, 2316);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
}
