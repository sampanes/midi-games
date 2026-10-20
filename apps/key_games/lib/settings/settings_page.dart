// Settings: the Back pad. C picks (or changes) the pad or button that goes
// back from any page; D forgets it. Reached from the home menu with G, so a
// TV box with no touch screen can set it up from the keyboard alone.

import 'package:flutter/material.dart';

import '../app/services.dart';
import '../input/back_control.dart';
import '../widgets/menu_page.dart';
import 'learn_back_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = AppServices.of(context).settings;
    return ValueListenableBuilder<BackControl?>(
      valueListenable: settings.backControl,
      builder: (context, back, _) => MenuPage(
        title: 'Settings',
        items: [
          MenuItem(
            title: 'Back pad',
            subtitle: back == null
                ? 'Pick a pad or button that goes back'
                : 'Now ${back.label}. Pick another',
            icon: Icons.undo_rounded,
            colors: const [Color(0xFF2FA8FF), Color(0xFF8A4DFF)],
            onPick: (context) => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const LearnBackPage()),
            ),
          ),
          MenuItem(
            title: 'Forget it',
            subtitle: back == null
                ? 'No Back pad is set'
                : 'Go back with the screen and the remote only',
            icon: Icons.block,
            colors: const [Color(0xFF4A4360), Color(0xFF2B2440)],
            onPick: (_) => settings.setBackControl(null),
          ),
        ],
        footer: back == null
            ? 'No Back pad yet: the screen and the remote go back.'
            : 'Back is ${back.label}.',
      ),
    );
  }
}
