import 'package:flutter_test/flutter_test.dart';
import 'package:mightys_pulse/src/core/advice.dart';
import 'package:mightys_pulse/src/core/ports.dart';
import 'support.dart';

void main() {
  test(
    'bounded advice rejects malformed, duplicates, decoded duplicates and deep nesting',
    () {
      for (final body in [
        '',
        'null',
        '[]',
        'malformed',
        '{"pause":true,}',
        '{"pause":true,"pa\\u0075se":false}',
        '[' * 34 + ']' * 34,
        'x' * 65537,
      ]) {
        expect(
          Advice.parse(body),
          isNull,
          reason: body.substring(0, body.length.clamp(0, 80)),
        );
      }
      expect(
        Advice.parse(
          '{"unknown":{"nested":[null,1,"a"]},"pa\\u0075se":true}',
        )?.pause,
        true,
      );
    },
  );
  test('clamps, nonsense fields and valid sibling pause', () async {
    for (final pair in [
      ('{"recommendedSendIntervalSeconds":1,"pause":true}', 5.0),
      ('{"recommendedSendIntervalSeconds":999999,"pause":true}', 3600.0),
      ('{"recommendedSendIntervalSeconds":"bad","pause":true}', 20.0),
      ('{"recommendedSendIntervalSeconds":-1,"pause":true}', 20.0),
    ]) {
      final h = Harness();
      h.transport.replies.add(PulseResponse(202, body: pair.$1));
      await h.send();
      h.runtime.track('paused');
      await h.flush();
      await h.advance(pair.$2 - 0.001);
      expect(h.transport.requests.length, 1);
      await h.advance(0.001);
      expect(h.transport.requests.length, 2);
    }
    for (final body in [
      '{}',
      '{"pause":"true"}',
      '{"recommendedSendIntervalSeconds":true}',
      '{"recommendedSendIntervalSeconds":0}',
      '{"RecommendedSendIntervalSeconds":60}',
    ]) {
      final h = Harness();
      h.transport.replies.add(PulseResponse(202, body: body));
      await h.send();
      h.runtime.track('next');
      await h.settle();
      await h.advance(19.999);
      expect(h.transport.requests.length, 1);
      await h.advance(0.001);
      expect(h.transport.requests.length, 2);
    }
  });
  test('retry date and numeric invalid values ignored', () {
    final now = DateTime.utc(2026);
    for (final text in [
      '-1',
      'NaN',
      'Infinity',
      'bad',
      'Thu, 01 Nope 2026 00:00:00 GMT',
    ]) {
      expect(retryAfter(text, now), isNull);
    }
  });
}
