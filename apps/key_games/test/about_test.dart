// The version shown in Settings matches pubspec.yaml, and About opens the
// licenses page (where the typeface's license is listed).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:key_games/app/about.dart';
import 'package:key_games/input/key_router.dart';
import 'package:key_games/settings/settings_page.dart';

import 'helpers.dart';

void main() {
  test('the version in the app is the version in pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final version = RegExp(r'^version:\s*(\S+)', multiLine: true).firstMatch(pubspec)!.group(1)!;
    expect(version.split('+').first, appVersion);
  });

  testWidgets('About (E) opens the licenses page with the version', (tester) async {
    await pumpApp(tester, const SettingsPage());
    await tester.pump(keySettle);
    expect(find.text('About'), findsOneWidget);
    expect(find.textContaining(appVersion), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyD); // D: the E key
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyD);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(LicensePage), findsOneWidget);
    expect(find.text(appName), findsWidgets);
  });
}
