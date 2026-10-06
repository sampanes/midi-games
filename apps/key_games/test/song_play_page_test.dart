import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:key_games/audio/synth.dart';
import 'package:key_games/midi/midi_input.dart';
import 'package:key_games/songs/song.dart';
import 'package:key_games/songs/song_play_page.dart';

// C D E: the computer keys A, S, D.
const _song = Song('Three Notes', [
  SongNote(60, 0, 300),
  SongNote(62, 400, 300),
  SongNote(64, 800, 300),
]);

Future<void> _tapKey(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(key);
  await tester.pump(const Duration(milliseconds: 50));
  await tester.sendKeyUpEvent(key);
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('song screen walks through the notes and plays back at the end', (tester) async {
    tester.view.physicalSize = const Size(1080, 2316);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);

    // The synth is never started here, so it stays silent.
    await tester.pumpWidget(MaterialApp(
      home: SongPlayPage(song: _song, synth: Synth(), midi: MidiInput()),
    ));
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.text('Three Notes'), findsOneWidget);
    expect(find.text('C'), findsWidgets);

    await _tapKey(tester, LogicalKeyboardKey.keyF); // F: wrong, stays on C
    await _tapKey(tester, LogicalKeyboardKey.keyK); // high C: right letter, too high
    expect(find.text('Lower!'), findsOneWidget);
    await _tapKey(tester, LogicalKeyboardKey.keyA); // C
    await _tapKey(tester, LogicalKeyboardKey.keyS); // D
    await _tapKey(tester, LogicalKeyboardKey.keyD); // E: finished
    expect(find.text('YAY!'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 2000));
    expect(find.text('Listen to your song!'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 2000));
    expect(find.text('Play again'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
