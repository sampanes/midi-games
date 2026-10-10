// Feedback after a wrong key. Guided games can repeat the wrong and right
// notes; Color Keys can play only the right note. New feedback replaces old.

import 'dart:async';

import 'synth.dart';

class MissEcho {
  MissEcho(this.synth);

  static const _wrongAt = Duration(milliseconds: 450);
  static const _rightAt = Duration(milliseconds: 1000);

  final Synth synth;
  final List<Timer> _timers = [];
  int? _rightOnlyNote;

  // Time from a miss until the right note has finished.
  static const length = Duration(milliseconds: 1600);

  // A shorter correction used when the player's original note should not be
  // echoed. Unlike Synth.blip, this owns its stop timer so canceling before a
  // new physical press cannot stop that newer press later.
  static const rightOnlyLength = Duration(milliseconds: 600);

  void play(int wrong, int right) {
    cancel();
    _timers
      ..add(
        Timer(_wrongAt, () => synth.blip(wrong, velocity: 60, lengthMs: 380)),
      )
      ..add(
        Timer(_rightAt, () => synth.blip(right, velocity: 100, lengthMs: 600)),
      );
  }

  void playRightOnly(int right) {
    cancel();
    _rightOnlyNote = right;
    synth.noteOn(right, 100);
    _timers.add(
      Timer(rightOnlyLength, () {
        if (_rightOnlyNote != right) return;
        synth.noteOff(right);
        // Keep ownership through Synth's release tail. A new attempt can then
        // cut that tail instead of hearing it underneath the next key.
        _timers.add(
          Timer(Synth.releaseLength, () {
            if (_rightOnlyNote == right) _rightOnlyNote = null;
          }),
        );
      }),
    );
  }

  void cancel() {
    for (final timer in _timers) {
      timer.cancel();
    }
    _timers.clear();
    final rightOnlyNote = _rightOnlyNote;
    _rightOnlyNote = null;
    if (rightOnlyNote != null) synth.noteOffNow(rightOnlyNote);
  }
}
