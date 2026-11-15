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

  group('test mode flag', () {
    Future<Object?> sentDebug(PulseOptions options) async {
      final h = Harness(options: options);
      await h.settle();
      await h.send('mode.check');
      return h.events.single['debug'];
    }

    test('an explicit value wins in both directions', () async {
      expect(await sentDebug(const PulseOptions(debug: true)), true);
      expect(await sentDebug(const PulseOptions(debug: false)), false);
    });

    test('the default follows the build mode and is the same on every run', () {
      const expected =
          !bool.fromEnvironment('dart.vm.product') &&
          !bool.fromEnvironment('dart.vm.profile');
      expect(const PulseOptions().debug, expected);
      expect(const PulseOptions().debug, const PulseOptions().debug);
      // Flutter tests run in a debug-style VM, so the default is test mode.
      expect(const PulseOptions().debug, true);
    });

    test(
      'the default is carried to the wire when no option is given',
      () async {
        expect(
          await sentDebug(const PulseOptions()),
          const PulseOptions().debug,
        );
      },
    );
  });
}
