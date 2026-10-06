// Home menu: one big tile per game.

import 'package:flutter/material.dart';

import 'audio/synth.dart';
import 'games/color_keys_page.dart';
import 'midi/midi_input.dart';
import 'songs/song_list_page.dart';
import 'widgets/keyboard_status.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.synth, required this.midi});

  final Synth synth;
  final MidiInput midi;

  void _go(BuildContext context, Widget page) {
    Navigator.push(context, MaterialPageRoute<void>(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    final tiles = [
      _GameTile(
        title: 'Color Keys',
        subtitle: 'Find the glowing note',
        icon: Icons.palette,
        colors: const [Color(0xFFFF3B3B), Color(0xFFFFE81F), Color(0xFF2FA8FF)],
        onTap: () => _go(context, ColorKeysPage(synth: synth, midi: midi)),
      ),
      _GameTile(
        title: 'Songs',
        subtitle: 'Play real tunes, one note at a time',
        icon: Icons.music_note,
        colors: const [Color(0xFF8A4DFF), Color(0xFFFF5EC8), Color(0xFFFF9A1F)],
        onTap: () => _go(context, SongListPage(synth: synth, midi: midi)),
      ),
    ];
    return Scaffold(
      backgroundColor: const Color(0xFF14111C),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text('Key Games', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900)),
                  ),
                  Flexible(child: KeyboardStatus(midi: midi)),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth > constraints.maxHeight;
                    return Flex(
                      direction: wide ? Axis.horizontal : Axis.vertical,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final tile in tiles)
                          Expanded(
                            child: Padding(padding: const EdgeInsets.all(8), child: tile),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GameTile extends StatelessWidget {
  const _GameTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.colors,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      borderRadius: BorderRadius.circular(28),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [for (final c in colors) c.withValues(alpha: 0.85)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Icon(icon, size: 96, color: Colors.white),
                    const SizedBox(height: 8),
                    Text(title, style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w900)),
                    Text(subtitle, style: const TextStyle(fontSize: 18, color: Colors.white70)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
