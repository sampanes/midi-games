// Menus from a phone to a TV: tiles are cards, not billboards, Settings is a
// header button, and the keyboard status sits at the right edge.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:key_games/input/back_control.dart';
import 'package:key_games/widgets/keyboard_status.dart';

import 'helpers.dart';

Size _tileSize(WidgetTester tester, String title) =>
    tester.getSize(find.ancestor(of: find.text(title), matching: find.byType(Material)).first);

void main() {
  testWidgets('on a full-screen PC the home tiles are capped and centered', (tester) async {
    useTv(tester);
    await pumpApp(tester, null);
    await tester.pump(const Duration(milliseconds: 500));

    for (final title in ['Look', 'Listen', 'Songs', 'Arcade']) {
      final size = _tileSize(tester, title);
      expect(size.width, lessThanOrEqualTo(600), reason: '$title is a card, not a billboard');
      expect(size.width, greaterThan(380), reason: '$title fills its share of the row');
      expect(size.height, lessThanOrEqualTo(size.width * 1.25 + 1));
    }
    // The row is centered: the gap on the left matches the gap on the right.
    final look = tester.getRect(find.text('Look'));
    final arcade = tester.getRect(find.text('Arcade'));
    expect((look.center.dx - 0).round(), (1920 - arcade.center.dx).round());

    // Settings is a header button, so it is not a fifth tile below the row.
    expect(tester.getRect(find.text('Settings')).top, lessThan(120));

    // The keyboard status sits at the right edge, not in the middle.
    expect(tester.getRect(find.byType(KeyboardStatus)).right, greaterThan(1800));
  });

  testWidgets('a menu with one or two tiles shows cards in the middle', (tester) async {
    useTv(tester);
    await pumpApp(tester, null);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Arcade'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    final rush = _tileSize(tester, 'Key Rush');
    expect(rush.width, lessThanOrEqualTo(600));
    expect(rush.height, lessThanOrEqualTo(rush.width * 1.25 + 1));
    final left = tester.getRect(find.text('Key Rush')).center.dx;
    final right = tester.getRect(find.text('Key Runner')).center.dx;
    expect(left.round(), (1920 - right).round());
  });

  testWidgets('the home menu lays out on a phone both ways', (tester) async {
    usePhone(tester, landscape: true);
    await pumpApp(tester, null);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Arcade'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());

    usePhone(tester);
    await pumpApp(tester, null);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Arcade'), findsOneWidget);
    // Two columns: Look and Listen share a row, Songs sits below Look.
    expect(tester.getRect(find.text('Look')).top, tester.getRect(find.text('Listen')).top);
    expect(tester.getRect(find.text('Songs')).top, greaterThan(tester.getRect(find.text('Look')).top));
  });

  testWidgets('the home menu says where to pick a Back pad until one is picked', (tester) async {
    useTv(tester);
    final services = await pumpApp(tester, null);
    expect(find.textContaining('Any pad goes back'), findsOneWidget);

    await services.settings.setBackControl(const BackControl(ControlKind.note, 9, 36));
    await tester.pump();
    expect(find.textContaining('Any pad goes back'), findsNothing);
    expect(find.text('Press a letter on the keyboard to pick.'), findsOneWidget);
  });
}
