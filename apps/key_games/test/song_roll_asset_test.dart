import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:key_games/songs/song.dart';

class RollBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    const song = 'assets/songs/demo.json';
    const roll = 'assets/songs/demo.roll';
    if (key == 'AssetManifest.bin') {
      return const StandardMessageCodec().encodeMessage({
        song: [{'asset': song}],
        roll: [{'asset': roll}],
      })!;
    }
    final data = switch (key) {
      song => '{"title":"Demo","notes":[[60,0,300]]}',
      roll => '{"description":"Piano part","notes":[[60,0,1000],[64,0,500],[67,5000,200]]}',
      _ => throw FlutterError('Missing $key'),
    };
    return ByteData.sublistView(Uint8List.fromList(utf8.encode(data)));
  }
}

void main() {
  test('loads an optional original polyphonic roll beside a song', () async {
    final songs = await loadSongs(RollBundle());
    expect(songs.single.guideDescription, 'Piano part');
    final notes = songs.single.guideNotes!;
    expect(notes.map((n) => n.note), [60, 64, 67]);
    expect(notes.map((n) => n.startMs), [0, 0, 5000]);
    expect(notes.map((n) => n.lengthMs), [1000, 500, 200]);
  });
}
