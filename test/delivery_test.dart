import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mightys_pulse/src/core/options.dart';
import 'package:mightys_pulse/src/core/ports.dart';
import 'support.dart';

void main() {
  test(
    'first batch after initialize leaves at once, later ones wait',
    () async {
      final h = Harness();
      await h.settle();
      h.runtime.track('first');
      await h.settle();
      expect(h.transport.requests.length, 1);
      expect(h.events.single['type'], 'first');
      h.runtime.track('second');
      await h.settle();
      expect(h.transport.requests.length, 1);
      await h.advance(19.999);
      expect(h.transport.requests.length, 1);
      await h.advance(0.001);
      expect(h.transport.requests.length, 2);
    },
  );
  test('time, count and background flush', () async {
    final h = Harness(options: const PulseOptions(maxBatchSize: 2));
    await h.settle();
    h.runtime.track('one');
    await h.settle();
    expect(h.transport.requests.length, 1);
    h.runtime.track('warm');
    await h.settle();
    expect(h.transport.requests.length, 1);
    await h.advance(19.999);
    expect(h.transport.requests.length, 1);
    await h.advance(0.001);
    expect(h.transport.requests.length, 2);
    expect(h.events.length, 2);
    h.runtime.track('two');
    h.runtime.track('three');
    await h.settle();
    expect(h.transport.requests.length, 3);
    h.runtime.track('pause');
    await h.runtime.backgroundSave();
    await h.settle();
    expect(h.events.last['type'], 'pause');
  });
  test('all retry statuses preserve wire bytes', () async {
    for (final status in [0, 302, 403, 408, 425, 429, 500, 502, 503, 599]) {
      final h = Harness();
      h.transport.replies.add(PulseResponse(status));
      await h.send('retry', {'large': 'x' * 1000});
      final first = h.transport.requests.single;
      await h.advance(0.999);
      expect(h.transport.requests.length, 1);
      await h.advance(0.001);
      expect(h.transport.requests.length, 2);
      expect(h.transport.requests.last.body, first.body);
      expect(h.runtime.count, 0);
    }
  });
  test(
    'pending retry bytes survive restart while new events stay separate',
    () async {
      final h = Harness();
      h.transport.replies.add(const PulseResponse(500, retryAfter: '60'));
      await h.send('original', {'large': 'x' * 1000});
      h.runtime.track('new');
      await h.settle();
      final first = h.transport.requests.single;
      final next = Harness(storage: h.storage, time: FakeTime(h.time.now));
      await next.flush();
      expect(next.transport.requests, isEmpty);
      await next.advance(60);
      expect(next.transport.requests.first.body, first.body);
      expect(eventsOf(next.transport.requests.last).single['type'], 'new');
    },
  );
  test('Retry-After seconds, HTTP date and one hour cap', () async {
    for (final after in ['60', 'Fri, 13 Nov 2026 00:01:00 GMT', '999999999']) {
      final h = Harness();
      h.transport.replies.add(PulseResponse(429, retryAfter: after));
      await h.send();
      final delay = after == '999999999' ? 3600.0 : 60.0;
      await h.advance(delay - 0.001);
      expect(h.transport.requests.length, 1);
      await h.advance(0.001);
      expect(h.transport.requests.length, 2);
    }
  });
  test('recursive plain 400 and 413 isolate invalid singletons', () async {
    for (final status in [400, 413]) {
      final h = Harness(
        options: const PulseOptions(maxBatchSize: 8, gzip: false),
      );
      final delivered = <int>[];
      h.transport.handler = (r) async {
        final values = eventsOf(r).map((e) => e['value']! as int).toList();
        final bad = values.contains(2) || values.contains(5);
        if (!bad) {
          delivered.addAll(values);
        }
        return PulseResponse(bad ? status : 202);
      };
      for (var i = 0; i < 8; i++) {
        h.runtime.track('event', value: i);
      }
      await h.flush();
      expect(delivered..sort(), [0, 1, 3, 4, 6, 7]);
      expect(h.transport.requests.length, lessThanOrEqualTo(15));
      expect(h.runtime.count, 0);
    }
  });
  test('401 halts until process restart and keeps queue', () async {
    final h = Harness();
    h.transport.replies.add(const PulseResponse(401));
    await h.send();
    h.runtime.track('new');
    await h.advance(3600);
    await h.flush();
    expect(h.transport.requests.length, 1);
    final next = Harness(storage: h.storage, time: FakeTime(h.time.now));
    await next.flush();
    expect(next.events.length, 2);
    expect(
      next.transport.requests.first.body,
      h.transport.requests.single.body,
    );
  });
  test('415 disables gzip for process, 413 only for batch', () async {
    for (final status in [415, 413]) {
      final h = Harness();
      h.transport.replies.add(PulseResponse(status));
      await h.send('one', {'large': 'q' * 1000});
      expect(h.transport.requests.first.gzip, true);
      expect(h.transport.requests[1].gzip, false);
      expect(plain(h.transport.requests.first), plain(h.transport.requests[1]));
      await h.send('two', {'large': 'q' * 1000});
      expect(h.transport.requests.last.gzip, status == 413);
    }
  });
  test(
    'pause respects forced flush/count/background and busy advice longest deadline',
    () async {
      final h = Harness(options: const PulseOptions(maxBatchSize: 2));
      h.transport.replies.add(
        const PulseResponse(
          202,
          body: '{"recommendedSendIntervalSeconds":120,"pause":true}',
        ),
      );
      await h.send('one');
      h.runtime.track('two');
      h.runtime.track('three');
      await h.flush();
      await h.runtime.backgroundSave();
      await h.advance(119.999);
      expect(h.transport.requests.length, 1);
      await h.advance(0.001);
      expect(h.transport.requests.length, 2);
      final busy = Harness();
      busy.transport.replies.add(
        const PulseResponse(
          503,
          retryAfter: '60',
          body: '{"recommendedSendIntervalSeconds":30,"pause":false}',
        ),
      );
      await busy.send();
      await busy.advance(59.999);
      expect(busy.transport.requests.length, 1);
      await busy.advance(0.001);
      expect(busy.transport.requests.length, 2);
    },
  );
  test('background save never waits for network', () async {
    final h = Harness();
    final reply = Completer<PulseResponse>();
    h.transport.handler = (_) => reply.future;
    await h.send();
    h.runtime.track('last');
    await h.runtime.backgroundSave().timeout(const Duration(seconds: 2));
    expect(h.runtime.count, 2);
    reply.complete(const PulseResponse(202));
    await h.settle();
  });
}
