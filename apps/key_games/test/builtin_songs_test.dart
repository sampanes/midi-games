import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:key_games/songs/builtin_songs.dart';
import 'package:key_games/songs/song.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('built-in tunes have unique titles, notes in order, on the 37-key picture', () {
    expect(builtinSongs.map((s) => s.title).toSet().length, builtinSongs.length);
    expect(builtinSongs.length, greaterThanOrEqualTo(8));
    for (final song in builtinSongs) {
      expect(song.notes, isNotEmpty, reason: song.title);
      var last = 0;
      for (final n in song.notes) {
        expect(n.startMs, greaterThanOrEqualTo(last), reason: song.title);
        expect(n.lengthMs, greaterThan(0), reason: song.title);
        expect(n.note, inInclusiveRange(48, 84), reason: song.title);
        last = n.startMs;
      }
    }
  });

  test('loadSongs lists the built-in tunes with no bundled songs', () async {
    final songs = await loadSongs(rootBundle);
    expect(songs.map((s) => s.title), contains('Twinkle Twinkle Little Star'));
    expect(songGroups(songs).first, 'Kids');
  });
}
