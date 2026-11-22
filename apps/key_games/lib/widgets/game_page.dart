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

// True when the page [context] is in has a page under it to go back to.
// Asked of the page's own route, not of the navigator: a page rebuilt while
// another covers it (the home menu, when a setting changes) must not grow a
// back button.
bool hasPageBelow(BuildContext context) => !(ModalRoute.of(context)?.isFirst ?? true);

class GamePage extends StatefulWidget {
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
    this.navigationLabels = const {},
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
  // Labels for choices that can be reached with C# and A#.
  final Map<int, String> navigationLabels;
  final void Function(NoteEvent event)? onNote;

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> {
  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    final labels = widget.navigationLabels;
    final keys = [for (final key in labels.keys) if (widget.picks.containsKey(key)) key];
    final selected = keys.isEmpty ? null : keys[_selected % keys.length];
    final scale = uiScale(context);
    return Scaffold(
      body: NoteFocus(
        picks: {
          ...widget.picks,
          if (selected != null) 1: () => setState(() => _selected = (_selected + 1) % keys.length),
          if (selected != null) 10: () => widget.picks[selected]!(),
        },
        onNote: widget.onNote,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ?widget.backdrop,
            SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: widget.headerPadding * scale,
                    child: NavigationSelection(
                      selected: selected,
                      child: ScaledChrome(
                        scale: scale,
                        child: Row(
                          children: [
                            if (hasPageBelow(context)) const BackButton(),
                            if (widget.title != null)
                              Expanded(
                                child: Text(
                                  widget.title!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
                                ),
                              ),
                            ...widget.header,
                            const SizedBox(width: 8),
                            const KeyboardStatus(),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (selected != null)
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12 * scale, vertical: 4 * scale),
                      child: Text(
                        'C#/Db: next  |  A#/Bb: select  |  Selected: ${labels[selected]}',
                        key: const ValueKey('navigation-hint'),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 14 * scale, color: Colors.white),
                      ),
                    ),
                  Expanded(child: NavigationSelection(selected: selected, child: widget.body)),
                  ...widget.footer,
                ],
              ),
            ),
            ...widget.overlays,
          ],
        ),
      ),
    );
  }
}

// Lets menu cards show which choice the black keys will select.
class NavigationSelection extends InheritedWidget {
  const NavigationSelection({super.key, required this.selected, required super.child});

  final int? selected;

  static bool isSelected(BuildContext context, int pc) =>
      context.dependOnInheritedWidgetOfExactType<NavigationSelection>()?.selected == pc;

  @override
  bool updateShouldNotify(NavigationSelection oldWidget) => selected != oldWidget.selected;
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
