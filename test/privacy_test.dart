import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:mightys_pulse/src/core/options.dart';
import 'package:mightys_pulse/src/core/ports.dart';
import 'package:mightys_pulse/src/core/queue.dart';
import 'support.dart';

void main() {
  test(
    'preinitialize buffer cap preserves capture time, session and hashed user',
    () async {
      final h = Harness(initialize: false);
      h.runtime.setUser('private.raw');
      for (var i = 0; i < 105; i++) {
        h.runtime.track('early', value: i);
      }
      await h.runtime.initialize('synthetic-key');
      await h.flush();
      expect(h.events.map((e) => e['value']), List.generate(100, (i) => i + 5));
      expect(h.events.first['userHash'], isNotNull);
      expect(h.events.first['timestamp'], '2026-11-13T00:00:00.000Z');
      for (final bytes in h.storage.files.values) {
        expect(
          utf8.decode(bytes, allowMalformed: true),
          isNot(contains('private.raw')),
        );
      }
    },
  );
  test('opt-out persists, clears, cancels active and resets user', () async {
    final h = Harness();
    final reply = Completer<PulseResponse>();
    h.transport.handler = (_) => reply.future;
    h.runtime.setUser('private.raw');
    await h.send();
    expect(plain(h.transport.requests.single), isNot(contains('private.raw')));
    await h.runtime.setOptOut(true);
    h.runtime.track('ignored');
    await h.settle();
    expect(h.runtime.optOut, true);
    expect(h.runtime.count, 0);
    expect(h.storage.files['opt-out'], [1]);
    expect(h.transport.cancellations, greaterThan(0));
    reply.complete(const PulseResponse(202));
    await h.settle();
    final next = Harness(storage: h.storage);
    await next.send();
    expect(next.transport.requests, isEmpty);
    await next.runtime.setOptOut(false);
    await next.send('anonymous');
    expect(next.events.single['userHash'], isNotNull);
  });
  test(
    'corrupt or unreadable preference and failed writes fail closed',
    () async {
      for (final bytes in [
        <int>[],
        [2],
        [0, 0],
        utf8.encode('bad'),
      ]) {
        final store = FakeStorage()..files['opt-out'] = bytes;
        final h = Harness(storage: store);
        await h.send();
        expect(h.runtime.optOut, true);
        expect(h.transport.requests, isEmpty);
      }
      final store = FakeStorage()..failReads = true;
      final unreadable = Harness(storage: store);
      await unreadable.send();
      expect(unreadable.runtime.optOut, true);
      final h = Harness();
      await h.settle();
      h.storage.failWrites = true;
      await h.runtime.setOptOut(true);
      await h.runtime.setOptOut(false);
      h.runtime.track('blocked');
      await h.settle();
      expect(h.runtime.optOut, true);
      expect(h.transport.requests, isEmpty);
      h.storage.failWrites = false;
      await h.advance(1);
      expect(h.runtime.optOut, false);
      await h.send('allowed');
      expect(h.events.single['type'], 'allowed');
    },
  );
  test('privacy generations invalidate unopened app-key queues', () async {
    final first = Harness();
    first.runtime.track('old');
    await first.settle();
    final other = Harness(storage: first.storage, initialize: false);
    await other.runtime.initialize('other-key');
    other.runtime.track('old.other');
    await other.settle();
    final settings = Harness(storage: first.storage, initialize: false);
    await settings.runtime.setOptOut(true);
    await settings.runtime.setOptOut(false);
    final restored = Harness(storage: first.storage);
    await restored.flush();
    expect(restored.transport.requests, isEmpty);
    final second = Harness(storage: first.storage, initialize: false);
    await second.runtime.initialize('other-key');
    await second.flush();
    expect(second.transport.requests, isEmpty);
  });
  test(
    'track racing opt-out and opt-in write never reopens older generation',
    () async {
      final h = Harness();
      await h.settle();
      for (var i = 0; i < 100; i++) {
        h.runtime.track('race');
        if (i % 5 == 0) {
          unawaited(h.runtime.setOptOut(true));
        }
      }
      await h.settle();
      expect(h.runtime.optOut, true);
      expect(h.runtime.count, 0);
      expect(h.transport.requests, isEmpty);
      final blocked = Completer<void>();
      final entered = Completer<void>();
      h.storage.afterReplace = (name) async {
        if (name == 'opt-out' && !entered.isCompleted) {
          entered.complete();
          await blocked.future;
        }
      };
      final optIn = h.runtime.setOptOut(false);
      await entered.future;
      final optOut = h.runtime.setOptOut(true);
      blocked.complete();
      await optIn;
      await optOut;
      await h.settle();
      expect(h.runtime.optOut, true);
    },
  );
  test(
    'capture during save persists before send and storage failures suspend network',
    () async {
      final h = Harness();
      await h.settle();
      var inserted = false;
      h.storage.afterReplace = (name) async {
        if (name.startsWith('queue-') && !inserted) {
          inserted = true;
          h.runtime.track('during.write');
        }
      };
      h.transport.handler = (request) async {
        final snapshot = QueueSnapshot.decode(
          h.storage.files[h.storage.queueName]!,
          compression: const TestCompression(),
        );
        expect(snapshot.pending.first.wire, request.body);
        return const PulseResponse(202);
      };
      await h.send('before');
      expect(h.events.map((e) => e['type']).toSet(), {
        'before',
        'during.write',
      });
      final failed = Harness();
      await failed.settle();
      failed.storage.failWrites = true;
      await failed.send('later');
      expect(failed.transport.requests, isEmpty);
      failed.storage.failWrites = false;
      await failed.advance(1);
      expect(failed.events.single['type'], 'later');
    },
  );
  test(
    '10000 interleaved captures across microtasks and timers have no loss or duplication',
    () async {
      final h = Harness(
        options: const PulseOptions(
          maxQueueSize: 10000,
          maxBatchSize: 1000,
          gzip: false,
        ),
      );
      await h.settle();
      await Future.wait(
        List.generate(10, (producer) async {
          for (var i = 0; i < 1000; i++) {
            h.runtime.track('parallel', value: producer * 1000 + i);
            if (i % 100 == 0) {
              await Future<void>.delayed(Duration.zero);
            } else {
              await Future<void>.value();
            }
          }
        }),
      );
      await h.flush();
      final values = h.events.map((e) => e['value']! as int).toList();
      expect(values.length, 10000);
      expect(values.toSet().length, 10000);
      expect(values..sort(), List.generate(10000, (i) => i));
    },
  );
}

class TestCompression implements PulseCompression {
  const TestCompression();
  @override
  List<int> encode(List<int> bytes) => bytes;
  @override
  List<int> decode(List<int> bytes) => bytes;
}
