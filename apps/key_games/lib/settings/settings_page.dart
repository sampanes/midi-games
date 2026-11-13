// Settings: the Back pad and the sound. C picks (or changes) the pad or
// button that goes back from any page; D forgets it; E shows the version and
// the licenses; F changes how the keys sound (it plays a few notes, to hear
// the change); G changes how loud a song's band is. Reached from the home
// menu with its last letter, so a TV box with no touch screen can set
// everything up from the keyboard alone.

import 'package:flutter/material.dart';

import '../app/about.dart';
import '../app/services.dart';
import '../app/settings.dart';
import '../widgets/menu_page.dart';
import 'learn_back_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final services = AppServices.of(context);
    final settings = services.settings;
    T after<T>(List<T> values, T now) => values[(values.indexOf(now) + 1) % values.length];
    return ListenableBuilder(
      listenable: Listenable.merge([settings.backControl, settings.keySound, settings.bandLevel]),
      builder: (context, _) {
        final back = settings.backControl.value;
        final sound = settings.keySound.value;
        final band = settings.bandLevel.value;
        return MenuPage(
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
            MenuItem(
              title: 'Key sound',
              subtitle: 'Now ${sound.label}. Press to change',
              icon: Icons.piano,
              colors: const [Color(0xFFFF9A1F), Color(0xFFFF5EC8)],
              onPick: (_) {
                settings.setKeySound(after(KeySound.values, sound));
                // A few notes in the new sound, once the pick's own blip is over.
                services.synth.tune(const [60, 64, 67, 72], stepMs: 260, lengthMs: 420);
              },
            ),
            MenuItem(
              title: 'Band',
              subtitle: 'Now ${band.label}. The music under a song',
              icon: Icons.queue_music,
              colors: const [Color(0xFF8A4DFF), Color(0xFF4A6BFF)],
              onPick: (_) => settings.setBandLevel(after(BandLevel.values, band)),
            ),
          ],
          footer: back == null
              ? 'No Back pad picked: any pad goes back.'
              : 'Back is ${back.label}.',
        );
      },
    );
  }
}
