import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mightys_pulse/src/core/options.dart';
import 'package:mightys_pulse/src/core/ports.dart';
import 'package:mightys_pulse/src/core/runtime.dart';
import 'package:mightys_pulse/src/platform/computation.dart';
import 'package:mightys_pulse/src/platform/compression.dart';
import 'package:mightys_pulse/src/platform/file_storage.dart';
import 'support.dart';

void main() {
  test(
    'runtime restarts from real file storage with isolated codec and exact pending bytes',
    () async {
      final directory = await Directory.systemTemp.createTemp('pulse-runtime-');
      addTearDown(() => directory.delete(recursive: true));
      final time = FakeTime(),
          firstTransport = FakeTransport()
            ..replies.add(const PulseResponse(500, retryAfter: '60'));
      PulseRuntime runtime(FakeTransport transport) => PulseRuntime(
        clock: time,
        scheduler: time,
        random: FakeRandom(),
        storage: FileStorage(directory),
        transport: transport,
        compression: const IoCompression(),
        computation: const IsolateComputation(),
        environment: FakeEnvironment(),
        log: (_) {},
      );
      final first = runtime(firstTransport);
      await first.initialize('real-file');
      first.track('saved', props: {'large': 'x' * 1000});
      unawaited(first.flush());
      for (var i = 0; i < 20; i++) {
        await first.idle;
        await Future<void>.delayed(Duration.zero);
      }
      expect(firstTransport.requests.length, 1);
      final bytes = firstTransport.requests.single.body;
      await first.close();
      time.advance(60);
      final nextTransport = FakeTransport();
      final next = runtime(nextTransport);
      await next.initialize('real-file');
      await next.flush();
      expect(nextTransport.requests.single.body, bytes);
      await next.close();
    },
  );
  test(
    'damaged persisted queue is discarded and fresh capture proceeds',
    () async {
      final h = Harness();
      h.runtime.track('old');
      await h.settle();
      h.storage.files[h.storage.queueName] = [1, 2, 3];
      final next = Harness(storage: h.storage);
      await next.send('fresh');
      expect(next.events.single['type'], 'fresh');
    },
  );
  test('count, age and future bounds hold after restore', () async {
    final h = Harness(
      options: const PulseOptions(maxQueueSize: 3, maxBatchSize: 100),
    );
    await h.settle();
    for (var i = 0; i < 5; i++) {
      h.runtime.track('bounded', value: i);
    }
    await h.flush();
    expect(h.events.map((e) => e['value']), [2, 3, 4]);
    for (final offset in [const Duration(days: 8), const Duration(hours: -2)]) {
      final old = Harness();
      old.runtime.track('stale');
      await old.settle();
      final next = Harness(
        storage: old.storage,
        time: FakeTime(old.time.now.add(offset)),
      );
      await next.flush();
      expect(next.transport.requests, isEmpty);
    }
  });
  test('max body byte cap and max batch count on large props', () async {
    final h = Harness(
      options: const PulseOptions(
        maxQueueSize: 2000,
        maxBatchSize: 1000,
        gzip: false,
      ),
    );
    for (var i = 0; i < 300; i++) {
      h.runtime.track(
        'large',
        value: i,
        props: {for (var j = 0; j < 7; j++) 'p$j': 'x' * 1024},
      );
    }
    await h.flush();
    expect(h.events.length, 300);
    expect(h.transport.requests.length, greaterThan(1));
    expect(
      h.transport.requests.every(
        (r) => r.body.length <= 1048576 && eventsOf(r).length <= 1000,
      ),
      true,
    );
  });
  test('exponential jitter and 5-minute cap', () async {
    for (final jitter in [0.0, 1.0, double.nan]) {
      final h = Harness();
      h.random.value = jitter;
      h.transport.replies.addAll(List.filled(12, const PulseResponse(500)));
      await h.send();
      for (var failure = 0; failure < 12; failure++) {
        final exponential = failure < 9 ? (1 << failure).toDouble() : 300.0;
        final delay =
            ((exponential > 300 ? 300 : exponential) *
                    (0.5 + (jitter.isNaN ? 0.5 : jitter)))
                .clamp(1.0, 300.0);
        final count = h.transport.requests.length;
        await h.advance(delay - 0.001);
        expect(h.transport.requests.length, count);
        await h.advance(0.001);
        expect(h.transport.requests.length, count + 1);
      }
    }
  });
  test(
    'caller props snapshot, app identity option and version override',
    () async {
      final h = Harness(
        options: const PulseOptions(
          sendAppIdentity: true,
          appVersion: 'override',
        ),
      );
      final props = <String, Object?>{'original': 1};
      h.runtime.track('copy', props: props);
      props['original'] = 2;
      await h.flush();
      expect(h.events.single['props'], {'original': 1});
      final system = h.events.single['system']! as Map<String, Object?>;
      expect(system['bundleId'], 'test.local');
      expect(system['appVersion'], 'override');
      final anonymous = Harness();
      await anonymous.send();
      expect(
        (anonymous.events.single['system']! as Map<String, Object?>)
            .containsKey('bundleId'),
        false,
      );
    },
  );
  test('flush waits through unreadable queue and follows recovery', () async {
    final h = Harness(initialize: false);
    await h.runtime.idle;
    h.storage.failReads = true;
    await h.runtime.initialize('synthetic-key');
    h.runtime.track('waiting');
    var completed = false;
    unawaited(
      h.runtime.flush().then((_) {
        completed = true;
      }),
    );
    await h.settle();
    expect(completed, false);
    h.storage.failReads = false;
    await h.advance(1);
    expect(completed, true);
    expect(h.events.single['type'], 'waiting');
  });
  test(
    'raw user never on disk or in request and null clears later events',
    () async {
      final h = Harness();
      h.runtime.setUser('secret.raw.identifier');
      h.runtime.track('first');
      await h.settle();
      for (final bytes in h.storage.files.values) {
        expect(
          utf8.decode(bytes, allowMalformed: true),
          isNot(contains('secret.raw.identifier')),
        );
      }
      await h.flush();
      expect(
        plain(h.transport.requests.first),
        isNot(contains('secret.raw.identifier')),
      );
      h.runtime.setUser(null);
      await h.send('second');
      expect(h.events.last['userHash'], isNotNull);
      expect(h.events.last['userHash'], isNot(h.events.first['userHash']));
    },
  );
}
