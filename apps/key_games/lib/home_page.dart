// Home menu: game categories, each a letter menu of its games, and every game
// starts with a difficulty picker (Easy to Expert). Everything is picked by
// pressing a note letter on the keyboard, so no touch screen is needed (TV):
// C C C always reaches the first game on Easy.

import 'package:flutter/material.dart';

import 'audio/synth.dart';
import 'games/color_keys_page.dart';
import 'games/difficulty.dart';
import 'games/ear_page.dart';
import 'games/highway_page.dart';
import 'games/runner_page.dart';
import 'games/rush_page.dart';
import 'midi/midi_input.dart';
import 'songs/song_list_page.dart';
import 'songs/song_listen_page.dart';
import 'songs/song_play_page.dart' show songLevels;
import 'widgets/menu_page.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.synth, required this.midi});

  final Synth synth;
  final MidiInput midi;

  void _go(BuildContext context, Widget page) {
    Navigator.push(context, MaterialPageRoute<void>(builder: (_) => page));
  }

  MenuItem _game(
    String title,
    String subtitle,
    IconData icon,
    List<Color> colors,
    Map<Difficulty, String> levels,
    Widget Function(Difficulty difficulty) game, {
    Map<Difficulty, String> labels = const {},
  }) {
    return MenuItem(
      title: title,
      subtitle: subtitle,
      icon: icon,
      colors: colors,
      onPick: (context) => _go(
        context,
        difficultyPage(
          title: title,
          midi: midi,
          descriptions: levels,
          labels: labels,
          game: game,
        ),
      ),
    );
  }

  MenuItem _category(
    String title,
    String subtitle,
    IconData icon,
    List<Color> colors,
    List<MenuItem> games,
  ) {
    return MenuItem(
      title: title,
      subtitle: subtitle,
      icon: icon,
      colors: colors,
      onPick: (context) => _go(context, MenuPage(title: title, midi: midi, items: games)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorKeys = _game(
      'Color Keys',
      'Find the note',
      Icons.palette,
      const [Color(0xFFFF3B3B), Color(0xFFFFE81F), Color(0xFF2FA8FF)],
      colorKeysLevels,
      (d) => ColorKeysPage(synth: synth, midi: midi, difficulty: d),
    );
    final ear = _game(
      'Ear Notes',
      'Listen, then find the note',
      Icons.hearing,
      const [Color(0xFF22C9A0), Color(0xFF2FA8FF), Color(0xFF4A6BFF)],
      earLevelsText,
      (d) => EarPage(synth: synth, midi: midi, difficulty: d),
    );
    final steps = _game(
      'Song Steps',
      'Play real tunes, one note at a time',
      Icons.music_note,
      const [Color(0xFF8A4DFF), Color(0xFFFF5EC8), Color(0xFFFF9A1F)],
      songLevels,
      (d) => SongListPage(synth: synth, midi: midi, difficulty: d, title: 'Song Steps'),
    );
    final highway = _game(
      'Note Highway',
      'Hit the falling notes in time',
      Icons.queue_music,
      const [Color(0xFF2FA8FF), Color(0xFF8A4DFF), Color(0xFFFF5EC8)],
      highwayLevelsText,
      (d) => SongListPage(
        synth: synth,
        midi: midi,
        difficulty: d,
        title: 'Note Highway',
        play: (song) => HighwayPage(song: song, synth: synth, midi: midi, difficulty: d),
      ),
    );
    // No levels: straight to the song list.
    final songBox = MenuItem(
      title: 'Song Box',
      subtitle: 'Hear any song first',
      icon: Icons.headphones,
      colors: const [Color(0xFFFF9A1F), Color(0xFF22C9A0), Color(0xFF2FA8FF)],
      onPick: (context) => _go(
        context,
        SongListPage(
          synth: synth,
          midi: midi,
          title: 'Song Box',
          levels: false,
          play: (song) => SongListenPage(song: song, synth: synth, midi: midi),
        ),
      ),
    );
    final rush = _game(
      'Key Rush',
      'One minute: hit all you can',
      Icons.bolt,
      const [Color(0xFFFFD84A), Color(0xFFFF6A2B), Color(0xFFFF3B3B)],
      rushLevels,
      (d) => RushPage(synth: synth, midi: midi, difficulty: d),
      labels: rushLabels,
    );
    final runner = _game(
      'Key Runner',
      'Dodge the rocks, grab the coins',
      Icons.directions_run,
      const [Color(0xFF22C9A0), Color(0xFFFFD84A), Color(0xFFFF5EC8)],
      runnerLevelsText,
      (d) => RunnerPage(synth: synth, midi: midi, difficulty: d),
    );
    return MenuPage(
      title: 'Key Games',
      midi: midi,
      items: [
        _category('Look', 'Find the glowing note', Icons.visibility,
            const [Color(0xFFFF3B3B), Color(0xFFFF9A1F)], [colorKeys]),
        _category('Listen', 'Games for your ears', Icons.hearing,
            const [Color(0xFF22C9A0), Color(0xFF4A6BFF)], [ear]),
        _category('Songs', 'Play real tunes', Icons.music_note,
            const [Color(0xFF8A4DFF), Color(0xFFFF5EC8)], [steps, highway, songBox]),
        _category('Arcade', 'Fast games against the clock', Icons.sports_esports,
            const [Color(0xFFFFD84A), Color(0xFFFF3B3B)], [rush, runner]),
      ],
      footer: 'Press a letter on the keyboard to pick. '
          'Hold the lowest and highest C together to go back.',
    );
  }
}
