// The app's colors and theme in one place. Note colors come from the
// pitch-class table in color_keys_rules.dart; everything else is here.

import 'package:flutter/material.dart';

import '../games/color_keys_rules.dart';

abstract final class AppColors {
  static const background = Color(0xFF14111C);
  static const starGold = Color(0xFFFFD84A);
  static const red = Color(0xFFFF3B3B);

  // Dark text on a bright key color.
  static const ink = Color(0xFF2A2233);

  // A key, tile or bubble drawn with no color (letter-only levels).
  static const plain = Color(0xFF4A4360);

  // The hidden mystery note in Ear Notes.
  static const mystery = Color(0xFF3A3448);

  static const card = Color(0xFF241F30);
  static const groupCard = Color(0xFF2B2440);
  static const quietCard = Color(0xFF1B1724);
}

Color pitchColor(int pc) => Color(pitchClasses[pc].argb);

Color noteColor(int note) => pitchColor(pitchClass(note));

ThemeData keyGamesTheme() => ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.background,
    );
