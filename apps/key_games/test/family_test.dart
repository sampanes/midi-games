// The things around the games that make a session easy: Free Play, the
// Again button, the sound settings, best scores on the level pickers, stars
// on the song cards, and "Next song" at the end of a song.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:key_games/app/settings.dart';
import 'package:key_games/app/theme.dart';
import 'package:key_games/games/difficulty.dart';
import 'package:key_games/games/free_play_page.dart';
import 'package:key_games/games/highway_page.dart';
import 'package:key_games/input/back_control.dart';
import 'package:key_games/input/key_router.dart';
import 'package:key_games/main.dart';
import 'package:key_games/settings/settings_page.dart';
import 'package:key_games/songs/song.dart';
import 'package:key_games/songs/song_list_page.dart';
import 'package:key_games/songs/song_listen_page.dart';
import 'package:key_games/songs/song_play_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';

// A key tap, then time for the page it opens to settle.
Future<void> _press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

Future<void> _back(WidgetTester tester) => _press(tester, LogicalKeyboardKey.escape);

int _goldStars(WidgetTester tester) => tester
    .widgetList<Icon>(find.byIcon(Icons.star_rounded))
    .where((icon) => icon.color == AppColors.starGold)
    .length;

void main() {
  test('a harder press sends a Free Play ball higher', () {
    expect(flightHeight(127), greaterThan(flightHeight(40)));
    expect(flightHeight(1), greaterThan(0.4));
    expect(flightHeight(127), lessThanOrEqualTo(0.9));
  });

  test('song steps stars: three for a clean walk, one for getting there', () {
    expect(stepsStars(0, 20), 3);
    expect(stepsStars(2, 20), 3);
    expect(stepsStars(5, 20), 2);
    expect(stepsStars(30, 20), 1);
    expect(stepsStars(0, 0), 0);
  });

  test('settings remember the sound, the band and the game played last', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = await Settings.load();
    expect(settings.keySound.value, KeySound.piano);
    expect(settings.bandLevel.value, BandLevel.full);
    expect(settings.lastGame.value, isNull);

    settings
      ..setKeySound(KeySound.organ)
      ..setBandLevel(BandLevel.off)
      ..setLastGame(const LastGame('highway', 1, 'Canon in D'));
    final again = await Settings.load();
    expect(again.keySound.value, KeySound.organ);
    expect(again.bandLevel.value, BandLevel.off);
    expect(again.lastGame.value, const LastGame('highway', 1, 'Canon in D'));

    // A game without a song forgets the last song.
    again.setLastGame(const LastGame('rush', 0));
    expect((await Settings.load()).lastGame.value, const LastGame('rush', 0));
  });

  testWidgets('free play: every key sounds, nothing can go wrong', (tester) async {
    usePhone(tester, landscape: true);
    final synth = RecordingSynth();
    await pumpApp(tester, const FreePlayPage(), synth: synth);
    expect(find.text('Press any key!'), findsOneWidget);

    for (final key in [LogicalKeyboardKey.keyA, LogicalKeyboardKey.keyD, LogicalKeyboardKey.keyK]) {
      await tester.sendKeyDownEvent(key);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.sendKeyUpEvent(key);
      await tester.pump(const Duration(milliseconds: 60));
    }
    expect(synth.events, containsAllInOrder(['on 60', 'off 60', 'on 64', 'off 64', 'on 72']));
    expect(tester.takeException(), isNull);

    // The balls fly, burst and are gone, and fly again after a rest.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(seconds: 2));
    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 100));
    expect(synth.events.last, 'off 67');
    expect(tester.takeException(), isNull);

    // Left the moment it opens, before a sound: nothing goes wrong either.
    await tester.pumpWidget(const SizedBox());
    await pumpApp(tester, const FreePlayPage());
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('home: A is Free Play, and then B plays it again', (tester) async {
    usePhone(tester, landscape: true);
    final services = await pumpApp(tester, null);
    await tester.pump(keySettle);
    expect(find.text('Again'), findsNothing);

    await _press(tester, LogicalKeyboardKey.keyH); // A: Free Play, no levels
    expect(find.byType(FreePlayPage), findsOneWidget);
    expect(services.settings.lastGame.value, const LastGame('free', 0));

    await _back(tester);
    expect(find.byType(FreePlayPage), findsNothing);
    expect(find.text('Again'), findsOneWidget);
    expect(find.byType(BackButton), findsNothing);
    expect(find.textContaining('B plays Free Play again.'), findsOneWidget);
    // Settings keeps its key, a black one, whether or not there is a game
    // to play again.
    expect(find.textContaining('F# (Settings)'), findsOneWidget);

    await _press(tester, LogicalKeyboardKey.keyJ); // B: again
    expect(find.byType(FreePlayPage), findsOneWidget);
  });

  testWidgets('home changed while a page covers it grows no back button', (tester) async {
    usePhone(tester, landscape: true);
    final services = await pumpApp(tester, null);
    await tester.pump(keySettle);
    await _press(tester, LogicalKeyboardKey.keyT); // F#: Settings
    expect(find.byType(SettingsPage), findsOneWidget);

    // The home menu shows the Back pad too, so it is rebuilt under Settings.
    await services.settings.setBackControl(const BackControl(ControlKind.note, 9, 36));
    await tester.pump();
    await _back(tester);
    expect(find.text('Free Play'), findsOneWidget);
    expect(find.byType(BackButton), findsNothing);
  });

  testWidgets('home: Again opens the last game at its level', (tester) async {
    usePhone(tester, landscape: true);
    final services = await pumpApp(tester, null);
    services.settings.setLastGame(LastGame('ear', Difficulty.hard.index));
    await tester.pump(keySettle);
    expect(find.textContaining('B plays Ear Notes again.'), findsOneWidget);

    await _press(tester, LogicalKeyboardKey.keyJ);
    expect(find.text('Level 4'), findsOneWidget); // Ear Notes on Hard

    // Left before its first note: the page closes cleanly.
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings: F changes the key sound and G the band', (tester) async {
    usePhone(tester, landscape: true);
    final synth = RecordingSynth();
    final services = await pumpApp(tester, const SettingsPage(), synth: synth);
    await tester.pump(keySettle);
    expect(synth.struck, isTrue);
    expect(find.text('Now Toy piano. Press to change'), findsOneWidget);

    await _press(tester, LogicalKeyboardKey.keyF);
    expect(services.settings.keySound.value, KeySound.organ);
    expect(synth.struck, isFalse);
    expect(find.text('Now Organ. Press to change'), findsOneWidget);
    // A few notes to hear the change.
    expect(synth.events, contains('tune 60,64,67,72'));

    await _press(tester, LogicalKeyboardKey.keyG);
    expect(services.settings.bandLevel.value, BandLevel.soft);
    expect(synth.bandGain, 0.5);
    await _press(tester, LogicalKeyboardKey.keyG);
    expect(synth.bandGain, 0);
    expect(find.textContaining('Now Off.'), findsOneWidget);
    await _press(tester, LogicalKeyboardKey.keyG);
    expect(services.settings.bandLevel.value, BandLevel.full);
  });

  testWidgets('a level with a best score wears it', (tester) async {
    useTv(tester);
    final services = await pumpApp(tester, null);
    services.settings.recordBest('rush.zones', 42);
    await tester.pump(keySettle);

    await _press(tester, LogicalKeyboardKey.keyG); // G: Arcade
    await _press(tester, LogicalKeyboardKey.keyA); // C: Key Rush, its levels
    expect(find.text('42'), findsOneWidget);
    // On Easy's tile, not on the others.
    final badge = tester.getCenter(find.text('42'));
    expect(badge.dx, lessThan(tester.getCenter(find.text('Medium')).dx));
  });

  testWidgets('song cards show the stars won, and a group how many of its stars', (tester) async {
    usePhone(tester, landscape: true);
    const notes = [SongNote(60, 0, 300)];
    const songs = [
      Song('Lullaby Test', notes, group: 'Kids'),
      Song('Rhyme Test', notes, group: 'Kids'),
      Song('March Test', notes, group: 'Classical'),
    ];
    String key(Song song) => highwayStarsKey(Difficulty.easy, song);
    final services = await testServices();
    services.settings
      ..recordBest(key(songs[0]), 2)
      ..recordBest(key(songs[1]), 3);
    await tester.pumpWidget(
      KeyGamesApp(services: services, home: SongListPage(songs: songs, starsKey: key)),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('5/6'), findsOneWidget); // Kids
    expect(find.text('0/3'), findsOneWidget); // Classical

    await _press(tester, LogicalKeyboardKey.keyA); // C: Kids
    expect(find.text('Rhyme Test'), findsOneWidget);
    expect(_goldStars(tester), 5);

    // A list without stars shows none.
    await tester.pumpWidget(const SizedBox());
    await pumpApp(tester, const SongListPage(songs: songs, group: 'Kids'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byIcon(Icons.star_rounded), findsNothing);
  });

  testWidgets('F at the end of a song plays the next one of the list', (tester) async {
    usePhone(tester, landscape: true);
    const songs = [
      Song('Lullaby Test', [SongNote(60, 0, 300)], group: 'Kids'),
      Song('Rhyme Test', [SongNote(64, 0, 300)], group: 'Kids'),
    ];
    final opened = <String>[];
    await pumpApp(
      tester,
      SongListPage(
        songs: songs,
        title: 'Song Box',
        levels: false,
        play: (song) => SongListenPage(song: song),
        onOpen: (song) => opened.add(song.title),
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    await _press(tester, LogicalKeyboardKey.keyA); // C: the first song
    expect(find.text('Next song'), findsOneWidget);
    expect(find.text('Kids, 1 notes'), findsOneWidget);

    await _press(tester, LogicalKeyboardKey.keyF); // F: the next song
    expect(find.byType(SongListenPage), findsOneWidget);
    expect(tester.widget<SongListenPage>(find.byType(SongListenPage)).song.title, 'Rhyme Test');

    // After the last song comes the first; Back is the list, not the song before.
    await _press(tester, LogicalKeyboardKey.keyF);
    expect(tester.widget<SongListenPage>(find.byType(SongListenPage)).song.title, 'Lullaby Test');
    expect(opened, ['Lullaby Test', 'Rhyme Test', 'Lullaby Test']);
    await _back(tester);
    expect(find.byType(SongListenPage), findsNothing);
    expect(find.text('Song Box: All songs'), findsOneWidget);
  });

  testWidgets('a song list opens a song by itself when asked (Again)', (tester) async {
    usePhone(tester, landscape: true);
    const notes = [SongNote(60, 0, 300)];
    const songs = [
      Song('Lullaby Test', notes, group: 'Kids'),
      Song('March Test', notes, group: 'Classical'),
    ];
    await pumpApp(
      tester,
      SongListPage(
        songs: songs,
        levels: false,
        play: (song) => SongListenPage(song: song),
        autoOpen: 'March Test',
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(tester.widget<SongListenPage>(find.byType(SongListenPage)).song.title, 'March Test');

    // Back is its group, then the groups.
    await _back(tester);
    expect(find.text('Songs: Classical'), findsOneWidget);
    await _back(tester);
    expect(find.text('Kids'), findsOneWidget);
  });

  testWidgets('song steps: the end shows stars and keeps the most won', (tester) async {
    usePhone(tester, landscape: true);
    const song = Song('Two Notes', [SongNote(60, 0, 300), SongNote(64, 400, 300)]);
    final services = await pumpApp(tester, const SongPlayPage(song: song));
    await tester.pump(const Duration(seconds: 1));

    for (final key in [LogicalKeyboardKey.keyA, LogicalKeyboardKey.keyD]) {
      await tester.sendKeyDownEvent(key);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.sendKeyUpEvent(key);
      await tester.pump(const Duration(milliseconds: 300));
    }
    // The celebration, then the song plays back, then the end panel.
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('You played Two Notes!'), findsOneWidget);
    expect(_goldStars(tester), 3);
    expect(services.settings.best(stepsStarsKey(Difficulty.easy, song)), 3);
    // Opened on its own, not from a list: no next song.
    expect(find.textContaining('Next:'), findsNothing);
  });
}
