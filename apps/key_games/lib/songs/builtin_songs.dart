// Tunes every build ships with, so the Songs games work out of the box: old
// nursery songs and one Beethoven, all public domain, written out by hand in
// C major around middle C (60). Your own songs come from private/songs
// through scripts/extract-melodies.py and are listed with these.
//
// Each tune is a list of (note, beats); a beat is a quarter note at the
// tune's tempo. Notes are held for most of their beat, like a played melody.

import 'song.dart';

Song _tune(String title, String group, int beatMs, List<(int, double)> steps) {
  final notes = <SongNote>[];
  var at = 0.0;
  for (final (note, beats) in steps) {
    final length = beats * beatMs;
    notes.add(SongNote(note, at.round(), (length * 0.85).round()));
    at += length;
  }
  return Song(title, notes, group: group);
}

// C major, one octave each side of middle C.
const _g3 = 55, _a3 = 57, _b3 = 59;
const _c4 = 60, _d4 = 62, _e4 = 64, _f4 = 65, _g4 = 67, _a4 = 69;
const _c5 = 72;

final List<Song> builtinSongs = [
  _tune('Twinkle Twinkle Little Star', 'Kids', 500, [
    (_c4, 1), (_c4, 1), (_g4, 1), (_g4, 1), (_a4, 1), (_a4, 1), (_g4, 2),
    (_f4, 1), (_f4, 1), (_e4, 1), (_e4, 1), (_d4, 1), (_d4, 1), (_c4, 2),
    (_g4, 1), (_g4, 1), (_f4, 1), (_f4, 1), (_e4, 1), (_e4, 1), (_d4, 2),
    (_g4, 1), (_g4, 1), (_f4, 1), (_f4, 1), (_e4, 1), (_e4, 1), (_d4, 2),
    (_c4, 1), (_c4, 1), (_g4, 1), (_g4, 1), (_a4, 1), (_a4, 1), (_g4, 2),
    (_f4, 1), (_f4, 1), (_e4, 1), (_e4, 1), (_d4, 1), (_d4, 1), (_c4, 2),
  ]),
  _tune('Mary Had a Little Lamb', 'Kids', 500, [
    (_e4, 1), (_d4, 1), (_c4, 1), (_d4, 1), (_e4, 1), (_e4, 1), (_e4, 2),
    (_d4, 1), (_d4, 1), (_d4, 2), (_e4, 1), (_g4, 1), (_g4, 2),
    (_e4, 1), (_d4, 1), (_c4, 1), (_d4, 1), (_e4, 1), (_e4, 1), (_e4, 1), (_e4, 1),
    (_d4, 1), (_d4, 1), (_e4, 1), (_d4, 1), (_c4, 4),
  ]),
  _tune('Hot Cross Buns', 'Kids', 500, [
    (_e4, 1), (_d4, 1), (_c4, 2), (_e4, 1), (_d4, 1), (_c4, 2),
    (_c4, 0.5), (_c4, 0.5), (_c4, 0.5), (_c4, 0.5), (_d4, 0.5), (_d4, 0.5), (_d4, 0.5), (_d4, 0.5),
    (_e4, 1), (_d4, 1), (_c4, 2),
  ]),
  _tune('Row, Row, Row Your Boat', 'Kids', 250, [
    (_c4, 3), (_c4, 3), (_c4, 2), (_d4, 1), (_e4, 3),
    (_e4, 2), (_d4, 1), (_e4, 2), (_f4, 1), (_g4, 6),
    (_c5, 1), (_c5, 1), (_c5, 1), (_g4, 1), (_g4, 1), (_g4, 1),
    (_e4, 1), (_e4, 1), (_e4, 1), (_c4, 1), (_c4, 1), (_c4, 1),
    (_g4, 2), (_f4, 1), (_e4, 2), (_d4, 1), (_c4, 6),
  ]),
  _tune('London Bridge', 'Kids', 500, [
    (_g4, 1.5), (_a4, 0.5), (_g4, 1), (_f4, 1), (_e4, 1), (_f4, 1), (_g4, 2),
    (_d4, 1), (_e4, 1), (_f4, 2), (_e4, 1), (_f4, 1), (_g4, 2),
    (_g4, 1.5), (_a4, 0.5), (_g4, 1), (_f4, 1), (_e4, 1), (_f4, 1), (_g4, 2),
    (_d4, 2), (_g4, 2), (_e4, 1), (_c4, 3),
  ]),
  _tune('Old MacDonald', 'Kids', 450, [
    (_c4, 1), (_c4, 1), (_c4, 1), (_g3, 1), (_a3, 1), (_a3, 1), (_g3, 2),
    (_e4, 1), (_e4, 1), (_d4, 1), (_d4, 1), (_c4, 3), (_g3, 1),
    (_c4, 1), (_c4, 1), (_c4, 1), (_g3, 1), (_a3, 1), (_a3, 1), (_g3, 2),
    (_e4, 1), (_e4, 1), (_d4, 1), (_d4, 1), (_c4, 4),
  ]),
  _tune('Frère Jacques', 'Kids', 450, [
    (_c4, 1), (_d4, 1), (_e4, 1), (_c4, 1), (_c4, 1), (_d4, 1), (_e4, 1), (_c4, 1),
    (_e4, 1), (_f4, 1), (_g4, 2), (_e4, 1), (_f4, 1), (_g4, 2),
    (_g4, 0.5), (_a4, 0.5), (_g4, 0.5), (_f4, 0.5), (_e4, 1), (_c4, 1),
    (_g4, 0.5), (_a4, 0.5), (_g4, 0.5), (_f4, 0.5), (_e4, 1), (_c4, 1),
    (_c4, 1), (_g3, 1), (_c4, 2), (_c4, 1), (_g3, 1), (_c4, 2),
  ]),
  _tune('Jingle Bells', 'Kids', 450, [
    (_e4, 1), (_e4, 1), (_e4, 2), (_e4, 1), (_e4, 1), (_e4, 2),
    (_e4, 1), (_g4, 1), (_c4, 1.5), (_d4, 0.5), (_e4, 4),
    (_f4, 1), (_f4, 1), (_f4, 1.5), (_f4, 0.5), (_f4, 1), (_e4, 1), (_e4, 1), (_e4, 0.5), (_e4, 0.5),
    (_e4, 1), (_d4, 1), (_d4, 1), (_e4, 1), (_d4, 2), (_g4, 2),
  ]),
  _tune('Happy Birthday', 'Kids', 500, [
    (_g3, 0.75), (_g3, 0.25), (_a3, 1), (_g3, 1), (_c4, 1), (_b3, 2),
    (_g3, 0.75), (_g3, 0.25), (_a3, 1), (_g3, 1), (_d4, 1), (_c4, 2),
    (_g3, 0.75), (_g3, 0.25), (_g4, 1), (_e4, 1), (_c4, 1), (_b3, 1), (_a3, 2),
    (_f4, 0.75), (_f4, 0.25), (_e4, 1), (_c4, 1), (_d4, 1), (_c4, 3),
  ]),
  _tune('Ode to Joy', 'Classical', 450, [
    (_e4, 1), (_e4, 1), (_f4, 1), (_g4, 1), (_g4, 1), (_f4, 1), (_e4, 1), (_d4, 1),
    (_c4, 1), (_c4, 1), (_d4, 1), (_e4, 1), (_e4, 1.5), (_d4, 0.5), (_d4, 2),
    (_e4, 1), (_e4, 1), (_f4, 1), (_g4, 1), (_g4, 1), (_f4, 1), (_e4, 1), (_d4, 1),
    (_c4, 1), (_c4, 1), (_d4, 1), (_e4, 1), (_d4, 1.5), (_c4, 0.5), (_c4, 2),
  ]),
];
