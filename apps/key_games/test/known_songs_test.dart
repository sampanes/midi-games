import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:key_games/app/settings.dart';
import 'package:key_games/songs/known_songs_page.dart';
import 'package:key_games/songs/song.dart';
import 'package:key_games/widgets/piano_strip.dart';

import 'helpers.dart';

const demo = Song('Test Song', [SongNote(61, 0, 300), SongNote(64, 300, 300)]);

void main() {
  testWidgets(
    'practice list distinguishes available songs and keeps additions',
    (tester) async {
      usePhone(tester);
      final services = await pumpApp(
        tester,
        const KnownSongsPage(songs: [demo]),
      );
      await services.settings.setKnownSongs(const [
        'Missing One',
        'Missing Two',
        'Test Song',
      ]);
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
      expect(find.byKey(const ValueKey('roll-note-61')), findsOneWidget);
      expect(find.byKey(const ValueKey('song-roll')), findsOneWidget);
    },
  );

  testWidgets(
    'guide shows the song in a scrollable roll without a playable keyboard',
    (tester) async {
      usePhone(tester);
      const longSong = Song('Roll', [
        SongNote(60, 0, 1000),
        SongNote(64, 0, 1000),
        SongNote(67, 60000, 1000),
      ]);
      await pumpApp(tester, const SongGuidePage(song: longSong));
      await tester.pump();
      expect(find.byKey(const ValueKey('roll-note-60')), findsOneWidget);
      expect(find.byKey(const ValueKey('roll-note-64')), findsOneWidget);
      expect(find.byKey(const ValueKey('roll-note-67')), findsOneWidget);
      expect(find.byType(PianoStrip), findsNothing);
      expect(find.text('Previous'), findsNothing);
      expect(find.text('Next'), findsNothing);
      final roll = find.byKey(const ValueKey('song-roll'));
      final before = tester.getTopLeft(roll).dy;
      await tester.drag(
        find.byKey(const ValueKey('song-roll-scroll')),
        const Offset(0, -400),
      );
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(roll).dy, lessThan(before));
      expect(
        find.byKey(const ValueKey('roll-note-60')),
        findsOneWidget,
      ); // Header stays visible.
    },
  );
  testWidgets('guide fits a landscape phone', (tester) async {
    usePhone(tester, landscape: true);
    await pumpApp(tester, const SongGuidePage(song: demo));
    await tester.pump();
    expect(find.byKey(const ValueKey('roll-note-61')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
