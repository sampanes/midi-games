import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/services.dart';
import '../app/theme.dart';
import '../games/color_keys_rules.dart';
import '../widgets/game_page.dart';
import 'song.dart';

// A personal list can include songs whose note data hasn't been added yet.
class KnownSongsPage extends StatefulWidget {
  const KnownSongsPage({super.key, this.songs});
  final List<Song>? songs;

  @override
  State<KnownSongsPage> createState() => _KnownSongsPageState();
}

class _KnownSongsPageState extends State<KnownSongsPage> {
  static const _letters = [0, 2, 4, 5, 7];
  List<Song>? _songs;
  String? _error;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    if (widget.songs != null) {
      _songs = widget.songs;
    } else {
      loadSongs(rootBundle).then(
        (songs) {
          if (mounted) setState(() => _songs = songs);
        },
        onError: (Object _) {
          if (mounted) {
            setState(() => _error = 'Could not load the song library.');
          }
        },
      );
    }
  }

  Song? _findSong(String title) {
    for (final song in _songs ?? const <Song>[]) {
      if (song.title.toLowerCase() == title.toLowerCase()) return song;
    }
    return null;
  }

  Future<void> _add() async {
    var entered = '';
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add a song'),
        content: TextField(
          onChanged: (value) => entered = value,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Song title'),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, entered),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (!mounted || title == null || title.trim().isEmpty) return;
    final settings = AppServices.of(context).settings;
    final clean = title.trim();
    if (settings.knownSongs.value.any(
      (s) => s.toLowerCase() == clean.toLowerCase(),
    )) {
      return;
    }
    await settings.setKnownSongs([...settings.knownSongs.value, clean]);
  }

  Future<void> _remove(String title) async {
    final settings = AppServices.of(context).settings;
    await settings.setKnownSongs([
      for (final s in settings.knownSongs.value)
        if (s != title) s,
    ]);
    if (mounted) {
      setState(
        () => _page = min(
          _page,
          max(0, (settings.knownSongs.value.length - 1) ~/ 5),
        ),
      );
    }
  }

  void _open(String title) {
    if (_songs == null) return;
    final song = _findSong(title);
    if (song != null) {
      Navigator.push(
        context,
        MaterialPageRoute<void>(builder: (_) => SongGuidePage(song: song)),
      );
      return;
    }
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: const Text(
          'Saved to your list. Add this song to your local song library to see its notes.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _remove(title);
            },
            child: const Text('Remove'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = AppServices.of(context).settings;
    return ValueListenableBuilder<List<String>>(
      valueListenable: settings.knownSongs,
      builder: (context, titles, _) {
        final pages = max(1, (titles.length / 5).ceil());
        final page = _page.clamp(0, pages - 1);
        final visible = titles.skip(page * 5).take(5).toList();
        void next() => setState(() => _page = (page + 1) % pages);
        final picks = <int, VoidCallback>{
          for (var i = 0; i < visible.length; i++)
            _letters[i]: () => _open(visible[i]),
          9: _add,
          if (pages > 1) 11: next,
        };
        return GamePage(
          title: 'My songs',
          picks: picks,
          navigationLabels: {
            for (var i = 0; i < visible.length; i++) _letters[i]: visible[i],
            9: 'Add a song',
            if (pages > 1) 11: 'Next page',
          },
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Save songs you want to remember. Open one to follow the keys.',
                style: TextStyle(fontSize: 18),
              ),
              if (_error != null) Text(_error!),
              if (_songs == null && _error == null)
                const LinearProgressIndicator(),
              for (var i = 0; i < visible.length; i++)
                Card(
                  child: ListTile(
                    leading: Text(pitchClasses[_letters[i]].name),
                    title: Text(visible[i]),
                    subtitle: Text(
                      _songs == null
                          ? 'Checking library...'
                          : _findSong(visible[i]) == null
                          ? 'Notes not added yet'
                          : 'Ready to practice',
                    ),
                    onTap: _songs == null ? null : () => _open(visible[i]),
                    trailing: IconButton(
                      tooltip: 'Remove ${visible[i]}',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _remove(visible[i]),
                    ),
                  ),
                ),
              FilledButton.icon(
                onPressed: _add,
                icon: const Icon(Icons.add),
                label: const Text('Add a song'),
              ),
              if (pages > 1)
                TextButton(
                  onPressed: next,
                  child: Text('Next page (${page + 1} of $pages)'),
                ),
            ],
          ),
        );
      },
    );
  }
}

// A scrollable reference: time moves downward; each vertical lane is a key.
class SongGuidePage extends StatelessWidget {
  const SongGuidePage({super.key, required this.song});
  final Song song;

  @override
  Widget build(BuildContext context) {
    final notes = song.guideNotes ?? song.notes;
    return GamePage(
      title: song.title,
      body: notes.isEmpty
          ? const Center(child: Text('No notes available yet.'))
          : PianoRoll(
              notes: notes,
              description: song.guideDescription ?? 'Extracted single-note line. Timing and octaves may have been simplified.',
            ),
    );
  }
}

class PianoRoll extends StatelessWidget {
  const PianoRoll({super.key, required this.notes, required this.description});
  final List<SongNote> notes;
  final String description;

  static const laneWidth = 8.0;
  static const axisWidth = 30.0;
  static const pixelsPerSecond = 56.0;

  static String noteName(int note) {
    const names = [
      'C',
      'C#',
      'D',
      'D#',
      'E',
      'F',
      'F#',
      'G',
      'G#',
      'A',
      'A#',
      'B',
    ];
    return '${names[pitchClass(note)]}${note ~/ 12 - 1}';
  }

  @override
  Widget build(BuildContext context) {
    final first = notes.map((n) => n.note).reduce(min);
    final last = notes.map((n) => n.note).reduce(max);
    final firstClass = pitchClass(first);
    final lastClass = pitchClass(last);
    // Finish the two- or three-black-key group at each end, including unused
    // keys. Even a one-note song gets enough context to find it by sight.
    final low = first - (firstClass <= 4 ? firstClass : firstClass - 5);
    final high = min(
      127,
      last + (lastClass <= 4 ? 4 - lastClass : 11 - lastClass),
    );
    final pitches = List<int>.generate(high - low + 1, (i) => low + i);
    final duration = notes.map((n) => n.startMs + n.lengthMs).reduce(max);
    final height = max(120.0, duration / 1000 * pixelsPerSecond + 24);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(
            'Read top to bottom. Bar length = hold time.\n$description',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: Colors.white70),
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = max(
                constraints.maxWidth,
                axisWidth + pitches.length * laneWidth,
              );
              final actualLaneWidth = (width - axisWidth) / pitches.length;
              return Scrollbar(
                notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: width,
                    child: Column(
                      children: [
                        SizedBox(
                          height: 34,
                          child: Row(
                            children: [
                              const SizedBox(
                                width: axisWidth,
                                child: Center(child: Text('time')),
                              ),
                              for (final pitch in pitches)
                                SizedBox(
                                  width: actualLaneWidth,
                                  child: _RollKeyHeader(
                                    key: ValueKey('roll-note-$pitch'),
                                    pitch: pitch,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Scrollbar(
                            child: SingleChildScrollView(
                              key: const ValueKey('song-roll-scroll'),
                              child: CustomPaint(
                                key: const ValueKey('song-roll'),
                                size: Size(width, height),
                                painter: _RollPainter(
                                  notes,
                                  pitches,
                                  actualLaneWidth,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        if (pitches.length * laneWidth + axisWidth >
            MediaQuery.sizeOf(context).width)
          const Padding(
            padding: EdgeInsets.all(6),
            child: Text(
              'Swipe sideways to see more keys',
              style: TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ),
      ],
    );
  }
}

// A non-interactive key reference: bars below align with these same lanes.
class _RollKeyHeader extends StatelessWidget {
  const _RollKeyHeader({super.key, required this.pitch});
  final int pitch;

  @override
  Widget build(BuildContext context) {
    final info = pitchClasses[pitchClass(pitch)];
    return Semantics(
      label: PianoRoll.noteName(pitch),
      child: Align(
        alignment: Alignment.topCenter,
        child: Container(
          height: info.white ? 34 : 23,
          decoration: BoxDecoration(
            color: info.white
                ? const Color(0xFFF4F1EC)
                : const Color(0xFF141219),
            border: Border.all(
              color: info.white ? Colors.black38 : Colors.white54,
              width: .5,
            ),
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(2),
            ),
          ),
          alignment: info.white ? Alignment.bottomCenter : Alignment.center,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              info.name,
              maxLines: 1,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: info.white ? Colors.black : Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RollPainter extends CustomPainter {
  _RollPainter(this.notes, this.pitches, this.laneWidth);
  final List<SongNote> notes;
  final List<int> pitches;
  final double laneWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final clip = canvas.getLocalClipBounds().intersect(Offset.zero & size);
    if (clip.isEmpty) return;
    final paint = Paint();
    for (var i = 0; i < pitches.length; i++) {
      paint.color = pitchClasses[pitchClass(pitches[i])].white
          ? const Color(0xFF282331)
          : const Color(0xFF17141E);
      canvas.drawRect(
        Rect.fromLTWH(
          PianoRoll.axisWidth + i * laneWidth,
          clip.top,
          laneWidth - 1,
          clip.height,
        ),
        paint,
      );
    }
    final startSecond = max(0, (clip.top / PianoRoll.pixelsPerSecond).floor());
    final endSecond = (clip.bottom / PianoRoll.pixelsPerSecond).ceil();
    for (var second = startSecond; second <= endSecond; second++) {
      final y = second * PianoRoll.pixelsPerSecond;
      paint.color = Colors.white.withValues(alpha: second % 5 == 0 ? .3 : .1);
      canvas.drawRect(
        Rect.fromLTWH(
          PianoRoll.axisWidth,
          y,
          size.width - PianoRoll.axisWidth,
          1,
        ),
        paint,
      );
      if (second % 5 == 0) {
        final label = TextPainter(
          text: TextSpan(
            text: '${second ~/ 60}:${(second % 60).toString().padLeft(2, '0')}',
            style: const TextStyle(color: Colors.white70, fontSize: 10),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: PianoRoll.axisWidth - 4);
        label.paint(canvas, Offset(2, y + 2));
      }
    }
    final columns = {for (var i = 0; i < pitches.length; i++) pitches[i]: i};
    for (final note in notes) {
      final y = note.startMs / 1000 * PianoRoll.pixelsPerSecond;
      final h = max(3.0, note.lengthMs / 1000 * PianoRoll.pixelsPerSecond);
      if (y + h < clip.top || y > clip.bottom) continue;
      final x = PianoRoll.axisWidth + columns[note.note]! * laneWidth;
      paint.color = noteColor(note.note);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x + 2, y, laneWidth - 4, h),
          const Radius.circular(3),
        ),
        paint,
      );
      paint.color = Colors.white.withValues(alpha: .75);
      canvas.drawRect(Rect.fromLTWH(x + 3, y, laneWidth - 6, min(2, h)), paint);
    }
  }

  @override
  bool shouldRepaint(_RollPainter oldWidget) =>
      oldWidget.notes != notes ||
      oldWidget.pitches != pitches ||
      oldWidget.laneWidth != laneWidth;
}
