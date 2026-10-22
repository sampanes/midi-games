// The app's colors, type and theme in one place. Note colors come from the
// pitch-class table in color_keys_rules.dart; everything else is here.

import 'dart:math';

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
// TV box, 2 on a full-screen 1080p PC, and past that it keeps growing with
// the screen, so a 1440p PC (2.67) or a 4K one at 100% (4) looks like the
// 1080p one, only sharper. The two screens that matter are a phone on its
// side (scale 1) and a PC on a TV. Headers, chips, badges, hints and menu
// tiles grow with it so they read from a couch. Game boards fill the screen
// and use it only for the phone-sized caps on their parts (lane widths,
// letters, the keyboard picture's height).
double uiScale(BuildContext context) {
  final side = MediaQuery.sizeOf(context).shortestSide;
  return side > 1080 ? min(side / 540, 4.0) : (side / 480).clamp(1.0, 2.0);
}

// Height of the keyboard picture at the bottom of a game: [design] at phone
// size, grown with the screen, never more than [share] of the screen.
double pianoStripHeight(BuildContext context, {double design = 180, double share = 0.24}) =>
    min(design * uiScale(context), MediaQuery.sizeOf(context).height * share);

// A button that carries a key badge of 30 * [scale]: its padding grows with
// the badge, since Material buttons grow their text but not their padding.
ButtonStyle keyButtonStyle(double scale) => ButtonStyle(
      padding: WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 18 * scale, vertical: 6 * scale),
      ),
    );

// The bundled typeface (assets/fonts, SIL Open Font License). Text drawn on
// a canvas (TextPainter) does not inherit the theme, so painters name it.
const fontFamily = 'Nunito';

ThemeData keyGamesTheme() => ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      fontFamily: fontFamily,
      scaffoldBackgroundColor: AppColors.background,
    );
