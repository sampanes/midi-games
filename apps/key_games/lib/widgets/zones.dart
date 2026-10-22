// Zones: the keyboard picture split into big parts, low and high (two) or
// low, middle and high (three), so the easiest levels ask "which part of the
// keyboard?" instead of "which key?". Any key in a part counts, so a small
// child can mash and still be right. Shared by Key Runner, Ear Notes, Key
// Rush and Note Highway, so the parts and their colors are the same in every
// game.
//
// The parts are measured on the keyboard picture (see pictureKeys). On the
// 37-key picture, which follows the keyboard's octave buttons (see fitBase),
// three parts are its octaves (7, 7 and 8 white keys) and two are its halves
// (11 and 11). On the one octave shown with no keyboard, three parts are
// C D E, F G and A B C, and two are C D E F and G A B C.

import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../games/color_keys_rules.dart';
import 'game_page.dart';
import 'piano_strip.dart';

const _zoneColors3 = [Color(0xFF22C9A0), Color(0xFFFFD84A), Color(0xFFFF5EC8)];
const _zoneNames3 = ['Low', 'Middle', 'High'];
const _zoneColors2 = [Color(0xFF22C9A0), Color(0xFFFF5EC8)];
const _zoneNames2 = ['Low', 'High'];

List<Color> zoneColors(int count) => count == 2 ? _zoneColors2 : _zoneColors3;
List<String> zoneNames(int count) => count == 2 ? _zoneNames2 : _zoneNames3;

typedef Keys = ({int low, int high});

// First key of part [i] of [count], counted from the picture's lowest C.
int _zoneStart(Keys picture, int i, int count) {
  final octave = picture.high - picture.low <= 12;
  final starts = count == 2
      ? (octave ? const [0, 7] : const [0, 18])
      : (octave ? const [0, 5, 9] : const [0, 12, 24]);
  return starts[i];
}

// Which part (0 = lowest) [note] is in. Keys below the picture count as the
// lowest part and keys above it as the highest.
int zoneOf(int note, Keys picture, int count) {
  final offset = note - picture.low;
  for (var i = count - 1; i > 0; i--) {
    if (offset >= _zoneStart(picture, i, count)) return i;
  }
  return 0;
}

// The keys of part [i] on the picture.
Keys zoneSpan(Keys picture, int i, int count) => (
      low: picture.low + _zoneStart(picture, i, count),
      high: i == count - 1
          ? picture.high
          : picture.low + _zoneStart(picture, i + 1, count) - 1,
    );

// Where part [i] sits across a strip [width] wide showing [picture], so
// lanes drawn above the strip line up with the parts.
({double left, double width}) zoneColumn(Keys picture, int i, int count, double width) {
  final span = zoneSpan(picture, i, count);
  final first = keyColumn(picture.low, picture.high, width, span.low);
  var lastWhite = span.high;
  while (!pitchClasses[pitchClass(lastWhite)].white) {
    lastWhite--;
  }
  final last = keyColumn(picture.low, picture.high, width, lastWhite);
  return (left: first.left, width: last.left + last.width - first.left);
}

int _whiteCount(Keys span) => [
      for (var note = span.low; note <= span.high; note++)
        if (pitchClasses[pitchClass(note)].white) note,
    ].length;

// A row of named color bars, one per part, as wide as the parts of a strip
// of the same width below it showing [picture]. [lit] is drawn bright with a
// white edge (the part to press now); with [lit] null every bar is bright.
class ZoneBar extends StatelessWidget {
  const ZoneBar({super.key, required this.count, required this.picture, this.lit});

  final int count;
  final Keys picture;
  final int? lit;

  @override
  Widget build(BuildContext context) {
    final s = uiScale(context);
    final colors = zoneColors(count);
    final names = zoneNames(count);
    return ScaledChrome(
      scale: s,
      child: Row(
        children: [
          for (var i = 0; i < count; i++)
            Expanded(
              flex: _whiteCount(zoneSpan(picture, i, count)),
              child: Container(
                height: 22 * s,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: lit == null || lit == i
                      ? colors[i]
                      : Color.lerp(colors[i], AppColors.background, 0.55),
                  borderRadius: BorderRadius.circular(6 * s),
                  border: lit == i ? Border.all(color: Colors.white, width: 2 * s) : null,
                ),
                child: Text(names[i],
                    style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.ink)),
              ),
            ),
        ],
      ),
    );
  }
}
