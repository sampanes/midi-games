// Home menu: game categories, each a letter menu of its games, and every game
// starts with a difficulty picker (Easy to Expert). Everything is picked by
// pressing a note letter on the keyboard, so no touch screen is needed (TV).
// A category with one game opens that game's picker straight away, so C C
// always reaches the first game on Easy. Free Play has no levels: its tile
// opens it.
//
// The categories say what a game asks for. Look: a note is shown, find it.
// Listen: a note is heard, find it. Memory: here is a pattern, play it back.
// Songs: real tunes, read as they go by. Arcade: against the clock.
//
// Two header buttons follow the tiles. Again, once a game has been played,
// has the next letter and opens the game played last at its level (a song
// game straight into its song). Settings is on a black key, F#, the same
// one whether or not there is a game to play again, where a small child
// picking letters does not land on it. The line under the tiles says what
// Again plays and, until a Back pad is picked in Settings (any pad goes
// back meanwhile), where to pick one.

import 'package:flutter/material.dart';

import 'app/services.dart';
import 'app/settings.dart';
import 'games/color_keys_page.dart';
import 'games/color_keys_rules.dart';
import 'games/copy_page.dart';
import 'games/difficulty.dart';
import 'games/ear_page.dart';
import 'games/free_play_page.dart';
import 'games/highway_page.dart';
import 'games/memory_page.dart';
import 'games/runner_page.dart';
import 'games/rush_page.dart';
import 'settings/settings_page.dart';
import 'songs/song.dart';
import 'songs/song_list_page.dart';
import 'songs/song_listen_page.dart';
import 'songs/known_songs_page.dart';
import 'songs/song_play_page.dart';
import 'widgets/menu_page.dart';

// One game on the menus. [open] builds its first page for a level, going
// straight into [song] when one is given (Again); [levels] is null for a
// game without levels.
class _Game {
  const _Game(
    this.id,
    this.title,
    this.subtitle,
    this.icon,
    this.colors,
    this.open, {
    this.levels,
    this.labels = const {},
    this.bestKeys = const {},
  });

  // The name the game is remembered by (Settings.lastGame).
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> colors;
  final Widget Function(Difficulty level, String? song) open;
  final Map<Difficulty, String>? levels;
  final Map<Difficulty, String> labels;
  final Map<Difficulty, String> bestKeys;
}

// The key that opens Settings from the home menu: F#.
const settingsLetter = 6;

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  static void _go(BuildContext context, Widget page) {
    Navigator.push(context, MaterialPageRoute<void>(builder: (_) => page));
  }

  static List<_Game> _games(Settings settings) {
    // A song game: its song list, which says which song was opened.
    Widget songs(
      String id,
      String title,
      Difficulty level,
      String? song, {
      Widget Function(Song song)? play,
      String Function(Song song)? starsKey,
      bool levels = true,
    }) =>
        SongListPage(
          difficulty: level,
          title: title,
          play: play,
          levels: levels,
          starsKey: starsKey,
          autoOpen: song,
          onOpen: (opened) => settings.setLastGame(LastGame(id, level.index, opened.title)),
        );

    return [
      _Game(
        'color',
        'Color Keys',
        'Find the note',
        Icons.palette,
        const [Color(0xFFFF3B3B), Color(0xFFFF9A1F)],
        (level, _) => ColorKeysPage(difficulty: level),
        levels: colorKeysLevels,
      ),
      _Game(
        'ear',
        'Ear Notes',
        'Listen, then find the note',
        Icons.hearing,
        const [Color(0xFF22C9A0), Color(0xFF4A6BFF)],
        (level, _) => EarPage(difficulty: level),
        levels: earLevelsText,
      ),
      _Game(
        'copy',
        'Copy Cat',
        'Watch the pattern, play it back',
        Icons.pets,
        const [Color(0xFFFF5EC8), Color(0xFF8A4DFF)],
        (level, _) => CopyPage(difficulty: level),
        levels: copyLevelsText,
        bestKeys: copyBestKeys,
      ),
      _Game(
        'memory',
        'Song Memory',
        'Learn a tune by heart, a bit at a time',
        Icons.psychology_alt,
        const [Color(0xFF4A6BFF), Color(0xFFC04DFF)],
        (level, song) => songs('memory', 'Song Memory', level, song,
            play: (song) => MemoryPage(song: song, difficulty: level),
            starsKey: (song) => memoryStarsKey(level, song)),
        levels: memoryLevelsText,
      ),
      _Game(
        'steps',
        'Song Steps',
        'Play real tunes, one note at a time',
        Icons.music_note,
        const [Color(0xFF8A4DFF), Color(0xFFFF5EC8)],
        (level, song) => songs('steps', 'Song Steps', level, song,
            starsKey: (song) => stepsStarsKey(level, song)),
        levels: songLevels,
      ),
      _Game(
        'highway',
        'Note Highway',
        'Hit the falling notes in time',
        Icons.queue_music,
        const [Color(0xFF2FA8FF), Color(0xFF8A4DFF)],
        (level, song) => songs('highway', 'Note Highway', level, song,
            play: (song) => HighwayPage(song: song, difficulty: level),
            starsKey: (song) => highwayStarsKey(level, song)),
        levels: highwayLevelsText,
      ),
      // No levels: straight to the song list.
      _Game(
        'box',
        'Song Box',
        'Hear any song first',
        Icons.headphones,
        const [Color(0xFFFF9A1F), Color(0xFFFF5EC8)],
        (level, song) => songs('box', 'Song Box', level, song,
            play: (song) => SongListenPage(song: song), levels: false),
      ),
      _Game(
        'rush',
        'Key Rush',
        'One minute: hit all you can',
        Icons.bolt,
        const [Color(0xFFFFD84A), Color(0xFFFF3B3B)],
        (level, _) => RushPage(difficulty: level),
        levels: rushLevels,
        labels: rushLabels,
        bestKeys: rushBestKeys,
      ),
      _Game(
        'runner',
        'Key Runner',
        'Dodge the rocks, grab the coins',
        Icons.directions_run,
        const [Color(0xFF22C9A0), Color(0xFF2FA8FF)],
        (level, _) => RunnerPage(difficulty: level),
        levels: runnerLevelsText,
        bestKeys: runnerBestKeys,
      ),
      _Game(
        'free',
        'Free Play',
        'No rules: every key sparkles',
        Icons.auto_awesome,
        const [Color(0xFF3DDC4A), Color(0xFF2FA8FF)],
        (_, _) => const FreePlayPage(),
      ),
    ];
  }

  // The tile of one game: its difficulty picker, or the game itself when it
  // has no levels. Either way the game is remembered for Again.
  static MenuItem _tile(_Game game, Settings settings) {
    final levels = game.levels;
    return MenuItem(
      title: game.title,
      subtitle: game.subtitle,
      icon: game.icon,
      colors: game.colors,
      onPick: (context) {
        if (levels == null) {
          settings.setLastGame(LastGame(game.id, 0));
          _go(context, game.open(Difficulty.easy, null));
          return;
        }
        _go(
          context,
          difficultyPage(
            title: game.title,
            descriptions: levels,
            labels: game.labels,
            bestKeys: game.bestKeys,
            onStart: (level) => settings.setLastGame(LastGame(game.id, level.index)),
            game: (level) => game.open(level, null),
          ),
        );
      },
    );
  }

  // One game: straight to it. More: a menu of them.
  static MenuItem _category(
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
      onPick: games.length == 1
          ? games.single.onPick
          : (context) => _go(context, MenuPage(title: title, items: games)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = AppServices.of(context).settings;
    final games = {for (final game in _games(settings)) game.id: game};
    MenuItem tile(String id) => _tile(games[id]!, settings);

    final tiles = [
      _category('Look', 'Find the glowing note', Icons.visibility,
          const [Color(0xFFFF3B3B), Color(0xFFFF9A1F)], [tile('color')]),
      _category('Listen', 'Hear a note, then find it', Icons.hearing,
          const [Color(0xFF22C9A0), Color(0xFF4A6BFF)], [tile('ear')]),
      _category('Memory', 'Here is the pattern: play it back', Icons.psychology,
          const [Color(0xFFFF5EC8), Color(0xFF8A4DFF)], [tile('copy'), tile('memory')]),
      _category('Songs', 'Play real tunes', Icons.music_note,
          const [Color(0xFF8A4DFF), Color(0xFFFF5EC8)],
          [
            tile('steps'), tile('highway'), tile('box'),
            MenuItem(
              title: 'My songs',
              subtitle: 'Remember songs and follow the keys',
              icon: Icons.library_music_rounded,
              colors: const [Color(0xFF8A4DFF), Color(0xFF2FA8FF)],
              onPick: (context) => _go(context, const KnownSongsPage()),
            ),
          ]),
      _category('Arcade', 'Fast games against the clock', Icons.sports_esports,
          const [Color(0xFFFFD84A), Color(0xFFFF3B3B)], [tile('rush'), tile('runner')]),
      tile('free'),
    ];
    final settingsItem = MenuItem(
      title: 'Settings',
      subtitle: 'The Back pad and the sound',
      icon: Icons.settings,
      colors: const [Color(0xFF4A4360), Color(0xFF2B2440)],
      onPick: (context) => _go(context, const SettingsPage()),
      letter: settingsLetter,
    );
    final settingsName = pitchClasses[settingsLetter].name;
    // Again takes the letter after the tiles.
    final againName = pitchClasses[menuLetters[tiles.length]].name;

    return ListenableBuilder(
      listenable: Listenable.merge([settings.backControl, settings.lastGame]),
      builder: (context, _) {
        final last = settings.lastGame.value;
        final lastGame = last == null ? null : games[last.game];
        final lastLevel =
            Difficulty.values[(last?.level ?? 0).clamp(0, Difficulty.values.length - 1)];
        return MenuPage(
          title: 'Key Games',
          footer: [
            if (lastGame == null)
              'Press a letter on the keyboard to pick.'
            else
              '$againName plays ${last!.song ?? lastGame.title} again.',
            if (settings.backControl.value == null)
              'Any pad goes back; $settingsName (Settings) picks just one.',
          ].join(' '),
          items: tiles,
          actions: [
            settingsItem,
            if (lastGame != null)
              MenuItem(
                title: 'Again',
                subtitle: last!.song ?? lastGame.title,
                icon: Icons.replay_rounded,
                colors: lastGame.colors,
                onPick: (context) => _go(context, lastGame.open(lastLevel, last.song)),
              ),
          ],
        );
      },
    );
  }
}
