import 'package:flutter_test/flutter_test.dart';
import 'package:mightys_pulse/src/core/options.dart';
import 'package:mightys_pulse/src/core/runtime.dart';
import 'package:mightys_pulse/src/platform/compression.dart';
import 'support.dart';

void main() {
  test(
    'debug false suppresses privacy errors even during initial construction',
    () async {
      final time = FakeTime(), storage = FakeStorage()..failReads = true;
      final messages = <String>[];
      final runtime = PulseRuntime(
        clock: time,
        scheduler: time,
        random: FakeRandom(),
        storage: storage,
        transport: FakeTransport(),
        compression: const IoCompression(),
        environment: FakeEnvironment(),
        log: messages.add,
      );
      await runtime.initialize(
        'key',
        options: const PulseOptions(debug: false),
      );
      await runtime.idle;
      expect(runtime.optOut, true);
      expect(messages, isEmpty);
    },
  );
}
