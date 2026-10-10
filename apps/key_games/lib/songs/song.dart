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
  const Song(this.title, this.notes, {this.group = 'Songs'});

  factory Song.fromJson(Map<String, dynamic> json) {
    final notes = [
      for (final n in json['notes'] as List)
        SongNote((n as List)[0] as int, n[1] as int, n[2] as int),
    ];
    return Song(json['title'] as String, notes, group: json['group'] as String? ?? 'Songs');
  }

  final String title;
  final List<SongNote> notes;

  // Heading in the song list (Kids, Classical, ...).
  final String group;
}

// Groups listed first, in this order; any others follow by name.
const songGroupOrder = ['Kids', 'Classical', 'Ballet', 'Musicals', 'Movies', 'Pop', 'Games', 'Anime', 'Rock'];

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
