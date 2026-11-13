// What the app remembers between runs: the Back control, the key sound, how
// loud the band is, the game played last, best scores and stars. Backed by
// shared_preferences, loaded once at startup and read without waiting after
// that.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../input/back_control.dart';

// How a key sounds: struck and fading like a toy piano, or the plain steady
// tone the app started with.
enum KeySound {
  piano('Toy piano'),
  organ('Organ');

  const KeySound(this.label);

  final String label;
}

// How loud a song's band plays under the tune.
enum BandLevel {
  full('Full', 1),
  soft('Soft', 0.5),
  off('Off', 0);

  const BandLevel(this.label, this.gain);

  final String label;
  final double gain;
}

// The game played last, for the home menu's "again" button: the game's
// name, its level, and for a song game the song.
class LastGame {
  const LastGame(this.game, this.level, [this.song]);

  final String game;
  final int level;
  final String? song;

  @override
  bool operator ==(Object other) =>
      other is LastGame && other.game == game && other.level == level && other.song == song;

  @override
  int get hashCode => Object.hash(game, level, song);
}

T _named<T extends Enum>(List<T> values, String? name) =>
    values.where((v) => v.name == name).firstOrNull ?? values.first;

class Settings {
  Settings._(this._prefs)
      : backControl = ValueNotifier(BackControl.parse(_prefs.getString(_backKey))),
        keySound = ValueNotifier(_named(KeySound.values, _prefs.getString(_soundKey))),
        bandLevel = ValueNotifier(_named(BandLevel.values, _prefs.getString(_bandKey))),
        lastGame = ValueNotifier(_readLast(_prefs));

  static Future<Settings> load() async => Settings._(await SharedPreferences.getInstance());

  static const _backKey = 'backControl';
  static const _soundKey = 'keySound';
  static const _bandKey = 'bandLevel';
  static const _lastKey = 'last';

  static LastGame? _readLast(SharedPreferences prefs) {
    final game = prefs.getString('$_lastKey.game');
    if (game == null) return null;
    return LastGame(game, prefs.getInt('$_lastKey.level') ?? 0, prefs.getString('$_lastKey.song'));
  }

  final SharedPreferences _prefs;

  // The pad or button that goes back; null until one is picked in Settings.
  final ValueNotifier<BackControl?> backControl;

  Future<void> setBackControl(BackControl? control) {
    backControl.value = control;
    return control == null
        ? _prefs.remove(_backKey)
        : _prefs.setString(_backKey, control.encode());
  }

  final ValueNotifier<KeySound> keySound;
  final ValueNotifier<BandLevel> bandLevel;

  // Null until a game has been played.
  final ValueNotifier<LastGame?> lastGame;

  void setKeySound(KeySound sound) {
    keySound.value = sound;
    unawaited(_prefs.setString(_soundKey, sound.name));
  }

  void setBandLevel(BandLevel level) {
    bandLevel.value = level;
    unawaited(_prefs.setString(_bandKey, level.name));
  }

  void setLastGame(LastGame last) {
    if (lastGame.value == last) return;
    lastGame.value = last;
    unawaited(_prefs.setString('$_lastKey.game', last.game));
    unawaited(_prefs.setInt('$_lastKey.level', last.level));
    final song = last.song;
    unawaited(song == null
        ? _prefs.remove('$_lastKey.song')
        : _prefs.setString('$_lastKey.song', song));
  }

  // Best score so far for [game] (for example "rush.easy"); 0 when none.
  int best(String game) => _prefs.getInt('best.$game') ?? 0;

  // Keeps [score] when it beats the best so far, and says whether it did.
  bool recordBest(String game, int score) {
    if (score <= best(game)) return false;
    unawaited(_prefs.setInt('best.$game', score));
    return true;
  }
}
