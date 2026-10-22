// Shared test setup: the app's services with a silent synth, no MIDI
// devices, nothing remembered, and the key router listening.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:key_games/app/services.dart';
import 'package:key_games/app/settings.dart';
import 'package:key_games/audio/synth.dart';
import 'package:key_games/main.dart';
import 'package:key_games/midi/midi_input.dart';
import 'package:key_games/widgets/piano_strip.dart';
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
// with MidiInput.feed. It reports a keyboard connected unless [keyboard] is
// false (a phone on its own, where the picture is one octave of big keys).
// Disposed when the test ends.
Future<AppServices> testServices({Synth? synth, MidiInput? midi, bool keyboard = true}) async {
  SharedPreferences.setMockInitialValues({});
  final services = AppServices(
    synth: synth ?? Synth(),
    midi: midi ?? MidiInput(),
    settings: await Settings.load(),
  );
  if (keyboard) services.midi.connected.value = const ['Test keyboard'];
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
  bool keyboard = true,
  double textScale = 1,
}) async {
  final services = await testServices(synth: synth, midi: midi, keyboard: keyboard);
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

// A 1080p screen at 1:1: a full-screen PC, or a 4K TV at 2x.
void useTv(WidgetTester tester) {
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

// Key Rush Easy waits for the first right key before its minute starts. Its
// keys are the low, middle and high part of the keyboard, and the computer
// keys all sit in the middle one, so this touches the keyboard picture once
// in each part, low to high: one of them is the part asked for.
Future<void> startRushClock(WidgetTester tester) async {
  final strip = tester.getRect(find.byType(PianoStrip));
  for (final x in [1 / 6, 1 / 2, 5 / 6]) {
    await tester.tapAt(Offset(strip.left + strip.width * x, strip.bottom - 10));
    await tester.pump(const Duration(milliseconds: 50));
  }
}
