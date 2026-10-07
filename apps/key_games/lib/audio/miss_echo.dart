// After a wrong key: play the child's note again, then the right one, so the
// two can be compared by ear. A new miss restarts it; a hit cancels it.

import 'dart:async';

import 'synth.dart';

class MissEcho {
  MissEcho(this.synth);

  static const _wrongAt = Duration(milliseconds: 450);
  static const _rightAt = Duration(milliseconds: 1000);

  final Synth synth;
  final List<Timer> _timers = [];

  // Time from a miss until the right note has finished.
  static const length = Duration(milliseconds: 1600);

  void play(int wrong, int right) {
    cancel();
    _timers
      ..add(Timer(_wrongAt, () => synth.blip(wrong, velocity: 60, lengthMs: 380)))
      ..add(Timer(_rightAt, () => synth.blip(right, velocity: 100, lengthMs: 600)));
  }

  void cancel() {
    for (final timer in _timers) {
      timer.cancel();
    }
    _timers.clear();
  }
}
