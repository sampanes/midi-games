// Songs for song mode: melody note lists made by scripts/extract-melodies.py
// and bundled as assets/songs/*.json (local builds only, never committed).
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
  const Song(this.title, this.notes);

  factory Song.fromJson(Map<String, dynamic> json) {
    final notes = [
      for (final n in json['notes'] as List)
        SongNote((n as List)[0] as int, n[1] as int, n[2] as int),
    ];
    return Song(json['title'] as String, notes);
  }

  final String title;
  final List<SongNote> notes;
}

Future<List<Song>> loadSongs(AssetBundle bundle) async {
  final manifest = await AssetManifest.loadFromAssetBundle(bundle);
  final paths = manifest
      .listAssets()
      .where((path) => path.startsWith('assets/songs/') && path.endsWith('.json'));
  final songs = <Song>[];
  for (final path in paths) {
    final json = jsonDecode(await bundle.loadString(path)) as Map<String, dynamic>;
    final song = Song.fromJson(json);
    if (song.notes.isNotEmpty) songs.add(song);
  }
  songs.sort((a, b) => a.title.compareTo(b.title));
  return songs;
}

enum SongPress { hit, finished, miss, ignored }

// Where the player is in a song. Any octave of the right note counts: the
// keyboard's octave buttons should never make a child "wrong".
class SongRun {
  const SongRun(this.song, {this.index = 0, this.misses = 0});

  final Song song;
  final int index;
  final int misses;

  bool get done => index >= song.notes.length;
  SongNote? get current => done ? null : song.notes[index];

  ({SongRun run, SongPress result}) press(int note) {
    final want = current;
    if (want == null) return (run: this, result: SongPress.ignored);
    if (pitchClass(note) != pitchClass(want.note)) {
      return (run: SongRun(song, index: index, misses: misses + 1), result: SongPress.miss);
    }
    final next = SongRun(song, index: index + 1, misses: misses);
    return (run: next, result: next.done ? SongPress.finished : SongPress.hit);
  }
}
