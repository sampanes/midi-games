import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:key_games/songs/song.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('built-in tunes have notes in order, on the 37-key picture, and a band', () async {
    final songs = await loadSongs(rootBundle);
    expect(songs.length, greaterThanOrEqualTo(13));
    for (final title in ['Twinkle Twinkle Little Star', 'Frère Jacques', 'Für Elise', 'Canon in D']) {
      expect(songs.map((s) => s.title), contains(title));
    }
    for (final song in songs) {
      expect(song.notes, isNotEmpty, reason: song.title);
      expect(song.backing, isNotEmpty, reason: song.title);
      var last = 0;
      for (final n in song.notes) {
        expect(n.startMs, greaterThanOrEqualTo(last), reason: song.title);
        expect(n.lengthMs, greaterThan(0), reason: song.title);
        expect(n.note, inInclusiveRange(48, 84), reason: song.title);
        last = n.startMs;
      }
      // The band plays while the tune does, never after it.
      final end = song.notes.map((n) => n.startMs + n.lengthMs).reduce((a, b) => a > b ? a : b);
      for (final n in song.backing) {
        expect(n.startMs + n.lengthMs, lessThanOrEqualTo(end + 60), reason: song.title);
      }
    }
    expect(songGroups(songs).first, 'Kids');
  });

  test('a song file without backing reads as a tune with no band', () {
    final song = Song.fromJson({
      'title': 'Old file',
      'notes': [
        [60, 0, 400],
      ],
    });
    expect(song.notes.single.note, 60);
    expect(song.backing, isEmpty);
    expect(song.group, 'Songs');
  });
}
