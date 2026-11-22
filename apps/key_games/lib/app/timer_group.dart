import 'dart:async';

/// Owns one-shot timers so a screen can cancel its pending work together.
/// Completed timers are discarded, including during long-running games.
class TimerGroup {
  final Set<Timer> _pending = {};

  void schedule(Duration delay, void Function() action) {
    late final Timer timer;
    timer = Timer(delay, () {
      _pending.remove(timer);
      action();
    });
    _pending.add(timer);
  }

  void cancelAll() {
    for (final timer in _pending) {
      timer.cancel();
    }
    _pending.clear();
  }
}
