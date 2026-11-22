import 'package:flutter_test/flutter_test.dart';
import 'package:key_games/app/timer_group.dart';

void main() {
  testWidgets('scheduled actions run once and may schedule more work', (
    tester,
  ) async {
    final timers = TimerGroup();
    final calls = <int>[];
    timers.schedule(const Duration(milliseconds: 10), () {
      calls.add(1);
      timers.schedule(const Duration(milliseconds: 10), () => calls.add(2));
    });

    await tester.pump(const Duration(milliseconds: 10));
    expect(calls, [1]);
    await tester.pump(const Duration(milliseconds: 10));
    expect(calls, [1, 2]);
    timers.cancelAll();
  });

  testWidgets('cancelAll cancels pending work and the group can be reused', (
    tester,
  ) async {
    final timers = TimerGroup();
    final calls = <int>[];
    timers.schedule(const Duration(milliseconds: 10), () => calls.add(1));
    timers.schedule(const Duration(milliseconds: 20), () => calls.add(2));
    await tester.pump(const Duration(milliseconds: 10));
    timers.cancelAll();
    timers.schedule(const Duration(milliseconds: 10), () => calls.add(3));
    await tester.pump(const Duration(milliseconds: 20));
    expect(calls, [1, 3]);
  });
}
