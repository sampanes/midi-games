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
    expect(song.group, 'Songs');
    expect(Song.fromJson({'title': 'T', 'group': 'Pop', 'notes': []}).group, 'Pop');
  });

  test('song groups come in the set order, unknown ones last by name', () {
    Song inGroup(String group) => Song('x', const [], group: group);
    final songs = [for (final g in ['Zoo', 'Games', 'Kids', 'Apples', 'Kids', 'Classical']) inGroup(g)];
    expect(songGroups(songs), ['Kids', 'Classical', 'Games', 'Apples', 'Zoo']);
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

  test('octave matters: right letter in the wrong octave says which way', () {
    var step = const SongRun(_song).press(48);
    expect(step.result, SongPress.tooLow);
    expect(step.run.index, 0);
    expect(step.run.misses, 1);
    step = step.run.press(72);
    expect(step.result, SongPress.tooHigh);
    step = step.run.press(62);
    expect(step.result, SongPress.miss);
    step = step.run.press(60);
    expect(step.result, SongPress.hit);
  });

  test('keyboard octave shift moves every target by whole octaves', () {
    final step = const SongRun(_song).press(72, shift: 12);
    expect(step.result, SongPress.hit);
    expect(step.run.press(60, shift: 12).result, SongPress.tooLow); // second C, an octave low
  });
}
