// Song picker: one big card per bundled song, with its first notes as
// colored dots so even non-readers can tell songs apart. Each card wears a
// note letter (C D E F G A); pressing it on the keyboard starts the song, and
// B turns to the next page when there are more than seven songs.

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../audio/synth.dart';
import '../games/color_keys_rules.dart';
import '../games/difficulty.dart';
import '../midi/midi_input.dart';
import '../widgets/key_nav.dart';
import '../widgets/keyboard_status.dart';
import 'song.dart';
import 'song_play_page.dart';

class SongListPage extends StatefulWidget {
  const SongListPage({
    super.key,
    required this.synth,
    required this.midi,
    this.difficulty = Difficulty.easy,
  });

  final Synth synth;
  final MidiInput midi;
  final Difficulty difficulty;

  @override
  State<SongListPage> createState() => _SongListPageState();
}

// The white-key letters C D E F G A B as pitch classes.
const _letters = [0, 2, 4, 5, 7, 9, 11];
const _nextPagePc = 11;

// Songs on one page: all seven letters when they fit, else six plus B for
// the next page.
int songsPerPage(int count) => count <= _letters.length ? _letters.length : _letters.length - 1;

class _SongListPageState extends State<SongListPage> {
  List<Song>? _songs;
  Object? _error;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    loadSongs(rootBundle).then(
      (songs) {
        if (mounted) setState(() => _songs = songs);
      },
      onError: (Object error) {
        if (mounted) setState(() => _error = error);
      },
    );
  }

  List<Song> get _all => _songs ?? const [];
  int get _perPage => songsPerPage(_all.length);
  int get _pages => (_all.length / _perPage).ceil();
  List<Song> get _pageSongs => _all.skip(_page * _perPage).take(_perPage).toList();

  void _nextPage() => setState(() => _page = (_page + 1) % _pages);

  Map<int, VoidCallback> get _picks {
    final songs = _pageSongs;
    return {
      for (var i = 0; i < songs.length; i++) _letters[i]: () => _open(songs[i]),
      if (_pages > 1) _nextPagePc: _nextPage,
    };
  }

  void _open(Song song) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => SongPlayPage(
          song: song,
          synth: widget.synth,
          midi: widget.midi,
          difficulty: widget.difficulty,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF14111C),
      body: KeyNav(
        midi: widget.midi,
        picks: _picks,
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
                child: Row(
                  children: [
                    const BackButton(),
                    Expanded(
                      child: Text('Songs: ${widget.difficulty.label}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
                    ),
                    Flexible(child: KeyboardStatus(midi: widget.midi)),
                  ],
                ),
              ),
              Expanded(child: _buildSongs()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSongs() {
    if (_error != null) return Center(child: Text('Could not load songs: $_error'));
    final songs = _songs;
    if (songs == null) return const Center(child: CircularProgressIndicator());
    if (songs.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No songs in this build. Put .mid files in private/songs, run '
            'scripts/extract-melodies.py, and rebuild the app.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final pageSongs = _pageSongs;
    return GridView(
      // Fixed height: two-line titles must fit on narrow phone columns too.
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 360,
        mainAxisExtent: 124,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
      ),
      padding: const EdgeInsets.all(12),
      children: [
        for (var i = 0; i < pageSongs.length; i++)
          _SongCard(song: pageSongs[i], pc: _letters[i], onTap: () => _open(pageSongs[i])),
        if (_pages > 1) _NextPageCard(page: _page, pages: _pages, onTap: _nextPage),
      ],
    );
  }
}

class _SongCard extends StatelessWidget {
  const _SongCard({required this.song, required this.pc, required this.onTap});

  final Song song;
  final int pc;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF241F30),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  KeyBadge(pc: pc, size: 40),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(song.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  ),
                ],
              ),
              Row(
                children: [
                  // As many dots as fit; narrow cards (phones) cut the rest.
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const NeverScrollableScrollPhysics(),
                      child: Row(
                        children: [
                          for (final n in song.notes.take(min(8, song.notes.length)))
                            Padding(
                              padding: const EdgeInsets.only(right: 5),
                              child: CircleAvatar(
                                radius: 9,
                                backgroundColor: Color(pitchClasses[pitchClass(n.note)].argb),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('${song.notes.length} notes', style: const TextStyle(color: Colors.white54)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NextPageCard extends StatelessWidget {
  const _NextPageCard({required this.page, required this.pages, required this.onTap});

  final int page;
  final int pages;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF1B1724),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              const KeyBadge(pc: _nextPagePc, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Text('More songs (page ${page + 1} of $pages)',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white70)),
              ),
              const Icon(Icons.arrow_forward_rounded, size: 32, color: Colors.white70),
            ],
          ),
        ),
      ),
    );
  }
}
