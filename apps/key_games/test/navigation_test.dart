import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:key_games/games/color_keys_rules.dart';
import 'package:key_games/input/back_control.dart';
import 'package:key_games/input/key_router.dart';
import 'package:key_games/midi/midi_input.dart';
import 'package:key_games/settings/settings_page.dart';
import 'package:key_games/songs/song.dart';
import 'package:key_games/songs/song_list_page.dart';
import 'package:key_games/songs/song_listen_page.dart';

import 'helpers.dart';

// A key tap, then time for the page it opens to settle.
Future<void> _press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  test('nearest note of a letter, for comparing a miss with the answer', () {
    expect(nearestOfClass(64, 0), 60); // E -> the C below
    expect(nearestOfClass(69, 0), 72); // A -> the C above
    expect(nearestOfClass(66, 0), 72); // F#: tie goes up
    expect(nearestOfClass(60, 0), 60);
    expect(nearestOfClass(50, 11), 47);
  });

  test('song pages use seven letters, or six plus B for the next page', () {
    expect(songsPerPage(3), 7);
    expect(songsPerPage(7), 7);
    expect(songsPerPage(8), 6);
  });

  testWidgets('menus pick by note letter, all the way into a game, and Escape backs out',
      (tester) async {
    usePhone(tester);
    await pumpApp(tester, null);
    await tester.pump(keySettle);
    expect(find.text('Listen'), findsOneWidget);

    await _press(tester, LogicalKeyboardKey.keyS); // D: Listen
    expect(find.text('Ear Notes'), findsOneWidget);
    await _press(tester, LogicalKeyboardKey.keyA); // C: Ear Notes
    expect(find.text('Expert'), findsOneWidget);
    await _press(tester, LogicalKeyboardKey.keyD); // E: Hard
    expect(find.text('Level 4'), findsOneWidget);

    // The difficulty picker was replaced by the game, so back is the menu.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Level 4'), findsNothing);
    expect(find.text('Ear Notes'), findsOneWidget);
  });

  testWidgets('two Cs pressed together on the home menu open one page, not two', (tester) async {
    usePhone(tester);
    final services = await pumpApp(tester, null);
    await tester.pump(keySettle);

    // Low C opens Look; the high C that lands a moment later must not then
    // pick Color Keys on the page that just opened.
    services.midi.feed(const NoteEvent(48, 100, on: true));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    services.midi.feed(const NoteEvent(84, 100, on: true));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    services.midi.feed(const NoteEvent(48, 0, on: false));
    services.midi.feed(const NoteEvent(84, 0, on: false));
    await tester.pump();

    expect(find.text('Color Keys'), findsOneWidget); // the Look menu
    expect(find.text('Easy'), findsNothing); // not its difficulty picker
  });

  testWidgets('the Back pad leaves a game and never sounds in it', (tester) async {
    usePhone(tester);
    final synth = RecordingSynth();
    final services = await pumpApp(tester, null, synth: synth);
    await services.settings.setBackControl(const BackControl(ControlKind.note, 9, 36));
    await tester.pump(keySettle);

    await _press(tester, LogicalKeyboardKey.keyS); // D: Listen
    await _press(tester, LogicalKeyboardKey.keyA); // C: Ear Notes
    await _press(tester, LogicalKeyboardKey.keyA); // C: Easy
    expect(find.text('Level 1'), findsOneWidget);

    services.midi.feed(const NoteEvent(36, 100, on: true, channel: 9));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    services.midi.feed(const NoteEvent(36, 0, on: false, channel: 9));
    await tester.pump();
    expect(find.text('Level 1'), findsNothing);
    expect(find.text('Ear Notes'), findsOneWidget);
    expect(synth.events, isNot(contains('on 36')));

    // The same note on another channel is just a key.
    expect(const BackControl(ControlKind.note, 9, 36).matchesNote(const NoteEvent(36, 100, on: true)),
        isFalse);
  });

  testWidgets('settings learn the next pad pressed as the Back pad', (tester) async {
    usePhone(tester, landscape: true);
    final services = await pumpApp(tester, null);
    await tester.pump(keySettle);

    await _press(tester, LogicalKeyboardKey.keyG); // G: Settings
    expect(find.byType(SettingsPage), findsOneWidget);
    expect(find.text('No Back pad yet: the screen and the remote go back.'), findsOneWidget);

    await _press(tester, LogicalKeyboardKey.keyA); // C: Back pad
    expect(find.text('Press the pad or button you want to use for Back.'), findsOneWidget);

    services.midi.feed(const NoteEvent(40, 100, on: true, channel: 9));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Back is now Pad 40 (channel 10).'), findsOneWidget);
    expect(services.settings.backControl.value, const BackControl(ControlKind.note, 9, 40));

    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Back is Pad 40 (channel 10).'), findsOneWidget);

    // Now that pad goes back from Settings to the home menu.
    services.midi.feed(const NoteEvent(40, 100, on: true, channel: 9));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Forget it'), findsNothing);
    expect(find.text('Look'), findsOneWidget);
  });

  testWidgets('song list lays out on a phone, with or without local songs', (tester) async {
    usePhone(tester);
    await pumpApp(tester, const SongListPage());
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(SongListPage), findsOneWidget);
  });

  testWidgets('songs in groups: pick a group by letter, then its songs; Escape goes back',
      (tester) async {
    usePhone(tester, landscape: true);
    const notes = [SongNote(60, 0, 300)];
    const songs = [
      Song('Lullaby Test', notes, group: 'Kids'),
      Song('Rhyme Test', notes, group: 'Kids'),
      Song('March Test', notes, group: 'Classical'),
    ];
    await pumpApp(tester, const SongListPage(songs: songs));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Kids'), findsOneWidget);
    expect(find.text('Classical'), findsOneWidget);
    expect(find.text('March Test'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyS); // D: the second group
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('March Test'), findsOneWidget);
    expect(find.text('Lullaby Test'), findsNothing);
    expect(find.text('Songs: Classical'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Classical'), findsOneWidget);
    expect(find.text('March Test'), findsNothing);
  });

  testWidgets('song box: a picked song plays, C plays it again, Escape goes back', (tester) async {
    usePhone(tester, landscape: true);
    const songs = [
      Song('Lullaby Test', [SongNote(60, 0, 300), SongNote(64, 400, 300)], group: 'Kids'),
    ];
    await pumpApp(
      tester,
      SongListPage(
        songs: songs,
        title: 'Song Box',
        levels: false,
        play: (song) => SongListenPage(song: song),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Song Box: All songs'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyA); // C: the first song
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(SongListenPage), findsOneWidget);
    expect(find.text('Play again'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2)); // the song ends
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA); // C: again
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('0:00 / 0:00'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(SongListenPage), findsNothing);
    expect(find.text('Lullaby Test'), findsOneWidget);
  });
}
