// The song after the one being played, for the "Next song" button at the end
// of a song. The song list wraps each song page it opens in one; a song page
// opened some other way has none, and shows no such button.

import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../widgets/key_badge.dart';

// The letter that picks "Next song" on every song page: F.
const nextSongPc = 5;

class SongQueue extends InheritedWidget {
  const SongQueue({
    super.key,
    required this.nextTitle,
    required this.openNext,
    required super.child,
  });

  final String nextTitle;

  // Replaces the page [context] is in with the next song.
  final void Function(BuildContext context) openNext;

  static SongQueue? of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<SongQueue>();

  @override
  bool updateShouldNotify(SongQueue oldWidget) => false;
}

// The "Next song" button for the end of a song, wearing its letter; nothing
// when the page was not opened from a song list. [scale] is uiScale: the
// button sits in scaled chrome, like the buttons beside it.
class NextSongButton extends StatelessWidget {
  const NextSongButton({super.key, required this.scale});

  final double scale;

  @override
  Widget build(BuildContext context) {
    final queue = SongQueue.of(context);
    if (queue == null) return const SizedBox.shrink();
    return FilledButton.tonalIcon(
      onPressed: () => queue.openNext(context),
      style: keyButtonStyle(scale),
      icon: KeyBadge(pc: nextSongPc, size: 30 * scale),
      label: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 230 * scale),
        child: Text('Next: ${queue.nextTitle}', maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}
