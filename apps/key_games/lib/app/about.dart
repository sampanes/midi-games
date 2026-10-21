// What the app says about itself: its version (kept in step with
// pubspec.yaml by a test) and the licenses page, where the typeface's
// license and every package's license are listed.

import 'package:flutter/material.dart';

const appName = 'Key Games';
const appVersion = '0.2.0';

void showAbout(BuildContext context) {
  showLicensePage(
    context: context,
    applicationName: appName,
    applicationVersion: appVersion,
    applicationLegalese: 'Games for a MIDI keyboard. The typeface is Nunito, '
        'under the SIL Open Font License (below, with every other license).',
  );
}
