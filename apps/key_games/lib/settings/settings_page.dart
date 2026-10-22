// Settings: the Back pad. C picks (or changes) the pad or button that goes
// back from any page; D forgets it; E shows the version and the licenses.
// Reached from the home menu with G, so a TV box with no touch screen can
// set it up from the keyboard alone.

import 'package:flutter/material.dart';

import '../app/about.dart';
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
                ? 'Any pad goes back now. Pick just one'
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
                ? 'No Back pad is picked'
                : 'Any pad goes back again',
            icon: Icons.block,
            colors: const [Color(0xFF4A4360), Color(0xFF2B2440)],
            onPick: (_) => settings.setBackControl(null),
          ),
          MenuItem(
            title: 'About',
            subtitle: '$appName $appVersion. Licenses',
            icon: Icons.info_outline_rounded,
            colors: const [Color(0xFF22C9A0), Color(0xFF2FA8FF)],
            onPick: showAbout,
          ),
        ],
        footer: back == null
            ? 'No Back pad picked: any pad goes back.'
            : 'Back is ${back.label}.',
      ),
    );
  }
}
