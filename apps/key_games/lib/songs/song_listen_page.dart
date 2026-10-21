// Song Box: plays a song's melody (exactly the notes the song games use) at
// its real speed while the keys light up, to hear how a song sounds before
// playing it. C plays it again from the start, D stops.

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../app/services.dart';
import '../app/theme.dart';
import '../audio/synth.dart';
import '../widgets/game_page.dart';
import '../widgets/key_badge.dart';
import '../widgets/piano_strip.dart';
import 'song.dart';

const _againPc = 0;
const _stopPc = 2;

class SongListenPage extends StatefulWidget {
  const SongListenPage({super.key, required this.song});

  final Song song;

  @override
  State<SongListenPage> createState() => _SongListenPageState();
}

class _SongListenPageState extends State<SongListenPage> {
  late final Synth _synth = AppServices.of(context).synth;
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
          _synth.noteOn(n.note, 85);
          if (mounted) setState(() => _sounding.add(n.note));
        }),
      );
      _timers.add(
        Timer(Duration(milliseconds: n.startMs + length), () {
          _synth.noteOff(n.note);
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
      _synth.noteOff(note);
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
    final s = uiScale(context);
    return GamePage(
      title: widget.song.title,
      headerPadding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
      picks: {_againPc: _play, _stopPc: () => setState(_stop)},
      // Phone-sized, grown with the screen, and scaled down to fit a
      // landscape phone.
      body: ScaledChrome(
        scale: s,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: SizedBox(
            width: 480 * s,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _playing ? Icons.graphic_eq_rounded : Icons.music_note_rounded,
                  size: 56 * s,
                  color: Colors.white70,
                ),
                SizedBox(height: 12 * s),
                Text(
                  '${widget.song.group}, ${widget.song.notes.length} notes',
                  style: const TextStyle(color: Colors.white60, fontSize: 16),
                ),
                SizedBox(height: 16 * s),
                LinearProgressIndicator(value: _endMs == 0 ? 0 : at / _endMs, minHeight: 8 * s),
                SizedBox(height: 8 * s),
                Text(
                  '${_time(at)} / ${_time(_endMs)}',
                  style: const TextStyle(color: Colors.white60),
                ),
                SizedBox(height: 20 * s),
                Wrap(
                  spacing: 24 * s,
                  runSpacing: 12 * s,
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
      footer: [
        SizedBox(
          height: pianoStripHeight(context, design: 150),
          child: PianoStrip(
            base: 48,
            span: whiteSpan(_lowest, _highest),
            held: _sounding,
            onNoteOn: (note) => _synth.noteOn(note, 100),
            onNoteOff: _synth.noteOff,
          ),
        ),
      ],
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
    final s = uiScale(context);
    return InkWell(
      borderRadius: BorderRadius.circular(12 * s),
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.all(6 * s),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            KeyBadge(pc: pc, size: 36 * s),
            SizedBox(width: 8 * s),
            Text(text, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }
}
