// The frame every screen shares: the background, the player's keys routed to
// this page while it is on top, a header row (a back button when there is
// somewhere to go back to, the page's own header widgets, the keyboard
// status chip), the body, anything below the body (the keyboard picture),
// and overlays (sparks, the win banner) above everything.

import 'package:flutter/material.dart';

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
  // the status chip (give one of them an Expanded).
  final String? title;
  final List<Widget> header;
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
                    padding: headerPadding,
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
                        const Flexible(child: KeyboardStatus()),
                      ],
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
