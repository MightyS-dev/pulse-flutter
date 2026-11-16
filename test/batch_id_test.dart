import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mightys_pulse/src/core/options.dart';
import 'package:mightys_pulse/src/core/ports.dart';
import 'package:mightys_pulse/src/core/queue.dart';
import 'package:mightys_pulse/src/platform/http_transport.dart';
import 'support.dart';

final _format = RegExp(r'^[0-9a-f]{32}$');

void main() {
  test('every batch carries a 32 character lowercase hex id', () async {
    final h = Harness();
    await h.send('one');
    final id = h.transport.requests.single.batchId;
    expect(id, isNotNull);
    expect(_format.hasMatch(id!), isTrue);
  });

  test('two consecutive different batches have different ids', () async {
    final h = Harness();
    await h.send('one');
    await h.advance(20);
    await h.send('two');
    await h.advance(20);
    expect(h.transport.requests.length, 2);
    expect(
      h.transport.requests[0].batchId,
      isNot(h.transport.requests[1].batchId),
    );
  });

  test('retry after network error, 5xx and 429 keeps id and content', () async {
    for (final status in [0, 500, 503, 429]) {
      final h = Harness();
      h.transport.replies.add(PulseResponse(status));
      await h.send('retry', {'large': 'x' * 1000});
      await h.advance(300);
      expect(h.transport.requests.length, 2, reason: 'status $status');
      final a = h.transport.requests[0], b = h.transport.requests[1];
      expect(b.batchId, a.batchId);
      expect(plain(b), plain(a));
    }
  });

  test('new signal before the retry does not change the batch', () async {
    final h = Harness();
    h.transport.replies.add(const PulseResponse(500, retryAfter: '60'));
    await h.send('original');
    h.runtime.track('later');
    await h.advance(60);
    final first = h.transport.requests.first;
    final retry = h.transport.requests[1];
    expect(retry.batchId, first.batchId);
    expect(plain(retry), plain(first));
    await h.advance(20);
    final last = h.transport.requests.last;
    expect(eventsOf(last).single['type'], 'later');
    expect(last.batchId, isNot(first.batchId));
  });

  test('id and content survive a process restart', () async {
    final h = Harness();
    h.transport.replies.add(const PulseResponse(500, retryAfter: '60'));
    await h.send('original', {'large': 'x' * 1000});
    final first = h.transport.requests.single;
    final next = Harness(storage: h.storage, time: FakeTime(h.time.now));
    await next.flush();
    await next.advance(60);
    final retry = next.transport.requests.first;
    expect(retry.batchId, first.batchId);
    expect(plain(retry), plain(first));
  });

  test('a 413 split gives new ids, different from the original', () async {
    final h = Harness(
      options: const PulseOptions(maxBatchSize: 8, gzip: false),
    );
    await h.settle();
    h.runtime.track('a');
    h.runtime.track('b');
    h.runtime.track('c');
    h.runtime.track('d');
    h.transport.replies.add(const PulseResponse(413));
    unawaited(h.runtime.flush());
    await h.settle();
    final ids = h.transport.requests.map((r) => r.batchId).toList();
    expect(ids.length, greaterThanOrEqualTo(3));
    expect(ids.toSet().length, ids.length);
  });

  test('plain fallback after 413 on a gzip batch keeps the id', () async {
    final h = Harness();
    h.transport.replies.add(const PulseResponse(413));
    await h.send('big', {'large': 'q' * 1000});
    final a = h.transport.requests[0], b = h.transport.requests[1];
    expect(b.batchId, a.batchId);
    expect(eventsOf(b), eventsOf(a));
  });

  test('snapshot without an id still loads and gets one', () {
    final now = DateTime.utc(2026, 11, 16);
    final entry = Entry(
      'a',
      now,
      '{"timestamp":"${now.toIso8601String()}","type":"event"}',
    );
    final batch = Batch(
      [entry.id],
      batchJson([entry]),
      utf8.encode(batchJson([entry])),
      false,
    );
    expect(batch.toJson().containsKey('batchId'), isTrue);
    final json = batch.toJson()..remove('batchId');
    expect(Batch.fromJson(json).id, '');
  });

  test('real transport sends X-Pulse-Batch on batch posts only', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final seen = <String, String?>{};
    server.listen((request) async {
      seen[request.method] = request.headers.value('X-Pulse-Batch');
      request.response.statusCode = request.method == 'GET' ? 404 : 202;
      await request.response.close();
    });
    final url = Uri.parse('http://127.0.0.1:${server.port}/x');
    final transport = IoTransport();
    await transport.send(
      PulseRequest(url, 'k', utf8.encode('[]'), false, batchId: 'a' * 32),
    );
    await transport.get(url, 'k');
    expect(seen['POST'], 'a' * 32);
    expect(seen['GET'], isNull);
  });

  test('a queue saved by 0.9.4 loads and every batch gets a new id', () async {
    final now = DateTime.utc(2026, 11, 13);
    Entry make(String id, String type) => Entry(
      id,
      now,
      '{"timestamp":"${now.toIso8601String()}","type":"$type"}',
    );
    final entries = [make('a', 'pending'), make('b', 'loose1'), make('c', 'x')];
    final json = batchJson([entries.first]);
    final probe = Harness();
    await probe.send('seed');
    // A launch that never changed privacy has an empty generation.
    const generation = '';
    // Exact 0.9.4 snapshot layout: no batchId key in a pending batch.
    final payload = utf8.encode(
      jsonEncode({
        'version': 1,
        'generation': generation,
        'entries': entries.map((e) => e.toJson()).toList(),
        'pending': [
          {
            'ids': ['a'],
            'json': json,
            'wire': base64Encode(utf8.encode(json)),
            'gzip': false,
            'failures': 0,
            'retryAt': DateTime.utc(1970).toIso8601String(),
          },
        ],
        'interval': 20.0,
        'pauseUntil': DateTime.utc(1970).toIso8601String(),
      }),
    );
    final bytes = <int>[
      ...utf8.encode('MPF1'),
      ...sha256.convert(payload).bytes,
      ...payload,
    ];
    final first = Harness(initialize: false);
    final name = probe.storage.queueName;
    first.storage.files[name] = bytes;
    for (final key in probe.storage.files.keys) {
      if (key != name) {
        first.storage.files[key] = probe.storage.files[key]!;
      }
    }
    final h = Harness(storage: first.storage, time: FakeTime(probe.time.now));
    await h.flush();
    await h.advance(30);
    await h.flush();
    final types = h.allEvents.map((e) => e['type']).toList();
    expect(types, containsAll(['pending', 'loose1', 'x']));
    final ids = h.transport.requests.map((r) => r.batchId).toList();
    expect(ids.every((i) => i != null && _format.hasMatch(i)), isTrue);
    expect(ids.toSet().length, ids.length);
  });
}
