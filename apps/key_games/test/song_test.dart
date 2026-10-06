import 'package:flutter_test/flutter_test.dart';
import 'package:key_games/songs/song.dart';

const _song = Song('Test Tune', [
  SongNote(60, 0, 400),
  SongNote(60, 500, 400),
  SongNote(67, 1000, 400),
]);

void main() {
  test('parses the extractor JSON shape', () {
    final song = Song.fromJson({
      'title': 'Tune',
      'source': 'tune.mid',
      'notes': [
        [60, 0, 250],
        [62, 300, 250],
      ],
    });
    expect(song.title, 'Tune');
    expect(song.notes.length, 2);
    expect(song.notes[1].note, 62);
    expect(song.notes[1].startMs, 300);
  });

  test('right notes walk through the song, repeated notes need repeated presses', () {
    var run = const SongRun(_song);
    var step = run.press(60);
    expect(step.result, SongPress.hit);
    expect(step.run.index, 1);
    step = step.run.press(60);
    expect(step.result, SongPress.hit);
    step = step.run.press(67);
    expect(step.result, SongPress.finished);
    expect(step.run.done, isTrue);
    run = step.run;
    expect(run.press(60).result, SongPress.ignored);
  });

  test('any octave counts; wrong notes count a miss and stay put', () {
    var step = const SongRun(_song).press(48);
    expect(step.result, SongPress.hit);
    step = step.run.press(62);
    expect(step.result, SongPress.miss);
    expect(step.run.index, 1);
    expect(step.run.misses, 1);
  });
}
