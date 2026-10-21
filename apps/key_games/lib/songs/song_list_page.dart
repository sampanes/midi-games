// Song picker: one big card per bundled song, with its first notes as
// colored dots so even non-readers can tell songs apart. Each card wears a
// note letter (C D E F G A); pressing it on the keyboard starts the song, and
// B turns to the next page when there are more than seven songs. When the
// songs come in more than one group (Kids, Classical, ...), the groups are
// picked first the same way, and Back returns to them.

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/theme.dart';
import '../games/difficulty.dart';
import '../widgets/game_page.dart';
import '../widgets/key_badge.dart';
import 'song.dart';
import 'song_play_page.dart';

class SongListPage extends StatefulWidget {
  const SongListPage({
    super.key,
    this.difficulty = Difficulty.easy,
    this.title = 'Songs',
    this.play,
    this.group,
    this.songs,
    this.levels = true,
  });

  final Difficulty difficulty;
  final String title;

  // The game a picked song opens; song steps when not given.
  final Widget Function(Song song)? play;

  // Only this group's songs, from [songs] (already loaded).
  final String? group;
  final List<Song>? songs;

  // False for a list without difficulty levels (the heading then says
  // "All songs" instead of the level).
  final bool levels;

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
    if (widget.songs != null) {
      _songs = widget.songs;
      return;
    }
    loadSongs(rootBundle).then(
      (songs) {
        if (mounted) setState(() => _songs = songs);
      },
      onError: (Object error) {
        if (mounted) setState(() => _error = error);
      },
    );
  }

  List<Song> get _loaded => _songs ?? const [];
  List<String> get _groups => widget.group == null ? songGroups(_loaded) : const [];

  // Group cards first when there is more than one group.
  bool get _picksGroup => _groups.length > 1;

  List<Song> get _all => widget.group == null
      ? _loaded
      : [for (final song in _loaded) if (song.group == widget.group) song];

  // The cards on offer: groups or songs.
  int get _count => _picksGroup ? _groups.length : _all.length;
  int get _perPage => songsPerPage(_count);
  int get _pages => max(1, (_count / _perPage).ceil());
  Iterable<int> get _pageItems => Iterable<int>.generate(_count).skip(_page * _perPage).take(_perPage);

  void _nextPage() => setState(() => _page = (_page + 1) % _pages);

  void _pick(int item) => _picksGroup ? _openGroup(_groups[item]) : _open(_all[item]);

  Map<int, VoidCallback> get _picks {
    final items = _pageItems.toList();
    return {
      for (var i = 0; i < items.length; i++) _letters[i]: () => _pick(items[i]),
      if (_pages > 1) _nextPagePc: _nextPage,
    };
  }

  void _openGroup(String group) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => SongListPage(
          difficulty: widget.difficulty,
          title: widget.title,
          play: widget.play,
          group: group,
          songs: _loaded,
          levels: widget.levels,
        ),
      ),
    );
  }

  void _open(Song song) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) =>
            widget.play?.call(song) ?? SongPlayPage(song: song, difficulty: widget.difficulty),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GamePage(
      title: '${widget.title}: '
          '${widget.group ?? (widget.levels ? widget.difficulty.label : 'All songs')}',
      headerPadding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
      picks: _picks,
      body: _buildSongs(),
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
          child: Text('No songs yet.', textAlign: TextAlign.center, style: TextStyle(fontSize: 22)),
        ),
      );
    }
    final items = _pageItems.toList();
    final scale = uiScale(context);
    return GridView(
      // Fixed height: two-line titles must fit on narrow phone columns too.
      // Cards grow with the screen like the header does.
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 360 * scale,
        mainAxisExtent: 124 * scale,
        mainAxisSpacing: 12 * scale,
        crossAxisSpacing: 12 * scale,
      ),
      padding: EdgeInsets.all(12 * scale),
      children: [
        for (var i = 0; i < items.length; i++)
          if (_picksGroup)
            _GroupCard(
              group: _groups[items[i]],
              songs: [for (final song in _all) if (song.group == _groups[items[i]]) song],
              pc: _letters[i],
              onTap: () => _pick(items[i]),
            )
          else
            _SongCard(song: _all[items[i]], pc: _letters[i], onTap: () => _pick(items[i])),
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
    final s = uiScale(context);
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(18 * s),
      child: InkWell(
        borderRadius: BorderRadius.circular(18 * s),
        onTap: onTap,
        focusColor: Colors.white24,
        child: Padding(
          padding: EdgeInsets.all(14 * s),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  KeyBadge(pc: pc, size: 40 * s),
                  SizedBox(width: 12 * s),
                  Expanded(
                    child: Text(song.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 18 * s, fontWeight: FontWeight.w800)),
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
                              padding: EdgeInsets.only(right: 5 * s),
                              child: CircleAvatar(
                                radius: 9 * s,
                                backgroundColor: noteColor(n.note),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(width: 8 * s),
                  Text('${song.notes.length} notes',
                      style: TextStyle(fontSize: 14 * s, color: Colors.white54)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.group, required this.songs, required this.pc, required this.onTap});

  final String group;
  final List<Song> songs;
  final int pc;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = uiScale(context);
    return Material(
      color: AppColors.groupCard,
      borderRadius: BorderRadius.circular(18 * s),
      child: InkWell(
        borderRadius: BorderRadius.circular(18 * s),
        onTap: onTap,
        focusColor: Colors.white24,
        child: Padding(
          padding: EdgeInsets.all(14 * s),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  KeyBadge(pc: pc, size: 40 * s),
                  SizedBox(width: 12 * s),
                  Expanded(
                    child: Text(group,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 22 * s, fontWeight: FontWeight.w900)),
                  ),
                  Icon(Icons.library_music_rounded, size: 28 * s, color: Colors.white54),
                ],
              ),
              Text(
                '${songs.length} ${songs.length == 1 ? 'song' : 'songs'}: '
                '${songs.map((s) => s.title).join(', ')}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14 * s, color: Colors.white60),
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
    final s = uiScale(context);
    return Material(
      color: AppColors.quietCard,
      borderRadius: BorderRadius.circular(18 * s),
      child: InkWell(
        borderRadius: BorderRadius.circular(18 * s),
        onTap: onTap,
        focusColor: Colors.white24,
        child: Padding(
          padding: EdgeInsets.all(14 * s),
          child: Row(
            children: [
              KeyBadge(pc: _nextPagePc, size: 40 * s),
              SizedBox(width: 12 * s),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text('More (page ${page + 1} of $pages)',
                      style: TextStyle(fontSize: 18 * s, fontWeight: FontWeight.w800, color: Colors.white70)),
                ),
              ),
              Icon(Icons.arrow_forward_rounded, size: 32 * s, color: Colors.white70),
            ],
          ),
        ),
      ),
    );
  }
}
