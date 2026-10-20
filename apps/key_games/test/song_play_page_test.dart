import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:key_games/songs/song.dart';
import 'package:key_games/songs/song_play_page.dart';

import 'helpers.dart';

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
    usePhone(tester);
    await pumpApp(tester, const SongPlayPage(song: _song));
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

    // C on the keyboard is the Play again button.
    await _tapKey(tester, LogicalKeyboardKey.keyA);
    expect(find.text('Play again'), findsNothing);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpWidget(const SizedBox());
  });
}
