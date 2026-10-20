// What the app remembers between runs: the Back control and best scores.
// Backed by shared_preferences, loaded once at startup and read without
// waiting after that.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../input/back_control.dart';

class Settings {
  Settings._(this._prefs)
      : backControl = ValueNotifier(BackControl.parse(_prefs.getString(_backKey)));

  static Future<Settings> load() async => Settings._(await SharedPreferences.getInstance());

  static const _backKey = 'backControl';

  final SharedPreferences _prefs;

  // The pad or button that goes back; null until one is picked in Settings.
  final ValueNotifier<BackControl?> backControl;

  Future<void> setBackControl(BackControl? control) {
    backControl.value = control;
    return control == null
        ? _prefs.remove(_backKey)
        : _prefs.setString(_backKey, control.encode());
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
