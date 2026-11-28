import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:key_games/midi/midi_input.dart';
import 'package:key_games/app/settings.dart';
import 'package:key_games/songs/known_songs_page.dart';
import 'package:key_games/songs/song.dart';

import 'helpers.dart';

const demo = Song('Test Song', [
  SongNote(61, 0, 300),
  SongNote(64, 300, 300),
]);

void main() {
  testWidgets(
    'practice list distinguishes available songs and keeps additions',
    (tester) async {
      usePhone(tester);
      final services = await pumpApp(
        tester,
        const KnownSongsPage(songs: [demo]),
      );
      await services.settings.setKnownSongs(const ['Missing One', 'Missing Two', 'Test Song']);
      await tester.pump();
      expect(find.text('Notes not added yet'), findsNWidgets(2));
      expect(find.text('Ready to practice'), findsOneWidget);
      await tester.tap(find.text('Add a song'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'My favorite');
      await tester.tap(find.text('Add').last);
      await tester.pumpAndSettle();
      expect(services.settings.knownSongs.value, contains('My favorite'));
      expect((await Settings.load()).knownSongs.value, contains('My favorite'));
      expect(find.text('My favorite'), findsOneWidget);
      await tester.tap(find.text('Test Song'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(SongGuidePage), findsOneWidget);
      expect(find.text('C#/Db 4'), findsOneWidget);
    },
  );

  testWidgets('guide advances only on the correct MIDI note and can go back', (
    tester,
  ) async {
    usePhone(tester);
    final synth = RecordingSynth();
    final services = await pumpApp(
      tester,
      const SongGuidePage(song: demo),
      synth: synth,
    );
    services.midi.feed(const NoteEvent(60, 90, on: true));
    await tester.pump();
    expect(find.text('C#/Db 4'), findsOneWidget);
    services.midi.feed(const NoteEvent(61, 90, on: true));
    await tester.pump();
    expect(find.text('E 4'), findsOneWidget);
    await tester.tap(find.text('Previous'));
    await tester.pump();
    expect(find.text('C#/Db 4'), findsOneWidget);
    await tester.tap(find.text('Hear note'));
    expect(synth.events, contains('blip 61'));
  });
  testWidgets('guide fits a landscape phone', (tester) async {
    usePhone(tester, landscape: true);
    await pumpApp(tester, const SongGuidePage(song: demo));
    await tester.pump();
    expect(find.text('C#/Db 4'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
