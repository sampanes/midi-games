// A menu screen of big tiles, each wearing a note letter (C D E F G A B):
// tap it or press that note on the keyboard. Used for the home categories,
// the game lists inside them, the difficulty pickers and Settings.

import 'dart:math';

import 'package:flutter/material.dart';

import '../app/services.dart';
import '../input/back_control.dart';
import 'game_page.dart';
import 'key_badge.dart';

// The white-key letters C D E F G A B as pitch classes.
const menuLetters = [0, 2, 4, 5, 7, 9, 11];

class MenuItem {
  const MenuItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.colors,
    required this.onPick,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> colors;
  final void Function(BuildContext context) onPick;
}

class MenuPage extends StatelessWidget {
  const MenuPage({
    super.key,
    required this.title,
    required this.items,
    this.footer,
  }) : assert(items.length <= 7);

  final String title;
  final List<MenuItem> items;

  // Replaces the standard "press a letter" line.
  final String? footer;

  @override
  Widget build(BuildContext context) {
    return GamePage(
      headerPadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      header: [
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900),
          ),
        ),
      ],
      picks: {
        for (var i = 0; i < items.length; i++) menuLetters[i]: () => items[i].onPick(context),
      },
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: _grid(context),
      ),
      footer: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: _Footer(text: footer, canPop: Navigator.canPop(context)),
        ),
      ],
    );
  }

  // One row when wide; on a tall screen, two columns once there are four or
  // more tiles.
  Widget _grid(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth > constraints.maxHeight;
        final columns = wide ? min(items.length, 4) : (items.length >= 4 ? 2 : 1);
        final rows = (items.length / columns).ceil();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var r = 0; r < rows; r++)
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var c = 0; c < columns; c++)
                      Expanded(
                        child: r * columns + c < items.length
                            ? Padding(
                                padding: const EdgeInsets.all(8),
                                child: _MenuTile(
                                  item: items[r * columns + c],
                                  pc: menuLetters[r * columns + c],
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

// How to pick and how to go back, in one line. The back half depends on
// whether a Back pad has been set in Settings.
class _Footer extends StatelessWidget {
  const _Footer({required this.text, required this.canPop});

  final String? text;
  final bool canPop;

  @override
  Widget build(BuildContext context) {
    final style = const TextStyle(color: Colors.white54);
    if (text != null) return Text(text!, textAlign: TextAlign.center, style: style);
    if (!canPop) {
      return Text('Press a letter on the keyboard to pick.', textAlign: TextAlign.center, style: style);
    }
    return ValueListenableBuilder<BackControl?>(
      valueListenable: AppServices.of(context).settings.backControl,
      builder: (context, back, _) => Text(
        back == null
            ? 'Press a letter to pick. To go back from the keyboard, set a Back pad in Settings.'
            : 'Press a letter to pick, or the Back pad to go back.',
        textAlign: TextAlign.center,
        style: style,
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({required this.item, required this.pc});

  final MenuItem item;
  final int pc;

  @override
  Widget build(BuildContext context) {
    return Material(
      borderRadius: BorderRadius.circular(28),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [for (final c in item.colors) c.withValues(alpha: 0.85)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: InkWell(
          onTap: () => item.onPick(context),
          child: Stack(
            children: [
              Positioned(top: 12, left: 12, child: KeyBadge(pc: pc, size: 52)),
              Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                    child: Column(
                      children: [
                        Icon(item.icon, size: 96, color: Colors.white),
                        const SizedBox(height: 8),
                        Text(item.title,
                            style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w900)),
                        Text(item.subtitle,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 18, color: Colors.white70)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
