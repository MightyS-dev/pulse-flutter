import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mightys_pulse/src/client.dart';
import 'package:mightys_pulse/src/core/backend.dart';
import 'package:mightys_pulse/src/core/options.dart';
import 'package:mightys_pulse/src/core/ports.dart';
import 'support.dart';

class BrokenBackend implements PulseBackend {
  @override
  bool get optOut => throw StateError('getter');
  @override
  Future<void> initialize(
    String key, {
    PulseOptions options = const PulseOptions(),
  }) async => throw StateError('initialize');
  @override
  void track(String type, {num? value, Map<String, Object?>? props}) =>
      throw StateError('track');
  @override
  void setUser(String? identifier) => throw StateError('setUser');
  @override
  Future<void> flush() async => throw StateError('flush');
  @override
  Future<void> setOptOut(bool value) async => throw StateError('preference');
}

void main() {
  test('sync and returned Future failures cannot escape facade zone', () async {
    final escaped = <Object>[];
    final done = Completer<void>();
    runZonedGuarded(
      () async {
        final client = PulseClient(BrokenBackend.new);
        await client.initialize('', options: const PulseOptions(debug: false));
        client.track(
          'x' * 100000,
          value: double.infinity,
          props: {
            'null': null,
            'nested': {'bad': double.nan},
          },
        );
        client.setUser('x' * 100000);
        expect(client.optOut, true);
        await client.flush();
        await client.setOptOut(false);
        done.complete();
      },
      (error, stack) {
        escaped.add(error);
      },
    );
    await done.future.timeout(const Duration(seconds: 5));
    expect(escaped, isEmpty);
  });
  test(
    'transport async throw is treated as network failure with exact retry bytes',
    () async {
      final h = Harness();
      var failed = false;
      h.transport.handler = (r) async {
        if (!failed) {
          failed = true;
          throw StateError('network');
        }
        return const PulseResponse(202);
      };
      await h.send();
      expect(h.transport.requests.length, 1);
      await h.advance(1);
      expect(h.transport.requests.length, 2);
      expect(h.transport.requests[0].body, h.transport.requests[1].body);
    },
  );
}
