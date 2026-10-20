// The control that goes back: a pad or a button on the keyboard that the
// player picked in Settings. Remembered as "note:<channel>:<note>" or
// "button:<channel>:<controller>"; channels are 0-15 inside, 1-16 on screen.
// Pure, so it is unit tested on its own.

import '../midi/midi_input.dart';

enum ControlKind { note, button }

class BackControl {
  const BackControl(this.kind, this.channel, this.number);

  final ControlKind kind;
  final int channel;
  final int number;

  static BackControl? parse(String? text) {
    if (text == null) return null;
    final parts = text.split(':');
    if (parts.length != 3) return null;
    final kind = ControlKind.values.where((k) => k.name == parts[0]).firstOrNull;
    final channel = int.tryParse(parts[1]);
    final number = int.tryParse(parts[2]);
    if (kind == null || channel == null || number == null) return null;
    return BackControl(kind, channel, number);
  }

  String encode() => '${kind.name}:$channel:$number';

  bool matchesNote(NoteEvent event) =>
      kind == ControlKind.note && event.channel == channel && event.note == number;

  bool matchesButton(ButtonEvent event) =>
      kind == ControlKind.button && event.channel == channel && event.controller == number;

  // "Pad 36 (channel 10)", "Button 20 (channel 1)".
  String get label =>
      '${kind == ControlKind.note ? 'Pad' : 'Button'} $number (channel ${channel + 1})';

  @override
  bool operator ==(Object other) =>
      other is BackControl &&
      other.kind == kind &&
      other.channel == channel &&
      other.number == number;

  @override
  int get hashCode => Object.hash(kind, channel, number);

  @override
  String toString() => encode();
}
