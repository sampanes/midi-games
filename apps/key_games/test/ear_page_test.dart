import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:key_games/audio/synth.dart';
import 'package:key_games/games/ear_page.dart';
import 'package:key_games/midi/midi_input.dart';

Future<void> _tapKey(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(key);
  await tester.pump(const Duration(milliseconds: 50));
  await tester.sendKeyUpEvent(key);
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('ear screen hides the note until it is found', (tester) async {
    tester.view.physicalSize = const Size(1080, 2316);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);

    // The synth is never started here, so it stays silent.
    await tester.pumpWidget(MaterialApp(
      home: EarPage(synth: Synth(), midi: MidiInput(), random: Random(4)),
    ));
    await tester.pump(const Duration(milliseconds: 1500));
    expect(find.text('?'), findsOneWidget);
    expect(find.text('Level 1'), findsOneWidget);
    expect(find.text('C   G'), findsOneWidget);

    // Level 1 is C or G, so one of these two finds it and shows the letter.
    await _tapKey(tester, LogicalKeyboardKey.keyA);
    await _tapKey(tester, LogicalKeyboardKey.keyG);
    expect(find.text('?'), findsNothing);

    // The next mystery note hides it again.
    await tester.pump(const Duration(milliseconds: 1500));
    expect(find.text('?'), findsOneWidget);

    await tester.tap(find.text('Level 1'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Level 2'), findsOneWidget);
    expect(find.text('C   E   G'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
