import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mightys_pulse/src/core/control_decision.dart';
import 'package:mightys_pulse/src/core/control_rules.dart';
import 'package:mightys_pulse/src/core/control_state.dart';
import 'package:mightys_pulse/src/core/control_state_builder.dart';
import 'package:mightys_pulse/src/core/model.dart';

/// Every combination of outcome, rules and context (7680 of them) turns into
/// the same public state as the first, long-hand builder made: the SHA-256 of
/// all lines was recorded from it. To see the lines, run with
/// `CONTROL_SNAPSHOT=<file>` (written there, compare two runs with diff).
void main() {
  test('the state builder matches the recorded snapshot', () {
    final lines = <String>[];
    final now = DateTime.utc(2026, 11, 16, 10);
    final full = ControlRules.fromMap({
      'format': 1,
      'version': 3,
      'update': {
        'android': {
          'min': '2.0.0',
          'latest': '3.0.0',
          'mode': 'required',
          'storeVersion': '3.0.0',
          'storeUrl': 'https://store.invalid/app',
        },
      },
      'maintenance': {
        'startsAt': '2026-11-16T11:30:00Z',
        'endsAt': '2026-11-17T13:05:00Z',
        'headsUpMinutes': 120,
      },
      'announcement': {
        'id': 'a1',
        'until': '2026-12-01T00:00:00Z',
        'title': 'News for {appName}',
        'body': 'Body {version}',
        'url': 'https://news.invalid/news',
        'buttonText': 'Read',
      },
      'whatsNew': {'version': '1.0.0', 'body': 'Fixes in {version}'},
      'texts': {
        'custom': {
          'maintenance': {'title': 'Back soon', 'body': null, 'buttonText': ''},
          'versionBlocked': {'body': 'Own {appName} text'},
          'whatsNew': {'buttonText': 'Nice'},
          'announcement': {'title': 'Own title'},
        },
      },
    });
    final bare = ControlRules.fromMap({'format': 1, 'version': 1});
    const outcomes = [
      'normal',
      'updateRequired',
      'updateSuggested',
      'versionBlocked',
      'maintenance',
    ];
    const bannerSets = [
      <String>[],
      ['testBuild'],
      ['maintenanceUpcoming'],
      ['maintenanceUpcoming', 'testBuild'],
    ];
    for (final state in outcomes) {
      for (final allow in [true, false]) {
        for (final banners in bannerSets) {
          for (final card in [null, 'whatsNew', 'announcement']) {
            for (final rules in [full, bare]) {
              for (final canOpen in [true, false]) {
                for (final fallback in [null, 'https://fallback.invalid']) {
                  for (final tags in [
                    ['en-US'],
                    ['de'],
                    ['ja-JP'],
                    <String>[],
                  ]) {
                    for (final name in ['', 'Garden']) {
                      final s = ControlStateBuilder.build(
                        ControlOutcome(state, allow, banners, card),
                        rules,
                        ControlContext(
                          appName: name,
                          appVersion: '1.0.0',
                          languageTags: tags,
                          fallbackStoreUrl: fallback,
                          now: now,
                          localTime: (t) => t.add(const Duration(hours: 1)),
                          canOpenStore: canOpen,
                        ),
                        'android',
                      );
                      lines.add(
                        [
                          state,
                          allow,
                          banners.join('+'),
                          card,
                          identical(rules, full) ? 'full' : 'bare',
                          canOpen,
                          fallback,
                          tags.join('+'),
                          name,
                          '=>',
                          describe(s),
                        ].join('|'),
                      );
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
    final text = '${lines.join('\n')}\n';
    final out = Platform.environment['CONTROL_SNAPSHOT'];
    if (out != null) File(out).writeAsStringSync(text);
    expect(lines.length, 7680);
    expect(
      hashText(text),
      'ba78810ff1c569027bbde06225f24c7c7805f4caa005a3b0c7795e10afd03bd1',
    );
  });
}

String describe(ControlState s) => [
  s.kind.name,
  s.title,
  s.body,
  s.buttonText,
  s.secondaryButtonText,
  s.url,
  s.startsAt?.toIso8601String(),
  s.endsAt?.toIso8601String(),
  s.version,
  s.allowContinue,
  s.isTestBuild,
  s.testBuildText,
].join('|');
