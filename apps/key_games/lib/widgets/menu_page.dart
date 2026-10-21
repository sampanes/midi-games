// A menu screen of big tiles, each wearing a note letter (C D E F G A B):
// tap it or press that note on the keyboard. Used for the home menu, the
// game lists inside a category, the difficulty pickers and Settings.
//
// Tiles are cards, not billboards: a tile is never wider than a hand-sized
// card scaled to the screen (uiScale), nor much taller than it is wide, and
// everything drawn on it (badge, icon, title) scales with the tile. So one
// game on a TV is one big card in the middle, not a wall of gradient with a
// small icon lost in it.

import 'dart:math';

import 'package:flutter/material.dart';

import '../app/theme.dart';
import 'game_page.dart';
import 'key_badge.dart';
import 'keyboard_status.dart' show narrowHeaderWidth;

// The white-key letters C D E F G A B as pitch classes.
const menuLetters = [0, 2, 4, 5, 7, 9, 11];

// The tile's design size: its contents are drawn for a 300 x 300 tile and
// scaled from there. A tile is never wider than this times uiScale.
const _tileDesign = 300.0;

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

  // Two colors, top-left to bottom-right.
  final List<Color> colors;
  final void Function(BuildContext context) onPick;
}

class MenuPage extends StatelessWidget {
  const MenuPage({
    super.key,
    required this.title,
    required this.items,
    this.actions = const [],
    this.footer,
  }) : assert(items.length + actions.length <= 7);

  final String title;
  final List<MenuItem> items;

  // Small buttons in the header instead of tiles (Settings on the home
  // menu). They take the letters after the tiles.
  final List<MenuItem> actions;

  // A line under the tiles. By default the home menu says how to pick and
  // the other menus say nothing.
  final String? footer;

  @override
  Widget build(BuildContext context) {
    final scale = uiScale(context);
    final hint = footer ??
        (Navigator.canPop(context) ? null : 'Press a letter on the keyboard to pick.');
    return GamePage(
      headerPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      header: [
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900),
          ),
        ),
        for (var i = 0; i < actions.length; i++)
          _HeaderAction(item: actions[i], pc: menuLetters[items.length + i]),
      ],
      picks: {
        for (var i = 0; i < items.length; i++) menuLetters[i]: () => items[i].onPick(context),
        for (var i = 0; i < actions.length; i++)
          menuLetters[items.length + i]: () => actions[i].onPick(context),
      },
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8) * scale,
        child: _Grid(items: items),
      ),
      footer: [
        if (hint != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12) * scale,
            child: Text(
              hint,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15 * scale, color: Colors.white60),
            ),
          ),
      ],
    );
  }
}

// Rows of equal tiles, centered. One row when wide; on a tall screen, two
// columns once there are four or more tiles.
class _Grid extends StatelessWidget {
  const _Grid({required this.items});

  final List<MenuItem> items;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = uiScale(context);
        final count = items.length;
        final wide = constraints.maxWidth > constraints.maxHeight;
        final columns = wide ? min(count, 4) : (count >= 4 ? 2 : 1);
        final rows = (count / columns).ceil();
        final gap = 12 * scale;
        final cellWidth = (constraints.maxWidth - gap * (columns - 1)) / columns;
        final cellHeight = (constraints.maxHeight - gap * (rows - 1)) / rows;
        final width = min(cellWidth, _tileDesign * scale);
        final height = min(cellHeight, width * 1.25);
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var r = 0; r < rows; r++)
                Padding(
                  padding: EdgeInsets.only(top: r == 0 ? 0 : gap),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var c = 0; c < columns; c++)
                        if (r * columns + c < count)
                          Padding(
                            padding: EdgeInsets.only(left: c == 0 ? 0 : gap),
                            child: SizedBox(
                              width: width,
                              height: height,
                              child: _MenuTile(
                                item: items[r * columns + c],
                                pc: menuLetters[r * columns + c],
                              ),
                            ),
                          ),
                    ],
                  ),
                ),
            ],
          ),
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
    return LayoutBuilder(
      builder: (context, constraints) {
        // Everything on the tile is drawn for a 300 x 300 tile and scaled.
        final k = (min(constraints.maxWidth, constraints.maxHeight) / _tileDesign).clamp(0.5, 2.5);
        final radius = BorderRadius.circular(28 * k.clamp(0.7, 1.5));
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 16 * k, offset: Offset(0, 6 * k)),
            ],
          ),
          child: Material(
            borderRadius: radius,
            clipBehavior: Clip.antiAlias,
            child: Ink(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [for (final c in item.colors) c.withValues(alpha: 0.9)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: InkWell(
                onTap: () => item.onPick(context),
                focusColor: Colors.white24,
                hoverColor: Colors.white10,
                child: Stack(
                  children: [
                    Positioned(top: 12 * k, left: 12 * k, child: KeyBadge(pc: pc, size: 52 * k)),
                    // Below the badge; shrinks as a block on a short tile.
                    Padding(
                      padding: EdgeInsets.fromLTRB(16 * k, 68 * k, 16 * k, 14 * k),
                      child: Center(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: SizedBox(
                            width: constraints.maxWidth - 32 * k,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(item.icon, size: 96 * k, color: Colors.white),
                                SizedBox(height: 8 * k),
                                // A long name shrinks to fit rather than cutting off.
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    item.title,
                                    maxLines: 1,
                                    style: TextStyle(fontSize: 40 * k, fontWeight: FontWeight.w900, height: 1.1),
                                  ),
                                ),
                                SizedBox(height: 4 * k),
                                Text(
                                  item.subtitle,
                                  textAlign: TextAlign.center,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: max(12, 18 * k), color: Colors.white70, height: 1.25),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// A header button: the letter badge, the icon and the name in a pill (badge
// and icon only on a narrow phone).
class _HeaderAction extends StatelessWidget {
  const _HeaderAction({required this.item, required this.pc});

  final MenuItem item;
  final int pc;

  @override
  Widget build(BuildContext context) {
    final scale = uiScale(context);
    final narrow = MediaQuery.sizeOf(context).width < narrowHeaderWidth;
    return Padding(
      padding: EdgeInsets.only(left: 8 * scale),
      child: Material(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: () => item.onPick(context),
          borderRadius: BorderRadius.circular(999),
          focusColor: Colors.white24,
          hoverColor: Colors.white10,
          child: Padding(
            padding: EdgeInsets.fromLTRB(8 * scale, 8 * scale, (narrow ? 12 : 18) * scale, 8 * scale),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                KeyBadge(pc: pc, size: 32 * scale),
                SizedBox(width: 8 * scale),
                Icon(item.icon, color: Colors.white70),
                if (!narrow) ...[
                  SizedBox(width: 6 * scale),
                  Text(item.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
