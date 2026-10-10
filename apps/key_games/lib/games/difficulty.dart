// Four difficulty levels shared by every game, so all ages can play the same
// game: each game says what each level changes (see the descriptions passed
// to difficultyPage). Picked with C D E F on the keyboard.

import 'package:flutter/material.dart';

import '../midi/midi_input.dart';
import '../widgets/menu_page.dart';

enum Difficulty {
  easy('Easy', 'Ages 3+', Icons.child_care, [Color(0xFF3DDC4A), Color(0xFF22C9A0)]),
  medium('Medium', 'Ages 5+', Icons.emoji_people, [Color(0xFF2FA8FF), Color(0xFF4A6BFF)]),
  hard('Hard', 'Ages 8+', Icons.local_fire_department, [Color(0xFFFF9A1F), Color(0xFFFF6A2B)]),
  expert('Expert', 'Grown-ups', Icons.workspace_premium, [Color(0xFFFF3B3B), Color(0xFFC04DFF)]);

  const Difficulty(this.label, this.ages, this.icon, this.colors);

  final String label;
  final String ages;
  final IconData icon;
  final List<Color> colors;

  bool atLeast(Difficulty other) => index >= other.index;
}

// A difficulty picker for one game. Picking replaces the picker with the
// game, so going back from the game returns to the game's menu. Only the
// levels in [descriptions] are offered; [labels] renames a level for a game
// whose levels are different ways to play (Key Rush: Easy and Real).
Widget difficultyPage({
  required String title,
  required MidiInput midi,
  required Map<Difficulty, String> descriptions,
  Map<Difficulty, String> labels = const {},
  required Widget Function(Difficulty difficulty) game,
}) {
  return MenuPage(
    title: title,
    midi: midi,
    items: [
      for (final d in Difficulty.values)
        if (descriptions.containsKey(d))
          MenuItem(
            title: labels[d] ?? d.label,
            subtitle: '${d.ages}\n${descriptions[d] ?? ''}',
            icon: d.icon,
            colors: d.colors,
            onPick: (context) => Navigator.pushReplacement(
              context,
              MaterialPageRoute<void>(builder: (_) => game(d)),
            ),
          ),
    ],
  );
}
