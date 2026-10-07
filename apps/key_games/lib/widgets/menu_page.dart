// A menu screen of big tiles, each wearing a note letter (C D E F G A B):
// tap it or press that note on the keyboard. Used for the home categories,
// the game lists inside them, and the difficulty pickers.

import 'dart:math';

import 'package:flutter/material.dart';

import '../midi/midi_input.dart';
import 'key_nav.dart';
import 'keyboard_status.dart';

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
    required this.midi,
    required this.items,
    this.footer,
  }) : assert(items.length <= 7);

  final String title;
  final MidiInput midi;
  final List<MenuItem> items;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.canPop(context);
    return Scaffold(
      backgroundColor: const Color(0xFF14111C),
      body: KeyNav(
        midi: midi,
        picks: {
          for (var i = 0; i < items.length; i++) menuLetters[i]: () => items[i].onPick(context),
        },
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    if (canPop) const BackButton(),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900),
                      ),
                    ),
                    Flexible(child: KeyboardStatus(midi: midi)),
                  ],
                ),
                const SizedBox(height: 16),
                Expanded(child: _grid(context)),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    footer ??
                        (canPop
                            ? 'Press a letter to pick. Hold the lowest and highest C together to go back.'
                            : 'Press a letter on the keyboard to pick.'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white54),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
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
