import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mightys_pulse/src/platform/lifecycle.dart';
import 'package:mightys_pulse/src/platform/system_services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'lifecycle saves paused hidden detached and swallows failures',
    () async {
      var saved = 0;
      final lifecycle = PulseLifecycle(() async {
        saved++;
        throw StateError('disk');
      });
      addTearDown(lifecycle.dispose);
      for (final state in AppLifecycleState.values) {
        lifecycle.didChangeAppLifecycleState(state);
      }
      await Future<void>.value();
      expect(saved, 3);
    },
  );
  test('secure sessions are 128-bit random and timers cancellable', () async {
    final random = SecureRandom();
    final tokens = List.generate(1000, (_) => random.token());
    expect(tokens.toSet().length, 1000);
    expect(tokens.every((t) => RegExp(r'^[a-f0-9]{32}$').hasMatch(t)), true);
    expect(random.sample(), inInclusiveRange(0, 1));
    expect(SystemClock().now.isUtc, true);
    final done = Completer<void>();
    SystemScheduler().schedule(Duration.zero, done.complete);
    await done.future;
    var called = false;
    SystemScheduler().schedule(const Duration(milliseconds: 1), () {
      called = true;
    }).cancel();
    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(called, false);
  });
}
