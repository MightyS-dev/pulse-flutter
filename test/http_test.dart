import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mightys_pulse/src/core/ports.dart';
import 'package:mightys_pulse/src/platform/http_transport.dart';

void main() {
  test(
    'real localhost POST headers, gzip payload, advice and Retry-After',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final received = Completer<void>();
      server.listen((request) async {
        expect(request.method, 'POST');
        expect(request.headers.value('X-App-Key'), 'synthetic');
        expect(request.headers.value('User-Agent'), 'pulse-flutter/0.9.0');
        expect(request.headers.value('Content-Encoding'), 'gzip');
        expect(request.headers.contentType?.mimeType, 'application/json');
        expect(request.headers.value('Cookie'), isNull);
        final bytes = await request.fold<List<int>>([], (a, b) => a..addAll(b));
        expect(utf8.decode(gzip.decode(bytes)), '[{"type":"real"}]');
        request.response.statusCode = 429;
        request.response.headers.set('Retry-After', '60');
        request.response.write('{"pause":false}');
        await request.response.close();
        received.complete();
      });
      final transport = IoTransport();
      final response = await transport.send(
        PulseRequest(
          Uri.parse('http://127.0.0.1:${server.port}/api/v1/signals'),
          'synthetic',
          gzip.encode(utf8.encode('[{"type":"real"}]')),
          true,
        ),
      );
      await received.future;
      expect(response.status, 429);
      expect(response.retryAfter, '60');
      expect(response.body, '{"pause":false}');
    },
  );
  test('redirect never forwards key or follows Location', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    var count = 0;
    server.listen((r) async {
      count++;
      r.response.statusCode = 302;
      r.response.headers.set(
        'Location',
        'http://127.0.0.1:${server.port}/secret',
      );
      await r.response.close();
    });
    final response = await IoTransport().send(
      PulseRequest(Uri.parse('http://127.0.0.1:${server.port}'), 'key', [
        91,
        93,
      ], false),
    );
    expect(response.status, 302);
    expect(count, 1);
  });
  test(
    'oversized advice keeps known acknowledgement with empty body',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((r) async {
        r.response.statusCode = 202;
        r.response.write('x' * 70000);
        await r.response.close();
      });
      final response = await IoTransport().send(
        PulseRequest(Uri.parse('http://127.0.0.1:${server.port}'), 'key', [
          91,
          93,
        ], false),
      );
      expect(response.status, 202);
      expect(response.body, '');
    },
  );
  test('timeout and cancellation produce safe network responses', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final started = Completer<void>();
    server.listen((r) {
      if (!started.isCompleted) {
        started.complete();
      }
    });
    final request = PulseRequest(
      Uri.parse('http://127.0.0.1:${server.port}'),
      'key',
      [91, 93],
      false,
    );
    expect(
      (await IoTransport(
        timeout: const Duration(milliseconds: 20),
      ).send(request)).status,
      0,
    );
    final transport = IoTransport();
    final future = transport.send(request);
    await started.future;
    transport.cancel();
    expect((await future).status, 0);
  });
}
