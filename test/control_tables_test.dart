import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mightys_pulse/src/core/control_decision.dart';
import 'package:mightys_pulse/src/core/control_rules.dart';
import 'package:mightys_pulse/src/core/control_texts.dart';
import 'package:mightys_pulse/src/core/control_version.dart';

/// The four shared tables are optional test fixtures. Where they are
/// not bundled these tests skip, visibly.
const _dir = 'test/fixtures/control-v1';
final _present = File('$_dir/version-cases.json').existsSync();
final _skip = _present ? null : 'shared App Control tables are not bundled';

Object? _json(String name) =>
    jsonDecode(File('$_dir/$name').readAsStringSync());
String _sha(String name) =>
    sha256.convert(File('$_dir/$name').readAsBytesSync()).toString();

ControlInput _input(Map<String, Object?> row) => ControlInput(
  rules: row['rules'] == null
      ? null
      : ControlRules.fromMap(row['rules']! as Map<String, Object?>),
  now: ControlTime.parse(row['now']! as String)!,
  platform: row['platform']! as String,
  appVersion: row['appVersion']! as String,
  debug: row['debug']! as bool,
  sdk: row['sdk']! as String,
  fromCache: row['fromCache']! as bool,
  cacheAgeHours: (row['cacheAgeHours']! as num).toDouble(),
  updateReturns: (row['updateReturns']! as num).toInt(),
  playUpdateNotAvailable: row['playUpdateNotAvailable']! as bool,
  canBuildStoreLink: row['canBuildStoreLink']! as bool,
  suggestDismissedHoursAgo: (row['suggestDismissedHoursAgo'] as num?)
      ?.toDouble(),
  shownAnnouncements: (row['shownAnnouncements']! as List)
      .cast<String>()
      .toSet(),
  justUpdated: row['justUpdated']! as bool,
  whatsNewShown: row['whatsNewShown']! as bool,
);

void main() {
  test('fixtures are byte identical to the server package', () {
    expect(
      _sha('version-cases.json'),
      '027cc69450b95177d4c50ee2a9026df3dfe05e2b6f46d4e449dca872b4ab4009',
    );
    expect(
      _sha('decision-cases.json'),
      'fdc4ef65c3bf22e1a5775e756d5660cf3608085eb2a5977c683b25affd15c622',
    );
    expect(
      _sha('control-id-cases.json'),
      'f236a1c986276ea69aeca69ccafff368ba8a07a749269986814e57b256d01b2f',
    );
    expect(
      _sha('texts.json'),
      '39aac628bda36bbb86fb4a091dad3252be82dd2a6353af9ea1db574a5264dbf4',
    );
  }, skip: _skip);

  test('every version case passes', () {
    final cases = (_json('version-cases.json')! as List)
        .cast<Map<String, Object?>>();
    expect(cases.length, greaterThanOrEqualTo(200));
    for (final row in cases) {
      final r = row['result'];
      final expected = r == 'incomparable' ? null : (r! as num).toInt();
      expect(
        ControlVersion.compare(row['a']! as String, row['b']! as String),
        expected,
        reason: '${row['a']} vs ${row['b']}',
      );
    }
  }, skip: _skip);

  test('every decision case passes', () {
    final cases = (_json('decision-cases.json')! as List)
        .cast<Map<String, Object?>>();
    expect(cases.length, greaterThanOrEqualTo(60));
    for (final row in cases) {
      final expected = row['expected']! as Map<String, Object?>;
      final outcome = ControlDecision.decide(
        _input(row['input']! as Map<String, Object?>),
      );
      final label = row['name']! as String;
      expect(outcome.state, expected['state'], reason: label);
      expect(outcome.allowContinue, expected['allowContinue'], reason: label);
      expect(outcome.banners, expected['banners'], reason: label);
      expect(outcome.card, expected['card'], reason: label);
    }
  }, skip: _skip);

  test('control ids match for every key', () {
    final cases = (_json('control-id-cases.json')! as List)
        .cast<Map<String, Object?>>();
    expect(cases.length, greaterThanOrEqualTo(10));
    for (final row in cases) {
      expect(
        ControlIds.forKey(row['key']! as String),
        row['controlId'],
        reason: row['note']! as String,
      );
    }
  }, skip: _skip);

  test('built-in texts equal the shared table', () {
    final root = _json('texts.json')! as Map<String, Object?>;
    final languages = (root['languages']! as List).cast<String>();
    expect(ControlTexts.languages, languages);
    final table = root['texts']! as Map<String, Object?>;
    for (final language in languages) {
      expect(
        ControlTexts.table(language),
        (table[language]! as Map).cast<String, String>(),
        reason: language,
      );
    }
  }, skip: _skip);

  test('language pick: app language, region forms, then English', () {
    expect(ControlTexts.pick(['de-AT']), 'de');
    expect(ControlTexts.pick(['pt_PT']), 'pt-BR');
    expect(ControlTexts.pick(['zh-TW']), 'zh-Hans');
    expect(ControlTexts.pick(['sr-Cyrl']), 'sr-Latn');
    expect(ControlTexts.pick(['xx', 'fr']), 'fr');
    expect(ControlTexts.pick(['']), 'en');
    expect(ControlTexts.pick(const []), 'en');
  });

  test('a body over 65536 bytes or another format is never read', () {
    expect(
      ControlRules.parse(utf8.encode('{"format":1,"pad":"${'x' * 70000}"}')),
      isNull,
    );
    expect(ControlRules.parse(utf8.encode('{"format":2}')), isNull);
    expect(ControlRules.parse(utf8.encode('[1]')), isNull);
    expect(
      ControlRules.parse(
        utf8.encode('{"format":1,"update":{"ios":5},"blocked":"x"}'),
      ),
      isNotNull,
    );
  });
}
