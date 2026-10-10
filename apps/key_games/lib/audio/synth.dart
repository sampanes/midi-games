// Small polyphonic synth on SoLoud: one looping triangle-wave source per note,
// started silent and faded in/out to avoid clicks. Low-latency settings came
// from the keys_spike test (buffer 256 felt close to instant on a phone).

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_soloud/flutter_soloud.dart';

double noteHz(int note) => 440.0 * math.pow(2, (note - 69) / 12).toDouble();

class Synth {
  static const lowestNote = 12;
  static const highestNote = 108;
  static const _attack = Duration(milliseconds: 4);
  static const releaseLength = Duration(milliseconds: 300);

  final SoLoud _soloud = SoLoud.instance;
  final Map<int, AudioSource> _sources = {};
  final Map<int, SoundHandle> _playing = {};
  final Map<int, Set<SoundHandle>> _releasing = {};
  final Map<int, int> _generation = {};

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
    _generation[note] = (_generation[note] ?? 0) + 1;
  }

  void noteOff(int note) {
    final handle = _playing.remove(note);
    if (handle == null || !ready) return;
    final releasing = _releasing.putIfAbsent(note, () => {});
    releasing.add(handle);
    _soloud.fadeVolume(handle, 0, releaseLength);
    _soloud.scheduleStop(handle, releaseLength);
    Timer(releaseLength, () {
      releasing.remove(handle);
      if (releasing.isEmpty && identical(_releasing[note], releasing)) {
        _releasing.remove(note);
      }
    });
  }

  // Immediately silence a held key before a solo correction tone. Normal key
  // releases use the gentle fade above; this is only for replacing a rejected
  // multi-key attempt without leaving its notes audible underneath.
  void noteOffNow(int note) {
    final handles = <SoundHandle>[];
    final playing = _playing.remove(note);
    if (playing != null) handles.add(playing);
    final releasing = _releasing.remove(note);
    if (releasing != null) handles.addAll(releasing);
    if (!ready) return;
    for (final handle in handles) {
      _soloud.setVolume(handle, 0);
      unawaited(_soloud.stop(handle));
    }
  }

  // A note with a fixed length, for on-screen taps and little tunes.
  void blip(int note, {int velocity = 90, int lengthMs = 160}) {
    noteOn(note, velocity);
    final generation = _generation[note];
    if (generation == null) return;
    Timer(Duration(milliseconds: lengthMs), () {
      // A newer press or correction may now own this pitch. An old blip timer
      // must never release that newer voice.
      if (_generation[note] == generation) noteOff(note);
    });
  }

  // Notes one after another, e.g. a rising arpeggio for a win.
  void tune(List<int> notes, {int stepMs = 110, int lengthMs = 220}) {
    for (var i = 0; i < notes.length; i++) {
      Timer(
        Duration(milliseconds: i * stepMs),
        () => blip(notes[i], lengthMs: lengthMs),
      );
    }
  }
}
