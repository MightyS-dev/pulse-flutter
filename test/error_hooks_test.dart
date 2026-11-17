import 'dart:async';
import 'dart:ui' show ErrorCallback;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mightys_pulse/mightys_pulse.dart';
import 'package:mightys_pulse/src/client.dart';
import 'package:mightys_pulse/src/core/backend.dart';
import 'package:mightys_pulse/src/core/config.dart';
import 'package:mightys_pulse/src/error_hooks.dart';
import 'support.dart';

class FakeSlots implements ErrorSlots {
  @override
  FlutterExceptionHandler? flutterHandler;
  @override
  ErrorCallback? platformHandler;
}

typedef Call = ({Object error, StackTrace? stack, String kind});

class RecordingBackend implements PulseBackend {
  final calls = <Call>[];
  bool throwing = false;
  @override
  void trackError(
    Object error,
    StackTrace? stack,
    Map<String, Object?>? props, {
    required String kind,
  }) {
    if (throwing) throw StateError('broken');
    calls.add((error: error, stack: stack, kind: kind));
  }

  @override
  bool get optOut => false;
  @override
  PulseConfig get config => PulseConfig.defaults;
  @override
  Future<void> initialize(
    String key, {
    PulseOptions options = const PulseOptions(),
  }) async {}
  @override
  void track(String type, {num? value, Map<String, Object?>? props}) {}
  @override
  void deepLink(Uri uri) {}
  @override
  void setUser(String? identifier) {}
  @override
  Future<void> flush() async {}
  @override
  Future<void> setOptOut(bool value) async {}
}

void main() {
  late FakeSlots slots;
  late RecordingBackend backend;
  late List<FlutterErrorDetails> previousFlutterCalls;
  late List<(Object, StackTrace)> previousPlatformCalls;
  late bool previousReturns;

  setUp(() {
    slots = FakeSlots();
    backend = RecordingBackend();
    previousFlutterCalls = [];
    previousPlatformCalls = [];
    previousReturns = true;
    slots.flutterHandler = previousFlutterCalls.add;
    slots.platformHandler = (e, s) {
      previousPlatformCalls.add((e, s));
      return previousReturns;
    };
  });

  PulseClient client() =>
      PulseClient(() => backend, errorSlots: slots, hooksSupported: true);

  test('captureErrors false installs nothing', () async {
    final before = (slots.flutterHandler, slots.platformHandler);
    await client().initialize(
      'key',
      options: const PulseOptions(debug: false, captureErrors: false),
    );
    expect(slots.flutterHandler, same(before.$1));
    expect(slots.platformHandler, same(before.$2));
  });

  test(
    'FlutterError.onError: sent as kind error and chained with the same details',
    () async {
      await client().initialize(
        'key',
        options: const PulseOptions(debug: false),
      );
      final details = FlutterErrorDetails(
        exception: StateError('boom'),
        stack: StackTrace.fromString('#0 f (package:a/a.dart:1:1)'),
      );
      slots.flutterHandler!(details);
      expect(backend.calls, hasLength(1));
      expect(backend.calls.single.kind, 'error');
      expect(backend.calls.single.error, same(details.exception));
      expect(backend.calls.single.stack, same(details.stack));
      expect(previousFlutterCalls.single, same(details));
    },
  );

  test(
    'PlatformDispatcher.onError: chained, previous result passed through',
    () async {
      await client().initialize(
        'key',
        options: const PulseOptions(debug: false),
      );
      final stack = StackTrace.fromString('#0 f (package:a/a.dart:1:1)');
      final error = ArgumentError('x');
      previousReturns = true;
      expect(slots.platformHandler!(error, stack), true);
      previousReturns = false;
      expect(slots.platformHandler!(error, stack), false);
      expect(previousPlatformCalls, hasLength(2));
      expect(previousPlatformCalls.first.$1, same(error));
      expect(previousPlatformCalls.first.$2, same(stack));
      expect(backend.calls, hasLength(2));
      expect(backend.calls.first.kind, 'error');
    },
  );

  test('without a previous platform handler it returns false', () async {
    slots.platformHandler = null;
    await client().initialize('key', options: const PulseOptions(debug: false));
    expect(slots.platformHandler!('x', StackTrace.empty), false);
  });

  test('without a previous Flutter handler it does not fail', () async {
    slots.flutterHandler = null;
    await client().initialize('key', options: const PulseOptions(debug: false));
    slots.flutterHandler!(FlutterErrorDetails(exception: 'x'));
    expect(backend.calls, hasLength(1));
  });

  test(
    'a broken SDK never throws from a handler and the previous one still runs',
    () async {
      await client().initialize(
        'key',
        options: const PulseOptions(debug: false),
      );
      backend.throwing = true;
      final details = FlutterErrorDetails(exception: 'x');
      expect(() => slots.flutterHandler!(details), returnsNormally);
      expect(slots.platformHandler!('y', StackTrace.empty), true);
      expect(previousFlutterCalls, [details]);
      expect(previousPlatformCalls, hasLength(1));
    },
  );

  test(
    'an error raised inside our own handler is ignored (recursion guard)',
    () {
      late ErrorHooks hooks;
      var depth = 0;
      hooks = ErrorHooks((error, stack) {
        depth++;
        slots.platformHandler!('again', StackTrace.empty);
      }, slots)..install();
      slots.platformHandler!('first', StackTrace.empty);
      expect(depth, 1);
      expect(hooks, isNotNull);
    },
  );

  test('a second initialize installs the hooks only once', () async {
    final c = client();
    await c.initialize('key', options: const PulseOptions(debug: false));
    final installed = slots.flutterHandler;
    await c.initialize('key', options: const PulseOptions(debug: false));
    expect(slots.flutterHandler, same(installed));
    slots.flutterHandler!(FlutterErrorDetails(exception: 'x'));
    expect(backend.calls, hasLength(1));
    expect(previousFlutterCalls, hasLength(1));
  });

  test(
    'trackError works with captureErrors false and uses the current stack',
    () async {
      final c = client();
      await c.initialize(
        'key',
        options: const PulseOptions(debug: false, captureErrors: false),
      );
      c.trackError(StateError('x'), null, null);
      c.trackError(StateError('y'), StackTrace.empty, null);
      expect(backend.calls.map((c) => c.kind), ['handled', 'handled']);
      expect(backend.calls.first.stack.toString(), isNotEmpty);
    },
  );

  test('trackError never throws when the SDK is broken', () {
    backend.throwing = true;
    expect(() => client().trackError('x', null, null), returnsNormally);
  });

  test('end to end: an unhandled error becomes a pulse.error signal', () async {
    final h = Harness(initialize: false);
    final c = PulseClient(
      () => h.runtime,
      errorSlots: slots,
      hooksSupported: true,
    );
    unawaited(
      c.initialize('synthetic-key', options: const PulseOptions(debug: false)),
    );
    slots.flutterHandler!(
      FlutterErrorDetails(
        exception: StateError('boom'),
        stack: StackTrace.fromString('#0 f (package:a/a.dart:7:1)'),
      ),
    );
    await h.flush();
    final e = h.allEvents.singleWhere((e) => e['type'] == 'pulse.error');
    expect((e['error']! as Map)['kind'], 'error');
    expect((e['error']! as Map)['frames'], ['f a.dart:7']);
    expect(previousFlutterCalls, hasLength(1));
  });

  test('the real slots are replaced and restored without trouble', () {
    const real = SystemErrorSlots();
    final f = real.flutterHandler, p = real.platformHandler;
    real.flutterHandler = (_) {};
    real.platformHandler = (_, _) => false;
    expect(real.flutterHandler, isNotNull);
    real.flutterHandler = f;
    real.platformHandler = p;
    expect(real.flutterHandler, same(f));
    expect(Pulse.trackError, isNotNull);
  });
}
