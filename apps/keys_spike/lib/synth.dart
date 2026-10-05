// Tiny polyphonic synth on SoLoud: one looping triangle-wave source per note,
// started silent and faded in/out to avoid clicks.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

const _noteNames = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];

// Same per-pitch-class colors as the web game (C red .. B pink).
const _pitchColors = [
  Color(0xFFFF3B3B), Color(0xFFFF6A2B), Color(0xFFFF9A1F), Color(0xFFFFC61F),
  Color(0xFFFFE81F), Color(0xFF3DDC4A), Color(0xFF22C9A0), Color(0xFF2FA8FF),
  Color(0xFF4A6BFF), Color(0xFF8A4DFF), Color(0xFFC04DFF), Color(0xFFFF5EC8),
];

String noteName(int note) => '${_noteNames[note % 12]}${note ~/ 12 - 1}';
Color noteColor(int note) => _pitchColors[note % 12];

double noteHz(int note) => 440.0 * math.pow(2, (note - 69) / 12).toDouble();

class Synth {
  static const _attack = Duration(milliseconds: 4);
  static const _release = Duration(milliseconds: 250);

  final SoLoud _soloud = SoLoud.instance;
  final Map<int, AudioSource> _sources = {};
  final Map<int, SoundHandle> _playing = {};

  bool get ready => _soloud.isInitialized;

  Future<void> start({required int bufferSize}) async {
    if (_soloud.isInitialized) return;
    await _soloud.init(bufferSize: bufferSize, lowLatency: true);
    // Preload the range a 37-key keyboard covers across its octave shifts.
    for (var note = 24; note <= 108; note++) {
      final source = await _soloud.loadWaveform(WaveForm.triangle, false, 1, 0);
      _soloud.setWaveformFreq(source, noteHz(note));
      _sources[note] = source;
    }
  }

  Future<void> stop() async {
    _playing.clear();
    _sources.clear();
    if (_soloud.isInitialized) {
      await _soloud.disposeAllSources();
      _soloud.deinit();
    }
  }

  void noteOn(int note, int velocity) {
    final source = _sources[note];
    if (source == null || !ready) return;
    noteOff(note);
    final level = 0.15 + 0.35 * (velocity / 127);
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
}
