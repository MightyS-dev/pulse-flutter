import 'package:flutter_test/flutter_test.dart';
import 'package:mightys_pulse/src/core/heatmap_shots.dart';
import 'package:mightys_pulse/src/core/ports.dart';
import 'support.dart';

class _Rig {
  _Rig({this.debug = true}) {
    shots = _make();
  }
  final time = FakeTime();
  final storage = FakeStorage();
  final transport = FakeTransport();
  bool debug;
  late HeatmapShots shots;
  final warnings = <String>[];

  HeatmapShots _make() => HeatmapShots(
    storage: storage,
    transport: transport,
    clock: time,
    appKey: 'synthetic-key',
    endpoint: Uri.parse('https://in.example.invalid/api/v1/signals'),
    appVersion: '1.2.3',
    debugBuild: () => debug,
    warn: warnings.add,
  );

  /// A new object on the same storage, as after an app restart.
  HeatmapShots restart() => shots = _make();

  Future<HeatmapShotTicket> ticket([String screen = 'Shop']) async =>
      (await shots.ticket(screen, 400, 800))!;
}

final _png = List<int>.filled(100, 7);

void main() {
  test('a ticket needs a debug build, a screen and a size', () async {
    final r = _Rig(debug: false);
    expect(await r.shots.ticket('Shop', 400, 800), isNull);
    r.debug = true;
    expect(await r.shots.ticket('', 400, 800), isNull);
    expect(await r.shots.ticket('Shop', 0, 800), isNull);
    expect(await r.shots.ticket('Shop', 400, 0), isNull);
    final t = await r.shots.ticket('Shop', 400, 800);
    expect(t!.screen, 'Shop');
    expect(t.bucket, 'phone');
    expect(t.orientation, 'portrait');
  });

  test('201 uploads the bytes with the key and marks it done', () async {
    final r = _Rig();
    r.transport.uploadReplies.add(
      const PulseResponse(201, body: '{"stored":true}'),
    );
    final ok = await r.shots.upload(await r.ticket(), _png, 'image/png');
    expect(ok, isTrue);
    final u = r.transport.uploads.single;
    expect(u.appKey, 'synthetic-key');
    expect(u.contentType, 'image/png');
    expect(u.bytes, _png);
    expect(u.url.path, '/api/v1/heatmap/screenshot');
    expect(u.url.host, 'in.example.invalid');
    expect(u.url.queryParameters, {
      'screen': 'Shop',
      'bucket': 'phone',
      'orientation': 'portrait',
      'appVersion': '1.2.3',
      'debug': 'true',
    });
    expect(await r.shots.ticket('Shop', 400, 800), isNull);
    expect(await r.shots.ticket('Shop', 800, 400), isNotNull);
    expect(await r.shots.ticket('Cart', 400, 800), isNotNull);
  });

  test(
    'the marker survives a restart and a new app version asks again',
    () async {
      final r = _Rig();
      r.transport.uploadReplies.add(const PulseResponse(201));
      await r.shots.upload(await r.ticket(), _png, 'image/png');
      r.restart();
      expect(await r.shots.ticket('Shop', 400, 800), isNull);
      final other = HeatmapShots(
        storage: r.storage,
        transport: r.transport,
        clock: r.time,
        appKey: 'k',
        endpoint: Uri.parse('https://in.example.invalid/api/v1/signals'),
        appVersion: '1.2.4',
        debugBuild: () => true,
        warn: (_) {},
      );
      expect(await other.ticket('Shop', 400, 800), isNotNull);
    },
  );

  test('the screen name is escaped in the query', () async {
    final r = _Rig();
    r.transport.uploadReplies.add(const PulseResponse(201));
    await r.shots.upload(await r.ticket('A & B/c d'), _png, 'image/png');
    expect(
      r.transport.uploads.single.url.queryParameters['screen'],
      'A & B/c d',
    );
    expect(
      r.transport.uploads.single.url.toString(),
      contains('A%20%26%20B%2Fc%20d'),
    );
  });

  for (final status in [403, 415, 413, 422]) {
    test('$status marks it done and is not retried', () async {
      final r = _Rig();
      r.transport.uploadReplies.add(PulseResponse(status));
      expect(
        await r.shots.upload(await r.ticket(), _png, 'image/png'),
        isFalse,
      );
      expect(await r.shots.ticket('Shop', 400, 800), isNull);
    });
  }

  for (final status in [429, 503, 507, 0, 500]) {
    test('$status is retried later, not marked', () async {
      final r = _Rig();
      r.transport.uploadReplies.add(PulseResponse(status, retryAfter: '30'));
      expect(
        await r.shots.upload(await r.ticket(), _png, 'image/png'),
        isFalse,
      );
      if (status == 500) {
        expect(await r.shots.ticket('Shop', 400, 800), isNotNull);
        return;
      }
      expect(await r.shots.ticket('Shop', 400, 800), isNull);
      r.time.advance(31);
      expect(await r.shots.ticket('Shop', 400, 800), isNotNull);
    });
  }

  test('Retry-After is honoured up to one hour, default is a minute', () async {
    final r = _Rig();
    r.transport.uploadReplies.add(
      const PulseResponse(429, retryAfter: '99999'),
    );
    await r.shots.upload(await r.ticket(), _png, 'image/png');
    r.time.advance(3599);
    expect(await r.shots.ticket('Shop', 400, 800), isNull);
    r.time.advance(2);
    expect(await r.shots.ticket('Shop', 400, 800), isNotNull);
    r.transport.uploadReplies.add(const PulseResponse(503));
    await r.shots.upload(await r.ticket(), _png, 'image/png');
    r.time.advance(59);
    expect(await r.shots.ticket('Shop', 400, 800), isNull);
    r.time.advance(2);
    expect(await r.shots.ticket('Shop', 400, 800), isNotNull);
  });

  test('never more than 20 attempts per hour', () async {
    final r = _Rig();
    for (var i = 0; i < 20; i++) {
      r.transport.uploadReplies.add(const PulseResponse(500));
      await r.shots.upload(await r.ticket('S$i'), _png, 'image/png');
    }
    expect(r.transport.uploads.length, 20);
    expect(await r.shots.ticket('S99', 400, 800), isNull);
    r.time.advance(3601);
    expect(await r.shots.ticket('S99', 400, 800), isNotNull);
  });

  test('bad pictures and non debug builds are never uploaded', () async {
    final r = _Rig();
    final t = await r.ticket();
    expect(await r.shots.upload(t, const [], 'image/png'), isFalse);
    expect(
      await r.shots.upload(
        t,
        List<int>.filled(2 * 1024 * 1024 + 1, 1),
        'image/png',
      ),
      isFalse,
    );
    expect(await r.shots.upload(t, _png, 'image/svg+xml'), isFalse);
    expect(await r.shots.upload(t, _png, 'text/plain'), isFalse);
    r.debug = false;
    expect(await r.shots.upload(t, _png, 'image/png'), isFalse);
    expect(r.transport.uploads, isEmpty);
  });

  test('a second upload of a view in flight is refused', () async {
    final r = _Rig();
    final t = await r.ticket();
    r.transport.uploadHandler = () async {
      return const PulseResponse(201);
    };
    final first = r.shots.upload(t, _png, 'image/png');
    final second = await r.shots.upload(t, _png, 'image/png');
    expect(second, isFalse);
    expect(await first, isTrue);
    expect(r.transport.uploads.length, 1);
  });

  test('forget deletes the markers and the file', () async {
    final r = _Rig();
    r.transport.uploadReplies.add(const PulseResponse(201));
    await r.shots.upload(await r.ticket(), _png, 'image/png');
    expect(r.storage.files.containsKey(HeatmapShots.fileName), isTrue);
    await r.shots.forget();
    expect(r.storage.files.containsKey(HeatmapShots.fileName), isFalse);
    expect(await r.shots.ticket('Shop', 400, 800), isNotNull);
  });

  test('a failing marker file never throws', () async {
    final r = _Rig();
    r.storage.failing.add(HeatmapShots.fileName);
    r.transport.uploadReplies.add(const PulseResponse(201));
    expect(await r.shots.upload(await r.ticket(), _png, 'image/png'), isTrue);
    expect(r.warnings, isNotEmpty);
  });

  test('a throwing transport is a failure, not an exception', () async {
    final r = _Rig();
    r.transport.uploadHandler = () async => throw StateError('x');
    expect(await r.shots.upload(await r.ticket(), _png, 'image/png'), isFalse);
  });
}
