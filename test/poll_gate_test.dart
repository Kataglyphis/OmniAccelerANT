// The polls' back-off: the short interval while answers come, then a doubling wait up to a minute.
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_accelerant/Pages/StreamPage/poll_gate.dart';

void main() {
  test('three misses keep the interval, then the wait doubles to a minute', () {
    const base = Duration(seconds: 5);
    expect(
      [
        for (var misses = 0; misses <= 8; misses++)
          backoffDelay(base, misses).inSeconds,
      ],
      [5, 5, 5, 5, 10, 20, 40, 60, 60],
    );
    expect(backoffDelay(base, 1000), const Duration(minutes: 1));
  });
}
