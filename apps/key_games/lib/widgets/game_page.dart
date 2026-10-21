// The frame every screen shares: the background, the player's keys routed to
// this page while it is on top, a header row (a back button when there is
// somewhere to go back to, the page's own header widgets, the keyboard
// status at the right edge), the body, anything below the body (the keyboard
// picture), and overlays (sparks, the win banner) above everything.
//
// The header row is scaled by uiScale: its text, icons and chips grow with
// the screen, so a page's header widgets are written at phone size.

import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../input/note_focus.dart';
import '../midi/midi_input.dart';
import 'keyboard_status.dart';

class GamePage extends StatelessWidget {
  const GamePage({
    super.key,
    this.title,
    this.header = const [],
    this.headerPadding = const EdgeInsets.fromLTRB(8, 8, 16, 4),
    required this.body,
    this.footer = const [],
    this.backdrop,
    this.overlays = const [],
    this.picks = const {},
    this.onNote,
  });

  // A plain title, or custom [header] widgets between the back button and
  // the keyboard status (give one of them an Expanded).
  final String? title;
  final List<Widget> header;

  // At phone size; scaled with the screen like the header itself.
  final EdgeInsets headerPadding;
  final Widget body;
  final List<Widget> footer;

  // Painted behind the page (a tinted gradient).
  final Widget? backdrop;
  final List<Widget> overlays;

  // Pitch class -> action for letters that choose something on this page.
  final Map<int, VoidCallback> picks;
  final void Function(NoteEvent event)? onNote;

  @override
  Widget build(BuildContext context) {
    final scale = uiScale(context);
    return Scaffold(
      body: NoteFocus(
        picks: picks,
        onNote: onNote,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ?backdrop,
            SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: headerPadding * scale,
                    child: ScaledChrome(
                      scale: scale,
                      child: Row(
                        children: [
                          if (Navigator.canPop(context)) const BackButton(),
                          if (title != null)
                            Expanded(
                              child: Text(
                                title!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
                              ),
                            ),
                          ...header,
                          const SizedBox(width: 8),
                          const KeyboardStatus(),
                        ],
                      ),
                    ),
                  ),
                  Expanded(child: body),
                  ...footer,
                ],
              ),
            ),
            ...overlays,
          ],
        ),
      ),
    );
  }
}

// Scales the text and icons of its child by [scale]: the header and footer
// chrome of a page, written at phone size, grows with the screen.
class ScaledChrome extends StatelessWidget {
  const ScaledChrome({super.key, required this.scale, required this.child});

  final double scale;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return MediaQuery(
      data: media.copyWith(textScaler: TextScaler.linear(scale)),
      child: IconTheme.merge(
        data: IconThemeData(size: 24 * scale),
        child: child,
      ),
    );
  }
}
