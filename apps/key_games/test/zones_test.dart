// The parts of the keyboard used by the easiest levels, on the 37-key
// picture (a keyboard connected) and on the one octave of big keys (none).

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:key_games/games/ear_page.dart';
import 'package:key_games/widgets/piano_strip.dart';
import 'package:key_games/widgets/zones.dart';

import 'helpers.dart';

void main() {
  const full = (low: 48, high: 84);
  const octave = (low: touchLow, high: touchHigh);

  test('on the 37-key picture the three parts are its octaves', () {
    expect(zoneOf(50, full, 3), 0);
    expect(zoneOf(62, full, 3), 1);
    expect(zoneOf(80, full, 3), 2);
    expect(zoneOf(84, full, 3), 2);
    expect(zoneOf(40, full, 3), 0);
    expect(zoneOf(65, full, 2), 0);
    expect(zoneOf(66, full, 2), 1);
  });

  test('on one octave the parts are C D E, F G, A B C, or C to F and G to C', () {
    expect([for (var n = 60; n <= 72; n++) zoneOf(n, octave, 3)],
        [0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2]);
    expect(zoneSpan(octave, 1, 3), (low: 65, high: 68));
    expect([for (var n = 60; n <= 72; n++) zoneOf(n, octave, 2)],
        [0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1]);
  });

  testWidgets('with no keyboard the picture is one octave of big keys; with one, 37 keys',
      (tester) async {
    usePhone(tester, landscape: true);
    final synth = RecordingSynth();
    final services =
        await pumpApp(tester, EarPage(random: Random(1)), synth: synth, keyboard: false);
    await tester.pump(const Duration(milliseconds: 1500));

    // The lowest key on the picture is middle C, as wide as an eighth of it.
    Future<void> tapLowest() async {
      final strip = tester.getRect(find.byType(PianoStrip));
      await tester.tapAt(Offset(strip.left + 5, strip.bottom - 10));
      await tester.pump(const Duration(milliseconds: 400));
    }

    await tapLowest();
    expect(synth.events, contains('on 60'));
    final strip = tester.getRect(find.byType(PianoStrip));
    final c = keyColumn(touchLow, touchHigh, strip.width, 60);
    expect(c.width, closeTo(strip.width / 8, 1));

    // A keyboard connects: the picture is the 37 keys from C3 again.
    services.midi.connected.value = ['Test keyboard'];
    await tester.pump();
    synth.events.clear();
    await tapLowest();
    expect(synth.events, contains('on 48'));

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
