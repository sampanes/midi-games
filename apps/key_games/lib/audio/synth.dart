// Small polyphonic synth on SoLoud: one looping triangle-wave source per note,
// started silent and faded in/out to avoid clicks. Low-latency settings came
// from the keys_spike test (buffer 256 felt close to instant on a phone).

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_soloud/flutter_soloud.dart';

double noteHz(int note) => 440.0 * math.pow(2, (note - 69) / 12).toDouble();

class Synth {
  static const lowestNote = 24;
  static const highestNote = 108;
  static const _attack = Duration(milliseconds: 4);
  static const _release = Duration(milliseconds: 300);

  final SoLoud _soloud = SoLoud.instance;
  final Map<int, AudioSource> _sources = {};
  final Map<int, SoundHandle> _playing = {};

  bool get ready => _soloud.isInitialized && _sources.isNotEmpty;

  Future<void> start({int bufferSize = 256}) async {
    if (_soloud.isInitialized) return;
    await _soloud.init(bufferSize: bufferSize, lowLatency: true);
    for (var note = lowestNote; note <= highestNote; note++) {
      final source = await _soloud.loadWaveform(WaveForm.triangle, false, 1, 0);
      _soloud.setWaveformFreq(source, noteHz(note));
      _sources[note] = source;
    }
  }

  void noteOn(int note, int velocity) {
    final source = _sources[note];
    if (source == null || !ready) return;
    noteOff(note);
    final level = 0.2 + 0.35 * (velocity.clamp(1, 127) / 127);
    final handle = _soloud.play(source, volume: 0, looping: true);
    _soloud.fadeVolume(handle, level, _attack);
    _playing[note] = handle;
  }

  void noteOff(int note) {
    final handle = _playing.remove(note);
    if (handle == null || !ready) return;
    _soloud.fadeVolume(handle, 0, _release);
    _soloud.scheduleStop(handle, _release);
  }

  // A note with a fixed length, for on-screen taps and little tunes.
  void blip(int note, {int velocity = 90, int lengthMs = 160}) {
    noteOn(note, velocity);
    Timer(Duration(milliseconds: lengthMs), () => noteOff(note));
  }

  // Notes one after another, e.g. a rising arpeggio for a win.
  void tune(List<int> notes, {int stepMs = 110, int lengthMs = 220}) {
    for (var i = 0; i < notes.length; i++) {
      Timer(Duration(milliseconds: i * stepMs), () => blip(notes[i], lengthMs: lengthMs));
    }
  }
}
