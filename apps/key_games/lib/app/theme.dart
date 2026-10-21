// The app's colors, type and theme in one place. Note colors come from the
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

// How much bigger than a phone the screen is: 1 on a phone, 1.5 on a 1080p
// TV box, 2 on a full-screen PC. Headers, chips, badges, hints and menu
// tiles grow with it so they read from a couch. Game boards and keyboard
// pictures already size themselves from the screen and do not use it.
double uiScale(BuildContext context) =>
    (MediaQuery.sizeOf(context).shortestSide / 480).clamp(1.0, 2.0);

// The bundled typeface (assets/fonts, SIL Open Font License).
const fontFamily = 'Nunito';

ThemeData keyGamesTheme() => ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      fontFamily: fontFamily,
      scaffoldBackgroundColor: AppColors.background,
    );
