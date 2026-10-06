// Song picker: one big card per bundled song, with its first notes as
// colored dots so even non-readers can tell songs apart.

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../audio/synth.dart';
import '../games/color_keys_rules.dart';
import '../midi/midi_input.dart';
import '../widgets/keyboard_status.dart';
import 'song.dart';
import 'song_play_page.dart';

class SongListPage extends StatefulWidget {
  const SongListPage({super.key, required this.synth, required this.midi});

  final Synth synth;
  final MidiInput midi;

  @override
  State<SongListPage> createState() => _SongListPageState();
}

class _SongListPageState extends State<SongListPage> {
  late final Future<List<Song>> _songs = loadSongs(rootBundle);

  void _open(Song song) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => SongPlayPage(song: song, synth: widget.synth, midi: widget.midi),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF14111C),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
              child: Row(
                children: [
                  const BackButton(),
                  const Expanded(
                    child: Text('Songs', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
                  ),
                  Flexible(child: KeyboardStatus(midi: widget.midi)),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<List<Song>>(
                future: _songs,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(child: Text('Could not load songs: ${snapshot.error}'));
                  }
                  final songs = snapshot.data;
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
                  return GridView.extent(
                    maxCrossAxisExtent: 360,
                    childAspectRatio: 2.2,
                    padding: const EdgeInsets.all(12),
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    children: [for (final song in songs) _SongCard(song: song, onTap: () => _open(song))],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SongCard extends StatelessWidget {
  const _SongCard({required this.song, required this.onTap});

  final Song song;
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
              Text(song.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              Row(
                children: [
                  for (final n in song.notes.take(min(8, song.notes.length)))
                    Padding(
                      padding: const EdgeInsets.only(right: 5),
                      child: CircleAvatar(
                        radius: 9,
                        backgroundColor: Color(pitchClasses[pitchClass(n.note)].argb),
                      ),
                    ),
                  const Spacer(),
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
