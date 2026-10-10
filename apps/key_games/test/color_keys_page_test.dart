import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:key_games/audio/synth.dart';
import 'package:key_games/games/color_keys_page.dart';
import 'package:key_games/games/color_keys_rules.dart';
import 'package:key_games/midi/midi_input.dart';

class _RecordingSynth extends Synth {
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

class _TestMidiInput extends MidiInput {
  final StreamController<NoteEvent> _events =
      StreamController<NoteEvent>.broadcast(sync: true);

  @override
  Stream<NoteEvent> get notes => _events.stream;

  void send(int note, {required bool on, int velocity = 100}) {
    _events.add(NoteEvent(note, velocity, on: on));
  }

  @override
  void dispose() {
    unawaited(_events.close());
    super.dispose();
  }
}

final _computerNotes = {
  LogicalKeyboardKey.keyA: 60,
  LogicalKeyboardKey.keyS: 62,
  LogicalKeyboardKey.keyD: 64,
  LogicalKeyboardKey.keyF: 65,
  LogicalKeyboardKey.keyG: 67,
  LogicalKeyboardKey.keyH: 69,
  LogicalKeyboardKey.keyJ: 71,
};

void main() {
  Future<void> showGame(
    WidgetTester tester,
    _RecordingSynth synth,
    int seed, [
    MidiInput? midi,
  ]) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ColorKeysPage(
          synth: synth,
          midi: midi ?? MidiInput(),
          random: Random(seed),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('a wrong key sounds once, followed only by the right key', (
    tester,
  ) async {
    const seed = 11;
    final target = pickNextTarget(null, Random(seed), whitePitchClasses);
    final wrong = _computerNotes.entries.firstWhere(
      (entry) => pitchClass(entry.value) != target,
    );
    final synth = _RecordingSynth();
    await showGame(tester, synth, seed);

    await tester.sendKeyDownEvent(wrong.key);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.sendKeyUpEvent(wrong.key);
    await tester.pump(const Duration(milliseconds: 151));

    final right = nearestOfClassInRange(wrong.value, target, 48, 84);
    expect(
      synth.events.where((event) => event == 'on ${wrong.value}'),
      hasLength(1),
    );
    expect(synth.events.where((event) => event == 'on $right'), hasLength(1));

    // Wait past the legacy echo timings to prove no delayed replay of the
    // wrong note was left queued.
    await tester.pump(const Duration(milliseconds: 1000));
    expect(
      synth.events.where((event) => event == 'on ${wrong.value}'),
      hasLength(1),
    );
    expect(
      synth.events.where((event) => event == 'blip ${wrong.value}'),
      isEmpty,
    );

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('two nearby presses are a miss and replay the target solo', (
    tester,
  ) async {
    const seed = 17;
    final target = pickNextTarget(null, Random(seed), whitePitchClasses);
    final right = _computerNotes.entries.firstWhere(
      (entry) => pitchClass(entry.value) == target,
    );
    final wrong = _computerNotes.entries.firstWhere(
      (entry) => pitchClass(entry.value) != target,
    );
    final synth = _RecordingSynth();
    await showGame(tester, synth, seed);

    // Correct first would score immediately without the 250 ms chord gate.
    await tester.sendKeyDownEvent(right.key);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.sendKeyDownEvent(wrong.key);
    await tester.pump();

    expect(synth.events.where((event) => event.startsWith('tune ')), isEmpty);
    expect(synth.sounding, {right.value});

    await tester.sendKeyUpEvent(right.key);
    await tester.sendKeyUpEvent(wrong.key);
    await tester.pump(const Duration(milliseconds: 599));
    expect(synth.sounding, {right.value});
    await tester.pump(const Duration(milliseconds: 1));
    expect(synth.sounding, isEmpty);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a single target is judged only after the chord window', (
    tester,
  ) async {
    const seed = 23;
    final target = pickNextTarget(null, Random(seed), whitePitchClasses);
    final right = _computerNotes.entries.firstWhere(
      (entry) => pitchClass(entry.value) == target,
    );
    final synth = _RecordingSynth();
    await showGame(tester, synth, seed);

    await tester.sendKeyDownEvent(right.key);
    await tester.pump(const Duration(milliseconds: 249));
    expect(synth.events.where((event) => event.startsWith('tune ')), isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    expect(
      synth.events.where((event) => event.startsWith('tune ')),
      hasLength(1),
    );

    await tester.sendKeyUpEvent(right.key);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a low-layout correction stays in the playable synth range', (
    tester,
  ) async {
    const seed = 31;
    final target = pickNextTarget(null, Random(seed), whitePitchClasses);
    final wrong = [for (var note = minGameNote; note < 24; note++) note]
        .firstWhere((note) => pitchClass(note) != target);
    final synth = _RecordingSynth();
    final midi = _TestMidiInput();
    await showGame(tester, synth, seed, midi);

    midi.send(wrong, on: true);
    await tester.pump(const Duration(milliseconds: 100));
    midi.send(wrong, on: false, velocity: 0);
    await tester.pump(const Duration(milliseconds: 150));

    final right = nearestOfClassInRange(wrong, target, Synth.lowestNote, 48);
    expect(right, greaterThanOrEqualTo(Synth.lowestNote));
    expect(synth.events, contains('on $right'));

    await tester.pumpWidget(const SizedBox());
    midi.dispose();
  });

  testWidgets('an active target hint is cut before an answer starts', (
    tester,
  ) async {
    const seed = 41;
    final target = pickNextTarget(null, Random(seed), whitePitchClasses);
    final hint = 72 + target;
    final wrong = _computerNotes.entries.firstWhere(
      (entry) => pitchClass(entry.value) != target,
    );
    final synth = _RecordingSynth();
    await showGame(tester, synth, seed);

    await tester.pump(const Duration(milliseconds: 1200));
    expect(synth.sounding, {hint});
    await tester.pump(const Duration(milliseconds: 400));
    expect(synth.sounding, isEmpty);

    await tester.sendKeyDownEvent(wrong.key);
    await tester.pump();
    expect(synth.events, contains('cut $hint'));
    expect(synth.sounding, {wrong.value});

    await tester.pump(const Duration(milliseconds: 250));
    final right = nearestOfClassInRange(wrong.value, target, 48, 84);
    expect(synth.sounding, {right});

    await tester.sendKeyUpEvent(wrong.key);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a missing chord release cannot leave the game latched', (
    tester,
  ) async {
    const seed = 37;
    final target = pickNextTarget(null, Random(seed), whitePitchClasses);
    final targetNote = 60 + target;
    final wrong = [for (var note = 60; note < 72; note++) note]
        .firstWhere((note) => pitchClass(note) != target);
    final later = [for (var note = 60; note < 72; note++) note]
        .firstWhere((note) => note != targetNote && note != wrong);
    final synth = _RecordingSynth();
    final midi = _TestMidiInput();
    await showGame(tester, synth, seed, midi);

    midi.send(targetNote, on: true);
    await tester.pump(const Duration(milliseconds: 100));
    midi.send(wrong, on: true);
    await tester.pump(const Duration(seconds: 1));

    midi.send(later, on: true);
    await tester.pump();
    expect(synth.events, contains('on $later'));

    midi.send(later, on: false, velocity: 0);
    await tester.pumpWidget(const SizedBox());
    midi.dispose();
  });
}
