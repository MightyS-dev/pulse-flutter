import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mightys_pulse/mightys_pulse.dart';
import 'package:mightys_pulse/src/client.dart';
import 'package:mightys_pulse/src/platform/backend_stub.dart';
import 'support.dart';

void main() {
  test(
    'facade forwards preinit calls and never leaks sync or async errors',
    () async {
      final h = Harness(initialize: false);
      final client = PulseClient(() => h.runtime);
      final escaped = <Object>[];
      final finished = Completer<void>();
      runZonedGuarded(
        () async {
          client.setUser('raw');
          client.track('early');
          await client.initialize('synthetic-key');
          for (final type in ['', 'x' * 10000, 'fine']) {
            client.track(
              type,
              value: double.nan,
              props: {
                'bad': {'nested': null},
                'null': null,
                'nan': double.infinity,
              },
            );
          }
          await client.flush();
          await client.setOptOut(true);
          expect(client.optOut, true);
          final broken = PulseClient(() => throw StateError('factory'));
          broken.track('x');
          broken.setUser('x');
          await broken.initialize('');
          await broken.flush();
          await broken.setOptOut(false);
          expect(broken.optOut, true);
          await Pulse.initialize('');
          Pulse.track('');
          Pulse.setUser(null);
          await Pulse.flush();
          await Pulse.setOptOut(true);
          finished.complete();
        },
        (error, stack) {
          escaped.add(error);
        },
      );
      await finished.future.timeout(const Duration(seconds: 10));
      expect(escaped, isEmpty);
    },
  );
  test('web stub no-ops and warns once only when debug enabled', () async {
    final warnings = <String>[];
    final stub = WebBackend(log: warnings.add);
    await stub.initialize('key', options: const PulseOptions(debug: false));
    stub.track('ignored');
    await stub.flush();
    expect(warnings, isEmpty);
    await stub.initialize('key', options: const PulseOptions(debug: true));
    await stub.initialize('key', options: const PulseOptions(debug: true));
    stub.track('ignored', value: double.nan);
    stub.setUser('raw');
    await stub.setOptOut(true);
    await stub.flush();
    expect(stub.optOut, true);
    expect(warnings.length, 1);
  });
}
