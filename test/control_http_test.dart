import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mightys_pulse/src/platform/http_transport.dart';

void main() {
  test(
    'the request carries no key and no identity, only Accept and If-None-Match',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      HttpHeaders? seen;
      String? path;
      server.listen((request) {
        seen = request.headers;
        path = request.uri.path;
        request.response
          ..statusCode = 200
          ..write('{"format":1}')
          ..close();
      });
      final reply = await IoTransport().fetchControl(
        Uri.parse('http://127.0.0.1:${server.port}/api/v1/control/abc'),
        ifNoneMatch: '"3"',
      );
      expect(reply.status, 200);
      expect(path, '/api/v1/control/abc');
      final names = <String>{};
      seen!.forEach((name, _) => names.add(name.toLowerCase()));
      expect(names, containsAll(['accept', 'if-none-match']));
      expect(names, isNot(contains('x-app-key')));
      expect(names, isNot(contains('authorization')));
      expect(names, isNot(contains('cookie')));
      expect(seen!.value('accept'), 'application/json');
      expect(seen!.value('if-none-match'), '"3"');
    },
  );

  test('a body over 65536 bytes counts as a failure', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) {
      request.response
        ..statusCode = 200
        ..write('x' * 70000)
        ..close();
    });
    final reply = await IoTransport().fetchControl(
      Uri.parse('http://127.0.0.1:${server.port}/api/v1/control/abc'),
    );
    expect(reply.status, 0);
    expect(reply.body, isEmpty);
  });

  test('a server that never answers is dropped after 5 seconds', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) {
      /* Never answers. */
    });
    final sw = Stopwatch()..start();
    final reply = await IoTransport().fetchControl(
      Uri.parse('http://127.0.0.1:${server.port}/api/v1/control/abc'),
    );
    expect(reply.status, 0);
    expect(sw.elapsed, lessThan(const Duration(seconds: 7)));
    expect(sw.elapsed, greaterThanOrEqualTo(const Duration(seconds: 4)));
  });
}
