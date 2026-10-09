import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:key_games/audio/synth.dart';
import 'package:key_games/games/color_keys_rules.dart';
import 'package:key_games/home_page.dart';
import 'package:key_games/midi/midi_input.dart';
import 'package:key_games/songs/song.dart';
import 'package:key_games/songs/song_list_page.dart';
import 'package:key_games/widgets/key_nav.dart';

void main() {
  test('back chord is two Cs three octaves apart, in either order', () {
    expect(isBackChord({48}, 84), isTrue);
    expect(isBackChord({84}, 48), isTrue);
    expect(isBackChord({60}, 96), isTrue); // octave buttons moved
    expect(isBackChord({48}, 72), isFalse);
    expect(isBackChord({50}, 86), isFalse);
    expect(isBackChord({}, 48), isFalse);
  });

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
    tester.view.physicalSize = const Size(1080, 2316);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);

    Future<void> press(LogicalKeyboardKey key) async {
      await tester.sendKeyEvent(key);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    }

    await tester.pumpWidget(MaterialApp(home: HomePage(synth: Synth(), midi: MidiInput())));
    await tester.pump();
    expect(find.text('Listen'), findsOneWidget);

    await press(LogicalKeyboardKey.keyS); // D: Listen
    expect(find.text('Ear Notes'), findsOneWidget);
    await press(LogicalKeyboardKey.keyA); // C: Ear Notes
    expect(find.text('Expert'), findsOneWidget);
    await press(LogicalKeyboardKey.keyD); // E: Hard
    expect(find.text('Level 4'), findsOneWidget);

    // The difficulty picker was replaced by the game, so back is the menu.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Level 4'), findsNothing);
    expect(find.text('Ear Notes'), findsOneWidget);
  });

  testWidgets('song list lays out on a phone, with or without local songs', (tester) async {
    tester.view.physicalSize = const Size(1080, 2316);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: SongListPage(synth: Synth(), midi: MidiInput())));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(KeyNav), findsOneWidget);
  });

  testWidgets('songs in groups: pick a group by letter, then its songs; Escape goes back',
      (tester) async {
    tester.view.physicalSize = const Size(2316, 1080);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    const notes = [SongNote(60, 0, 300)];
    const songs = [
      Song('Lullaby Test', notes, group: 'Kids'),
      Song('Rhyme Test', notes, group: 'Kids'),
      Song('March Test', notes, group: 'Classical'),
    ];
    await tester.pumpWidget(MaterialApp(home: SongListPage(synth: Synth(), midi: MidiInput(), songs: songs)));
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
}
