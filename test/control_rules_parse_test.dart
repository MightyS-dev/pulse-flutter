import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mightys_pulse/src/core/control_rules.dart';
import 'package:mightys_pulse/src/core/model.dart';

/// Reading the rules: right types, wrong types and missing fields give the
/// same rules as the first reader did (SHA-256 of every field of every case,
/// recorded from it). `CONTROL_SNAPSHOT=<file>` writes the lines.
void main() {
  test('the rules reader matches the recorded snapshot', () {
    final wrong = <Object?>[
      null,
      7,
      7.5,
      true,
      'x',
      <Object?>[],
      <String, Object?>{},
    ];
    final cases = <Map<String, Object?>>[
      {},
      {
        'format': 1,
        'version': 9,
        'off': true,
        'update': {
          'ios': {
            'min': '1.0',
            'latest': '2.0',
            'mode': 'suggested',
            'storeVersion': '2.0',
            'storeUrl': 'https://a.invalid',
          },
          'android': 5,
          'web': {'min': 3, 'mode': null},
        },
        'blocked': [
          {
            'version': '1.2',
            'platforms': ['ios', 3],
            'allowContinue': true,
          },
          {'version': 1, 'allowContinue': 'yes'},
          'bad',
        ],
        'maintenance': {
          'startsAt': '2026-11-16T10:00:00+01:30',
          'endsAt': '2026-11-16T12:00:00.123Z',
          'headsUpMinutes': 30.0,
          'exemptAboveStore': true,
          'platforms': ['android'],
        },
        'announcement': {
          'id': 'n1',
          'until': '2026-12-01T00:00:00Z',
          'title': 'T',
          'body': 'B',
          'url': 'https://u.invalid',
          'buttonText': 'Go',
          'platforms': 'ios',
        },
        'whatsNew': {'version': '2.0', 'body': 5},
        'texts': {
          'custom': {
            'maintenance': {'title': 'M', 'body': 1, 'buttonText': 'K'},
            'x': 'bad',
          },
        },
        'disabledSdkVersions': ['a@1', 2],
      },
      {
        'format': 1.0,
        'version': 2.5,
        'maintenance': {'startsAt': '2026-11-16T10:00:00Z', 'endsAt': 'soon'},
        'announcement': {'id': 3, 'until': '2026-12-01T00:00:00Z'},
        'whatsNew': 'bad',
        'texts': 'bad',
      },
      for (final field in [
        'format',
        'version',
        'off',
        'update',
        'blocked',
        'maintenance',
        'announcement',
        'whatsNew',
        'texts',
        'disabledSdkVersions',
      ])
        for (final value in wrong) {'format': 1, field: value},
      for (final value in wrong)
        {
          'format': 1,
          'maintenance': {
            'startsAt': '2026-11-16T10:00:00Z',
            'endsAt': '2026-11-16T11:00:00Z',
            'headsUpMinutes': value,
            'exemptAboveStore': value,
            'platforms': value,
          },
          'announcement': {
            'id': 'a',
            'until': '2026-11-16T11:00:00Z',
            'title': value,
            'platforms': value,
          },
          'update': {
            'ios': {'min': value, 'storeUrl': value},
          },
          'texts': {
            'custom': {'whatsNew': value},
          },
        },
    ];
    final lines = [for (final c in cases) describe(ControlRules.fromMap(c))];
    lines.add(
      '${ControlRules.parse(utf8.encode(jsonEncode(cases[1])))?.version}',
    );
    final text = '${lines.join('\n')}\n';
    final out = Platform.environment['CONTROL_SNAPSHOT'];
    if (out != null) File(out).writeAsStringSync(text);
    expect(
      hashText(text),
      '8b6ed694534323e52f8c07fbe2110fc826b4b7ca7faddd3303ac6fc3570aa715',
    );
  });
}

String describe(ControlRules r) {
  String set(Set<String>? s) =>
      s == null ? 'null' : (s.toList()..sort()).join('+');
  final m = r.maintenance, a = r.announcement, w = r.whatsNew;
  return [
    r.format,
    r.version,
    r.off,
    for (final e in r.update.entries)
      '${e.key}:${e.value.min},${e.value.latest},${e.value.mode},${e.value.storeVersion},${e.value.storeUrl}',
    for (final b in r.blocked)
      'b:${b.version},${set(b.platforms)},${b.allowContinue}',
    m == null
        ? 'm:null'
        : 'm:${m.startsAt.toIso8601String()},${m.endsAt.toIso8601String()},${m.headsUpMinutes},${m.exemptAboveStore},${set(m.platforms)}',
    a == null
        ? 'a:null'
        : 'a:${a.id},${a.until.toIso8601String()},${a.title},${a.body},${a.url},${a.buttonText},${set(a.platforms)}',
    w == null ? 'w:null' : 'w:${w.version},${w.body}',
    for (final e in r.custom.entries)
      'c:${e.key}:${e.value.title},${e.value.body},${e.value.buttonText}',
    'd:${r.disabledSdkVersions.join('+')}',
  ].join('|');
}
