// Song Box: plays a song's melody (exactly the notes the song games use) at
// its real speed while the keys light up, to hear how a song sounds before
// playing it. C plays it again from the start, D stops.

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../audio/synth.dart';
import '../midi/midi_input.dart';
import '../widgets/key_nav.dart';
import '../widgets/keyboard_status.dart';
import '../widgets/piano_strip.dart';
import 'song.dart';

const _againPc = 0;
const _stopPc = 2;

class SongListenPage extends StatefulWidget {
  const SongListenPage({super.key, required this.song, required this.synth, required this.midi});

  final Song song;
  final Synth synth;
  final MidiInput midi;

  @override
  State<SongListenPage> createState() => _SongListenPageState();
}

class _SongListenPageState extends State<SongListenPage> {
  final List<Timer> _timers = [];
  final Set<int> _sounding = {};
  final Stopwatch _clock = Stopwatch();
  Timer? _tick;

  late final int _lowest = widget.song.notes.map((n) => n.note).reduce(min);
  late final int _highest = widget.song.notes.map((n) => n.note).reduce(max);
  late final int _endMs = widget.song.notes.map((n) => n.startMs + n.lengthMs).reduce(max);

  bool get _playing => _clock.isRunning;

  @override
  void initState() {
    super.initState();
    _play();
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  void _play() {
    _stop();
    for (final n in widget.song.notes) {
      final length = max(80, n.lengthMs - 20);
      _timers.add(
        Timer(Duration(milliseconds: n.startMs), () {
          widget.synth.noteOn(n.note, 85);
          if (mounted) setState(() => _sounding.add(n.note));
        }),
      );
      _timers.add(
        Timer(Duration(milliseconds: n.startMs + length), () {
          widget.synth.noteOff(n.note);
          if (mounted) setState(() => _sounding.remove(n.note));
        }),
      );
    }
    _timers.add(
      Timer(Duration(milliseconds: _endMs + 300), () {
        if (mounted) setState(_clock.stop);
      }),
    );
    _clock
      ..reset()
      ..start();
    _tick = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (mounted) setState(() {});
    });
    if (mounted) setState(() {});
  }

  void _stop() {
    for (final timer in _timers) {
      timer.cancel();
    }
    _timers.clear();
    _tick?.cancel();
    for (final note in _sounding) {
      widget.synth.noteOff(note);
    }
    _sounding.clear();
    _clock.stop();
  }

  String _time(int ms) {
    final s = ms ~/ 1000;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final at = min(_clock.elapsedMilliseconds, _endMs);
    return Scaffold(
      backgroundColor: const Color(0xFF14111C),
      body: KeyNav(
        midi: widget.midi,
        picks: {_againPc: _play, _stopPc: () => setState(_stop)},
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
                child: Row(
                  children: [
                    const BackButton(),
                    Expanded(
                      child: Text(
                        widget.song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
                      ),
                    ),
                    Flexible(child: KeyboardStatus(midi: widget.midi)),
                  ],
                ),
              ),
              Expanded(
                // Scales down to fit a landscape phone.
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: SizedBox(
                    width: 480,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _playing ? Icons.graphic_eq_rounded : Icons.music_note_rounded,
                          size: 56,
                          color: Colors.white70,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '${widget.song.group}, ${widget.song.notes.length} notes',
                          style: const TextStyle(color: Colors.white60, fontSize: 16),
                        ),
                        const SizedBox(height: 16),
                        LinearProgressIndicator(value: _endMs == 0 ? 0 : at / _endMs, minHeight: 8),
                        const SizedBox(height: 8),
                        Text(
                          '${_time(at)} / ${_time(_endMs)}',
                          style: const TextStyle(color: Colors.white60),
                        ),
                        const SizedBox(height: 20),
                        Wrap(
                          spacing: 24,
                          runSpacing: 12,
                          alignment: WrapAlignment.center,
                          children: [
                            _KeyHint(pc: _againPc, text: 'Play again', onTap: _play),
                            _KeyHint(pc: _stopPc, text: 'Stop', onTap: () => setState(_stop)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SizedBox(
                height: 150,
                child: PianoStrip(
                  base: 48,
                  span: whiteSpan(_lowest, _highest),
                  held: _sounding,
                  onNoteOn: (note) => widget.synth.noteOn(note, 100),
                  onNoteOff: widget.synth.noteOff,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _KeyHint extends StatelessWidget {
  const _KeyHint({required this.pc, required this.text, required this.onTap});

  final int pc;
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            KeyBadge(pc: pc, size: 36),
            const SizedBox(width: 8),
            Text(text, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }
}
