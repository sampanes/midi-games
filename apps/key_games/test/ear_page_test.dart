import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:key_games/games/ear_page.dart';

import 'helpers.dart';

Future<void> _tapKey(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(key);
  await tester.pump(const Duration(milliseconds: 50));
  await tester.sendKeyUpEvent(key);
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('ear screen hides the note until it is found', (tester) async {
    usePhone(tester);
    await pumpApp(tester, EarPage(random: Random(4)));
    await tester.pump(const Duration(milliseconds: 1500));
    expect(find.text('?'), findsOneWidget);
    expect(find.text('Level 1'), findsOneWidget);
    expect(find.text('Low'), findsOneWidget);
    expect(find.text('High'), findsOneWidget);

    // Level 1 is high or low. The computer keys are the middle of the
    // keyboard picture: C (A) is in its low half and the high C (K) in its
    // high half, so one of the two finds it, and the circle names it.
    await _tapKey(tester, LogicalKeyboardKey.keyA);
    await _tapKey(tester, LogicalKeyboardKey.keyK);
    expect(find.text('?'), findsNothing);

    // The next mystery note hides it again.
    await tester.pump(const Duration(milliseconds: 1500));
    expect(find.text('?'), findsOneWidget);

    await tester.tap(find.text('Level 1'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Level 2'), findsOneWidget);
    expect(find.text('C   G'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
