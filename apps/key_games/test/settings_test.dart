import 'package:flutter_test/flutter_test.dart';
import 'package:key_games/app/settings.dart';
import 'package:key_games/input/back_control.dart';
import 'package:key_games/midi/midi_input.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('a back control survives a round trip through its text form', () {
    const pad = BackControl(ControlKind.note, 9, 36);
    expect(BackControl.parse(pad.encode()), pad);
    expect(pad.encode(), 'note:9:36');
    expect(pad.label, 'Pad 36 (channel 10)');
    expect(BackControl.parse('button:0:20')?.label, 'Button 20 (channel 1)');
    expect(BackControl.parse(null), isNull);
    expect(BackControl.parse('nonsense'), isNull);
    expect(BackControl.parse('note:x:36'), isNull);
  });

  test('a back control matches its own note or button only', () {
    const pad = BackControl(ControlKind.note, 9, 36);
    expect(pad.matchesNote(const NoteEvent(36, 100, on: true, channel: 9)), isTrue);
    expect(pad.matchesNote(const NoteEvent(36, 100, on: true, channel: 0)), isFalse);
    expect(pad.matchesNote(const NoteEvent(37, 100, on: true, channel: 9)), isFalse);
    expect(pad.matchesButton(const ButtonEvent(9, 36, 127)), isFalse);

    const button = BackControl(ControlKind.button, 0, 20);
    expect(button.matchesButton(const ButtonEvent(0, 20, 127)), isTrue);
    expect(button.matchesButton(const ButtonEvent(1, 20, 127)), isFalse);
    expect(button.matchesNote(const NoteEvent(20, 100, on: true)), isFalse);
  });

  test('settings remember the back control and the best scores', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = await Settings.load();
    expect(settings.backControl.value, isNull);
    expect(settings.best('rush.easy'), 0);

    expect(settings.recordBest('rush.easy', 12), isTrue);
    expect(settings.recordBest('rush.easy', 12), isFalse);
    expect(settings.recordBest('rush.easy', 9), isFalse);
    expect(settings.recordBest('rush.easy', 20), isTrue);
    expect(settings.best('rush.easy'), 20);
    expect(settings.best('rush.medium'), 0);

    await settings.setBackControl(const BackControl(ControlKind.button, 0, 20));

    // A fresh load reads the same values back.
    final again = await Settings.load();
    expect(again.best('rush.easy'), 20);
    expect(again.backControl.value, const BackControl(ControlKind.button, 0, 20));

    await again.setBackControl(null);
    expect((await Settings.load()).backControl.value, isNull);
  });
}
