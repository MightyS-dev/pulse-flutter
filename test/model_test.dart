import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mightys_pulse/src/core/info.dart';
import 'package:mightys_pulse/src/core/model.dart';
import 'package:mightys_pulse/src/core/options.dart';

void main() {
  String? signal({
    String type = 'purchase',
    num? value = 4.5,
    Map<String, Object?>? props,
  }) => Signal.encode(
    timestamp: DateTime.utc(2026, 11, 13, 8),
    session: 'session',
    userHash: 'hash',
    type: type,
    value: value,
    props: props ?? {'item': 'coins', 'amount': 2},
    system: {
      'platform': 'desktop',
      'osName': 'Windows',
      'osVersion': '11',
      'appVersion': '1.2.3',
      'appBuildNumber': '42',
      'deviceModel': 'Desktop',
      'locale': 'sr-RS',
      'sdkName': PulseInfo.sdkName,
      'sdkVersion': PulseInfo.version,
    },
    debug: false,
  );
  test('contract shape matches the reference fixture', () {
    final copy = File('test/fixtures/v1.jsonc').readAsStringSync();
    final fixture =
        (jsonDecode(copy.replaceAll(RegExp(r'//[^\n]*'), '')) as List<Object?>)
                .first
            as Map<String, Object?>;
    final event = jsonDecode(signal()!) as Map<String, Object?>;
    expect(event.keys.toSet(), fixture.keys.toSet());
    expect(event.keys.toList(), [
      'timestamp',
      'sessionId',
      'userHash',
      'type',
      'value',
      'debug',
      'system',
      'props',
    ]);
    expect(
      (event['system']! as Map<String, Object?>).keys.toSet(),
      (fixture['system']! as Map<String, Object?>).keys.toSet(),
    );
    expect(event['timestamp'], '2026-11-13T08:00:00.000Z');
    expect(signal(), signal());
  });
  test(
    'escapes and scalar props, bool strings, integers and decimal expansion',
    () {
      const text = 'quote" slash\\ control\u0001\n日本😀';
      final raw = signal(
        type: text,
        value: 1e-20,
        props: {
          'text': text,
          'yes': true,
          'no': false,
          'int': 2,
          'huge': 1e30,
          'nan': double.nan,
          'map': {'x': 1},
          'null': null,
        },
      )!;
      final event = jsonDecode(raw) as Map<String, Object?>;
      final props = event['props']! as Map<String, Object?>;
      expect(event['type'], text);
      expect(props['text'], text);
      expect(props['yes'], 'true');
      expect(props['no'], 'false');
      expect(props['int'], isA<int>());
      for (final key in ['nan', 'map', 'null']) {
        expect(props.containsKey(key), false);
      }
      expect(raw, contains('0.00000000000000000001'));
      expect(raw, contains('1000000000000000000000000000000'));
      expect(raw, isNot(contains('e+')));
    },
  );
  test('finite values, UTF-16 and invalid surrogate rejection', () {
    for (final type in [
      '',
      ' \n',
      'a' * 201,
      '😀' * 101,
      String.fromCharCode(0xd800),
    ]) {
      expect(signal(type: type), isNull);
    }
    expect(signal(type: '😀' * 100), isNotNull);
    expect(signal(value: double.nan), isNull);
    expect(signal(value: double.infinity), isNull);
    final event =
        jsonDecode(
              signal(
                props: {'lone': String.fromCharCode(0xdc00), 'fine': '😀'},
              )!,
            )
            as Map<String, Object?>;
    expect(event['props'], {'fine': '😀'});
  });
  test('props count, key, value and UTF-8 byte caps', () {
    final event =
        jsonDecode(
              signal(
                props: {
                  'k' * 129: 'bad',
                  'long': 'x' * 1025,
                  for (var i = 0; i < 50; i++) 'p$i': '界' * 340,
                },
              )!,
            )
            as Map<String, Object?>;
    final props = event['props']! as Map<String, Object?>;
    expect(props.length, lessThanOrEqualTo(32));
    expect(utf8.encode(jsonEncode(props)).length, lessThanOrEqualTo(8192));
    expect(props.containsKey('long'), false);
    final small =
        jsonDecode(signal(props: {for (var i = 0; i < 50; i++) 'p$i': i})!)
            as Map<String, Object?>;
    expect((small['props']! as Map<String, Object?>).length, 32);
  });
  test('SHA-256 standard vectors', () {
    expect(
      hashText(''),
      'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
    );
    expect(
      hashText('abc'),
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    );
  });
  test('invalid options clamp without throwing', () {
    final options = const PulseOptions(
      flushIntervalSeconds: double.nan,
      maxBatchSize: 999999,
      maxQueueSize: -2,
      maxQueueAgeDays: 999,
    ).normalized();
    expect(options.flushIntervalSeconds, 20);
    expect(options.maxBatchSize, 1000);
    expect(options.maxQueueSize, 1);
    expect(options.maxQueueAgeDays, 29);
    expect(
      const PulseOptions(
        flushIntervalSeconds: 0.001,
      ).normalized().flushIntervalSeconds,
      0.05,
    );
  });
}
