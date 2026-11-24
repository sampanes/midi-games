import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:key_games/games/free_play_page.dart';
import 'package:key_games/input/key_router.dart';
import 'package:key_games/midi/midi_input.dart';
import 'package:key_games/songs/song.dart';
import 'package:key_games/songs/song_list_page.dart';

import 'helpers.dart';

Future<void> tapMidi(WidgetTester tester, MidiInput midi, int note) async {
  midi.feed(NoteEvent(note, 100, on: true));
  await tester.pump();
  midi.feed(NoteEvent(note, 0, on: false));
  await tester.pump();
}

void main() {
  testWidgets('black keys cycle and select menu choices', (tester) async {
    usePhone(tester);
    final services = await pumpApp(tester, null);
    await tester.pump(keySettle);
    expect(find.textContaining('Selected: Look'), findsOneWidget);
    await tapMidi(tester, services.midi, 61); // C# moves to Listen.
    expect(find.textContaining('Selected: Listen'), findsOneWidget);
    await tapMidi(tester, services.midi, 61); // And on to Memory.
    expect(find.textContaining('Selected: Memory'), findsOneWidget);
    await tapMidi(tester, services.midi, 70); // A# selects Memory.
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Song Memory'), findsOneWidget);
    expect(find.textContaining('Selected: Copy Cat'), findsOneWidget);
  });

  testWidgets('black keys choose a song and its next page', (tester) async {
    usePhone(tester);
    final songs = List.generate(
      8,
      (i) => Song('Song $i', const [SongNote(60, 0, 300)]),
    );
    final services = await pumpApp(tester, SongListPage(songs: songs));
    await tester.pump(keySettle);
    for (var i = 0; i < 6; i++) {
      await tapMidi(tester, services.midi, 61);
    }
    expect(find.textContaining('Selected: Next page'), findsOneWidget);
    await tapMidi(tester, services.midi, 70);
    expect(find.text('Song 6'), findsOneWidget);
    expect(find.text('Song 7'), findsOneWidget);
  });

  testWidgets('black keys still sound during free play', (tester) async {
    usePhone(tester);
    final synth = RecordingSynth();
    final services = await pumpApp(tester, const FreePlayPage(), synth: synth);
    await tester.pump(keySettle);
    await tapMidi(tester, services.midi, 61);
    await tapMidi(tester, services.midi, 70);
    expect(synth.events, containsAll(['on 61', 'off 61', 'on 70', 'off 70']));
    expect(find.byKey(const ValueKey('navigation-hint')), findsNothing);
  });
}
