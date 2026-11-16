import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mightys_pulse/src/core/options.dart';

import 'support.dart';

int millis(Map<String, Object?> event) =>
    DateTime.parse(event['timestamp']! as String).millisecondsSinceEpoch;

List<String> types(Harness h) =>
    h.allEvents.map((e) => e['type']! as String).toList();

void main() {
  test('three signals in the same millisecond get +0, +1, +2 ms', () async {
    final h = Harness();
    h.runtime.track('a');
    h.runtime.track('b');
    h.runtime.track('c');
    await h.flush();
    final stamps = h.allEvents.map(millis).toList();
    expect(types(h), ['a', 'b', 'c']);
    expect(stamps, [stamps[0], stamps[0] + 1, stamps[0] + 2]);
  });

  test('automatic signals come before the trigger in order and time', () async {
    final h = Harness(automatic: true);
    h.runtime.track('first');
    h.runtime.track('second');
    await h.flush();
    final stamps = h.allEvents.map(millis).toList();
    expect(types(h), [
      'pulse.new_install',
      'pulse.session_started',
      'first',
      'second',
    ]);
    for (var i = 1; i < stamps.length; i++) {
      expect(stamps[i], stamps[i - 1] + 1);
    }
  });

  test('signals tracked before initialize keep their capture order', () async {
    final h = Harness(initialize: false);
    h.runtime.track('a');
    h.runtime.track('b');
    unawaited(
      h.runtime.initialize(
        'synthetic-key',
        options: const PulseOptions(debug: false),
      ),
    );
    await h.settle();
    h.runtime.track('c');
    await h.flush();
    final stamps = h.allEvents.map(millis).toList();
    expect(types(h), ['a', 'b', 'c']);
    expect(stamps, [stamps[0], stamps[0] + 1, stamps[0] + 2]);
  });

  test(
    'a clock that goes backwards still yields increasing timestamps',
    () async {
      final h = Harness();
      h.runtime.track('a');
      await h.settle();
      h.time.date = h.time.date.subtract(const Duration(seconds: 5));
      h.runtime.track('b');
      await h.settle();
      h.runtime.track('c');
      await h.flush();
      final stamps = h.allEvents.map(millis).toList();
      expect(types(h), ['a', 'b', 'c']);
      expect(stamps, [stamps[0], stamps[0] + 1, stamps[0] + 2]);
    },
  );

  test('a later clock reading is kept', () async {
    final h = Harness();
    h.runtime.track('a');
    await h.settle();
    h.time.date = h.time.date.add(const Duration(seconds: 2));
    h.runtime.track('b');
    await h.flush();
    final stamps = h.allEvents.map(millis).toList();
    expect(stamps[1] - stamps[0], 2000);
  });
}
