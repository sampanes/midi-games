// Game chrome grows with the screen: the end panels, the countdown and the
// Learn Back page are twice their phone size on a full-screen PC, and the
// keyboard picture is taller.

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:key_games/games/difficulty.dart';
import 'package:key_games/games/rush_page.dart';
import 'package:key_games/settings/learn_back_page.dart';
import 'package:key_games/widgets/piano_strip.dart';

import 'helpers.dart';

Future<double> _rushEndTitleHeight(WidgetTester tester) async {
  await pumpApp(tester, RushPage(difficulty: Difficulty.easy, random: Random(5), songs: const []));
  await tester.pump(const Duration(seconds: 3));
  await tester.pump(const Duration(seconds: 61));
  expect(find.text("Time's up!"), findsOneWidget);
  final height = tester.getSize(find.text("Time's up!")).height;
  // Let the end-of-round timers finish before the test ends.
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 2));
  return height;
}

void main() {
  testWidgets('the Key Rush end panel is twice as big on a PC as on a phone', (tester) async {
    usePhone(tester, landscape: true);
    final onPhone = await _rushEndTitleHeight(tester);

    useTv(tester);
    final onTv = await _rushEndTitleHeight(tester);
    expect(onTv, closeTo(onPhone * 2, 2));
  });

  testWidgets('the keyboard picture is taller on a PC, within its share of the screen',
      (tester) async {
    usePhone(tester, landscape: true);
    await pumpApp(tester, RushPage(difficulty: Difficulty.easy, random: Random(5), songs: const []));
    await tester.pump(const Duration(milliseconds: 500));
    final onPhone = tester.getSize(find.byType(PianoStrip)).height;
    expect(onPhone, lessThanOrEqualTo(411 * 0.24 + 1));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));

    useTv(tester);
    await pumpApp(tester, RushPage(difficulty: Difficulty.easy, random: Random(5), songs: const []));
    await tester.pump(const Duration(milliseconds: 500));
    final onTv = tester.getSize(find.byType(PianoStrip)).height;
    expect(onTv, closeTo(1080 * 0.24, 1));
    expect(onTv, greaterThan(onPhone * 2));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('the Learn Back page reads from a couch', (tester) async {
    useTv(tester);
    await pumpApp(tester, const LearnBackPage());
    final text = find.text('Press the pad or button you want to use for Back.');
    // 28 at phone size, doubled on the PC: a line is about 76 tall.
    expect(tester.getSize(text).height, greaterThan(60));
    expect(tester.getSize(find.byType(Icon).last).height, 192);
  });
}
