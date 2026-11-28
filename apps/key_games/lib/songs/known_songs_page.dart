import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/services.dart';
import '../audio/synth.dart';
import '../games/color_keys_rules.dart';
import '../midi/midi_input.dart';
import '../widgets/game_page.dart';
import '../widgets/piano_strip.dart';
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

// A no-score, self-paced reminder of the melody in an existing song file.
class SongGuidePage extends StatefulWidget {
  const SongGuidePage({super.key, required this.song});
  final Song song;

  @override
  State<SongGuidePage> createState() => _SongGuidePageState();
}

class _SongGuidePageState extends State<SongGuidePage> {
  late final Synth _synth;
  final Set<int> _held = {};
  int _index = 0;
  int _base = 48;

  @override
  void initState() {
    super.initState();
    _synth = AppServices.of(context).synth;
  }

  int get _target => widget.song.notes[_index].note;
  String _name(int note) {
    const names = [
      'C',
      'C#/Db',
      'D',
      'D#/Eb',
      'E',
      'F',
      'F#/Gb',
      'G',
      'G#/Ab',
      'A',
      'A#/Bb',
      'B',
    ];
    return '${names[pitchClass(note)]} ${note ~/ 12 - 1}';
  }

  void _move(int offset) => setState(
    () => _index = (_index + offset).clamp(0, widget.song.notes.length - 1),
  );

  void _note(NoteEvent event) {
    if (!event.on) {
      _synth.noteOff(event.note);
      setState(() => _held.remove(event.note));
      return;
    }
    _synth.noteOn(event.note, event.velocity);
    setState(() {
      _held.add(event.note);
      _base = fitBase(_base, event.note);
      if (event.note == _target && _index < widget.song.notes.length - 1) {
        _index++;
      }
    });
  }

  @override
  void dispose() {
    for (final note in _held) {
      _synth.noteOff(note);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notes = widget.song.notes;
    final low = max(12, (_target ~/ 12) * 12 - 12);
    final high = min(108, low + 24);
    return GamePage(
      title: widget.song.title,
      onNote: _note,
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Note  ${_index + 1} / ${notes.length}',
                style: const TextStyle(fontSize: 18),
              ),
              const SizedBox(height: 8),
              Text(
                _name(_target),
                style: const TextStyle(
                  fontSize: 46,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Text(
                'Play the glowing key, or use the buttons to move at your pace.',
                textAlign: TextAlign.center,
              ),
              const Text(
                'Simplified MIDI line: chords and octaves may differ.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: _index == 0 ? null : () => _move(-1),
                    child: const Text('Previous'),
                  ),
                  FilledButton(
                    onPressed: () => _synth.blip(_target, lengthMs: 500),
                    child: const Text('Hear note'),
                  ),
                  OutlinedButton(
                    onPressed: _index == notes.length - 1
                        ? null
                        : () => _move(1),
                    child: const Text('Next'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Next: ${notes.skip(_index + 1).take(4).map((n) => _name(n.note)).join('  -  ')}',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
      footer: [
        SizedBox(
          height: min(180, MediaQuery.sizeOf(context).height * .25),
          child: PianoStrip(
            base: _base,
            span: (low: low, high: high),
            targetNote: _target,
            plain: true,
            held: _held,
            onNoteOn: (note) => _note(NoteEvent(note, 90, on: true)),
            onNoteOff: (note) => _note(NoteEvent(note, 0, on: false)),
          ),
        ),
      ],
    );
  }
}
