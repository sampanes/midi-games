// Songs for song mode. Every song is a melody note list, with the rest of
// its music as backing, made by scripts/extract-melodies.py from a MIDI file:
// the built-in tunes from the samples (assets/builtin/*.json, written by
// scripts/make-sample-songs.py and committed), and your own songs from
// private/songs (assets/songs/*.json, local builds only, never committed).
// The rules here are pure so they are unit tested on their own.

import 'dart:convert';

import 'package:flutter/services.dart';

import '../games/color_keys_rules.dart' show pitchClass;

class SongNote {
  const SongNote(this.note, this.startMs, this.lengthMs);

  final int note;
  final int startMs;
  final int lengthMs;
}

class Song {
  const Song(this.title, this.notes, {this.group = 'Songs', this.backing = const [], this.guideNotes, this.guideDescription});

  factory Song.fromJson(Map<String, dynamic> json) {
    List<SongNote> read(List? list) => [
          for (final n in list ?? const [])
            SongNote((n as List)[0] as int, n[1] as int, n[2] as int),
        ];
    return Song(
      json['title'] as String,
      read(json['notes'] as List),
      group: json['group'] as String? ?? 'Songs',
      backing: read(json['backing'] as List?),
    );
  }

  final String title;

  // Optional unmodified, polyphonic part for the visual song guide.
  final List<SongNote>? guideNotes;
  final String? guideDescription;

  // The tune, one note at a time: what the player plays.
  final List<SongNote> notes;

  // The rest of the music (chords, bass, other parts), on the tune's clock:
  // the band, played by the app.
  final List<SongNote> backing;

  // Heading in the song list (Kids, Classical, ...).
  final String group;
}

// Groups listed first, in this order; any others follow by name.
const songGroupOrder = [
  'Kids', 'Holidays', 'Classical', 'Ballet', 'Musicals', 'Movies', 'Pop', 'Games', 'Anime', 'Rock',
];

// The most stars a song can win in a game.
const songStars = 3;

// Stars for walking a song through in Song Steps: all three for (nearly) no
// wrong keys, two for a few, and one for getting to the end at all.
int stepsStars(int misses, int notes) {
  if (notes == 0) return 0;
  final share = misses / notes;
  return share <= 0.1 ? 3 : share <= 0.35 ? 2 : 1;
}

List<String> songGroups(List<Song> songs) {
  int rank(String group) {
    final i = songGroupOrder.indexOf(group);
    return i < 0 ? songGroupOrder.length : i;
  }

  return {for (final song in songs) song.group}.toList()
    ..sort((a, b) => rank(a) != rank(b) ? rank(a) - rank(b) : a.compareTo(b));
}

// Played when no songs are bundled: up and down the C major scale.
const scaleSong = Song('Scale', [
  SongNote(60, 0, 300), SongNote(62, 0, 300), SongNote(64, 0, 300), SongNote(65, 0, 300),
  SongNote(67, 0, 300), SongNote(69, 0, 300), SongNote(71, 0, 300), SongNote(72, 0, 500),
  SongNote(71, 0, 300), SongNote(69, 0, 300), SongNote(67, 0, 300), SongNote(65, 0, 300),
  SongNote(64, 0, 300), SongNote(62, 0, 300), SongNote(60, 0, 500),
]);

// The built-in tunes and any bundled from private/songs, by title. A song of
// your own with a built-in tune's title (a sample saved in the song editor)
// replaces it.
Future<List<Song>> loadSongs(AssetBundle bundle) async {
  final manifest = await AssetManifest.loadFromAssetBundle(bundle);
  final byTitle = <String, Song>{};
  for (final folder in ['assets/builtin/', 'assets/songs/']) {
    final paths = manifest
        .listAssets()
        .where((path) => path.startsWith(folder) && path.endsWith('.json'))
        .toList()
      ..sort();
    for (final path in paths) {
      final json = jsonDecode(await bundle.loadString(path)) as Map<String, dynamic>;
      var song = Song.fromJson(json);
      final guidePath = '${path.substring(0, path.length - 5)}.roll';
      if (manifest.listAssets().contains(guidePath)) {
        final guide = jsonDecode(await bundle.loadString(guidePath)) as Map<String, dynamic>;
        final notes = (guide['notes'] as List).map((value) {
          final row = value as List;
          return SongNote(row[0] as int, row[1] as int, row[2] as int);
        }).toList();
        if (notes.isNotEmpty) {
          song = Song(song.title, song.notes, group: song.group, backing: song.backing,
              guideNotes: notes, guideDescription: guide['description'] as String?);
        }
      }
      if (song.notes.isNotEmpty) byTitle[song.title] = song;
    }
  }
  return byTitle.values.toList()..sort((a, b) => a.title.compareTo(b.title));
}

enum SongPress { hit, finished, tooLow, tooHigh, miss, ignored }

// Where the player is in a song. The octave matters (a melody can jump from
// A up to the high A and back), but [shift] lets the keyboard's octave
// buttons move everything by whole octaves without making a child "wrong".
class SongRun {
  const SongRun(this.song, {this.index = 0, this.misses = 0});

  final Song song;
  final int index;
  final int misses;

  bool get done => index >= song.notes.length;
  SongNote? get current => done ? null : song.notes[index];

  ({SongRun run, SongPress result}) press(int note, {int shift = 0}) {
    final want = current;
    if (want == null) return (run: this, result: SongPress.ignored);
    final target = want.note + shift;
    if (note != target) {
      final missed = SongRun(song, index: index, misses: misses + 1);
      if (pitchClass(note) != pitchClass(target)) return (run: missed, result: SongPress.miss);
      return (run: missed, result: note < target ? SongPress.tooLow : SongPress.tooHigh);
    }
    final next = SongRun(song, index: index + 1, misses: misses);
    return (run: next, result: next.done ? SongPress.finished : SongPress.hit);
  }
}
