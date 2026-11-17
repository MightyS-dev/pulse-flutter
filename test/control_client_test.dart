import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mightys_pulse/src/core/control_state.dart';
import 'package:mightys_pulse/src/core/model.dart';
import 'package:mightys_pulse/src/core/options.dart';
import 'package:mightys_pulse/src/core/ports.dart';
import 'support_control.dart';
import 'support.dart';

void main() {
  group('check and state', () {
    test('a required update shows once the rules arrive', () async {
      final rig = Rig(appVersion: '1.0.0')
        ..reply(rulesJson(update: requiredUpdate('2.0.0')));
      rig.start();
      expect(rig.client.state.kind, ControlKind.normal);
      await rig.settle();
      expect(rig.client.state.kind, ControlKind.updateRequired);
      expect(rig.client.state.allowContinue, false);
      expect(rig.client.state.url, 'https://pulse.mightys.dev/app');
      expect(rig.client.state.body, contains('Garden'));
      expect(rig.transport.controlRequests.single.url.toString(), controlUrl);
    });

    test('listeners hear each change once', () async {
      final rig = Rig(appVersion: '1.0.0')
        ..reply(rulesJson(update: requiredUpdate('2.0.0')));
      final seen = <ControlKind>[];
      rig.client.addListener((s) => seen.add(s.kind));
      rig.start();
      await rig.settle();
      rig.client.reevaluate();
      expect(seen, [ControlKind.updateRequired]);
    });

    test('a throwing listener never breaks the client', () async {
      final rig = Rig(appVersion: '1.0.0')
        ..reply(rulesJson(update: requiredUpdate('2.0.0')));
      rig.client.addListener((_) => throw StateError('boom'));
      rig.start();
      await rig.settle();
      expect(rig.client.state.kind, ControlKind.updateRequired);
    });

    test('custom text replaces the built-in title and body', () async {
      final rig = Rig(appVersion: '1.0.0')
        ..reply(
          rulesJson(
            update: requiredUpdate('2.0.0'),
            custom: {
              'updateRequired': {
                'title': 'Please upgrade',
                'body': 'Custom {appName}',
                'buttonText': null,
              },
            },
          ),
        );
      rig.start();
      await rig.settle();
      expect(rig.client.state.title, 'Please upgrade');
      expect(rig.client.state.body, 'Custom Garden');
      expect(rig.client.state.buttonText, 'Update');
    });

    test(
      'If-None-Match carries the cached ETag and 304 keeps the state',
      () async {
        final rig = Rig(appVersion: '1.0.0');
        rig.seedCache(
          rulesJson(version: 7, update: requiredUpdate('2.0.0')),
          etag: '"7"',
        );
        rig.reply('', status: 304);
        rig.start();
        await rig.settle();
        expect(rig.transport.controlRequests.single.etag, '"7"');
        expect(rig.client.state.kind, ControlKind.updateRequired);
      },
    );
  });

  group('seven failures', () {
    final failures = <String, Future<PulseResponse> Function()>{
      'server down': () async => const PulseResponse(0),
      'dns error': () async => throw StateError('dns'),
      'tls error': () async => throw const FormatException('tls'),
      'http 500': () async => const PulseResponse(500, body: 'oops'),
      'thirty seconds without an answer': () =>
          Completer<PulseResponse>().future,
      'body that is not json': () async =>
          const PulseResponse(200, body: '<html>'),
      'body of 10 MB': () async => PulseResponse(
        200,
        body: '{"format":1,"x":"${'a' * 10 * 1024 * 1024}"}',
      ),
    };
    for (final entry in failures.entries) {
      test(
        '${entry.key}: no screen without a cache, last known state with one',
        () async {
          final fresh = Rig(appVersion: '1.0.0')
            ..transport.controlHandler = entry.value;
          final sw = Stopwatch()..start();
          fresh.start();
          expect(sw.elapsedMilliseconds, lessThan(50));
          await fresh.settle();
          await fresh.advance(5);
          expect(fresh.client.state.kind, ControlKind.normal);
          expect(fresh.requests, 1, reason: 'no retry loop');
          await fresh.advance(30);
          expect(
            fresh.requests,
            1,
            reason: 'no retry before the next foreground',
          );

          final cached = Rig(appVersion: '1.0.0');
          cached.seedCache(rulesJson(update: requiredUpdate('2.0.0')));
          cached.transport.controlHandler = entry.value;
          cached.start();
          await cached.settle();
          await cached.advance(5);
          expect(cached.client.state.kind, ControlKind.updateRequired);
        },
      );
    }

    test(
      'a hanging request frees the slot after 5 seconds, then 60 seconds apart',
      () async {
        final rig = Rig(appVersion: '1.0.0')
          ..transport.controlHandler = () => Completer<PulseResponse>().future;
        rig.start();
        await rig.settle();
        rig.client.onForeground();
        await rig.advance(5);
        expect(rig.requests, 1);
        await rig.advance(61);
        rig.client.onForeground();
        await rig.settle();
        expect(rig.requests, 2);
      },
    );
  });

  group('cache', () {
    test(
      'first launch without a network and without a cache is normal',
      () async {
        final rig = Rig(appVersion: '1.0.0');
        rig.start();
        await rig.settle();
        expect(rig.client.state, ControlState.normal);
      },
    );

    test('a 31 day old cache ignores the locking rules', () async {
      final rig = Rig(appVersion: '1.0.0');
      rig.seedCache(
        rulesJson(update: requiredUpdate('2.0.0')),
        savedAt: rig.time.now.subtract(const Duration(days: 31)),
      );
      rig.start();
      await rig.settle();
      expect(rig.client.state.kind, ControlKind.normal);
    });

    test('a 29 day old cache still locks', () async {
      final rig = Rig(appVersion: '1.0.0');
      rig.seedCache(
        rulesJson(update: requiredUpdate('2.0.0')),
        savedAt: rig.time.now.subtract(const Duration(days: 29)),
      );
      rig.start();
      await rig.settle();
      expect(rig.client.state.kind, ControlKind.updateRequired);
    });

    test('an expired maintenance from the cache is ignored', () async {
      final rig = Rig();
      final now = rig.time.now;
      rig.seedCache(
        rulesJson(
          maintenance: {
            'startsAt': now
                .subtract(const Duration(hours: 3))
                .toIso8601String(),
            'endsAt': now.subtract(const Duration(hours: 1)).toIso8601String(),
            'headsUpMinutes': 0,
            'exemptAboveStore': false,
            'platforms': null,
          },
        ),
      );
      rig.start();
      await rig.settle();
      expect(rig.client.state.kind, ControlKind.normal);
    });

    test('a maintenance from the cache never lasts past 72 hours', () async {
      final rig = Rig();
      final now = rig.time.now;
      rig.seedCache(
        rulesJson(
          maintenance: {
            'startsAt': now
                .subtract(const Duration(hours: 73))
                .toIso8601String(),
            'endsAt': now.add(const Duration(hours: 10)).toIso8601String(),
            'headsUpMinutes': 0,
            'exemptAboveStore': false,
            'platforms': null,
          },
        ),
      );
      rig.start();
      await rig.settle();
      expect(rig.client.state.kind, ControlKind.normal);
    });

    test('304 keeps the cache and refreshes the success time', () async {
      final rig = Rig(appVersion: '1.0.0');
      rig.seedCache(
        rulesJson(update: requiredUpdate('2.0.0')),
        savedAt: rig.time.now.subtract(const Duration(days: 29, hours: 23)),
      );
      rig.reply('', status: 304);
      rig.start();
      await rig.settle();
      await rig.advance(2 * 3600);
      expect(
        rig.client.state.kind,
        ControlKind.updateRequired,
        reason: 'the refreshed time keeps the cache young',
      );
    });

    test('a good answer is stored for the next launch', () async {
      final rig = Rig(appVersion: '1.0.0')
        ..reply(rulesJson(version: 9, update: requiredUpdate('2.0.0')));
      rig.start();
      await rig.settle();
      final name = rig.storage.files.keys.firstWhere(
        (n) => n.startsWith('control-') && !n.contains('local'),
      );
      expect(
        String.fromCharCodes(rig.storage.files[name]!),
        startsWith('"9"\n'),
      );
    });
  });

  group('switches', () {
    Future<Rig> showing() async {
      final rig = Rig(appVersion: '1.0.0')
        ..reply(rulesJson(update: requiredUpdate('2.0.0')));
      rig.start();
      await rig.settle();
      expect(rig.client.state.kind, ControlKind.updateRequired);
      return rig;
    }

    test(
      'disabledSdkVersions clears a shown screen at the next check',
      () async {
        final rig = await showing();
        rig.reply(
          rulesJson(
            version: 2,
            update: requiredUpdate('2.0.0'),
            disabled: ['pulse-flutter@0.9.7'],
          ),
        );
        await rig.advance(61);
        rig.client.onForeground();
        await rig.settle();
        expect(rig.client.state.kind, ControlKind.normal);
      },
    );

    test('off clears a shown screen at the next check', () async {
      final rig = await showing();
      rig.reply(
        rulesJson(version: 2, off: true, update: requiredUpdate('2.0.0')),
      );
      await rig.advance(61);
      rig.client.onForeground();
      await rig.settle();
      expect(rig.client.state.kind, ControlKind.normal);
    });

    test('mode off makes no request and stays normal', () async {
      final rig = Rig(appVersion: '1.0.0')
        ..reply(rulesJson(update: requiredUpdate('2.0.0')));
      rig.start(mode: ControlMode.off);
      rig.client.onForeground();
      rig.client.checkNow();
      await rig.advance(120);
      rig.client.onForeground();
      await rig.settle();
      expect(rig.requests, 0);
      expect(rig.client.state, ControlState.normal);
    });
  });

  group('loop guard', () {
    test(
      'storeVersion equal to the installed version gives a suggestion',
      () async {
        final rig = Rig(appVersion: '1.0.0')
          ..reply(
            rulesJson(update: requiredUpdate('2.0.0', storeVersion: '1.0.0')),
          );
        rig.start();
        await rig.settle();
        expect(rig.client.state.kind, ControlKind.updateSuggested);
        expect(rig.client.state.allowContinue, true);
      },
    );

    test('three returns on the same version give a suggestion', () async {
      final rig = Rig(appVersion: '1.0.0')
        ..reply(rulesJson(update: requiredUpdate('2.0.0')));
      rig.start();
      await rig.settle();
      for (var i = 0; i < 3; i++) {
        expect(
          rig.client.state.kind,
          ControlKind.updateRequired,
          reason: 'before return $i',
        );
        rig.client.noteUpdatePressed();
        await rig.settle();
        rig.client.onForeground();
        await rig.settle();
      }
      expect(rig.client.state.kind, ControlKind.updateSuggested);
    });

    test('no way to open the store gives a suggestion, never a lock', () async {
      final rig = Rig(appVersion: '1.0.0')
        ..reply(rulesJson(update: requiredUpdate('2.0.0')));
      rig.client.canOpenStore = () => false;
      rig.start();
      await rig.settle();
      expect(rig.client.state.kind, ControlKind.updateSuggested);
      rig.client.canOpenStore = () => true;
      rig.client.reevaluate();
      expect(rig.client.state.kind, ControlKind.updateRequired);
    });

    test('no store link at all gives a suggestion', () async {
      final rig = Rig(appVersion: '1.0.0')
        ..reply(rulesJson(update: requiredUpdate('2.0.0', storeUrl: null)));
      rig.start();
      await rig.settle();
      expect(rig.client.state.kind, ControlKind.updateSuggested);
    });
  });

  group('dismiss, cards, bars', () {
    test(
      'a dismissed suggestion stays away for 24 hours, then returns',
      () async {
        final rig = Rig(appVersion: '1.0.0')
          ..reply(
            rulesJson(
              update: {
                'ios': {
                  'min': null,
                  'latest': '2.0.0',
                  'mode': 'suggested',
                  'storeVersion': null,
                  'storeUrl': 'https://pulse.mightys.dev/app',
                },
              },
            ),
          );
        rig.start();
        await rig.settle();
        expect(rig.client.state.kind, ControlKind.updateSuggested);
        rig.client.dismiss();
        await rig.settle();
        expect(rig.client.state.kind, ControlKind.normal);
        await rig.advance(23 * 3600);
        expect(rig.client.state.kind, ControlKind.normal);
        await rig.advance(2 * 3600);
        expect(rig.client.state.kind, ControlKind.updateSuggested);
      },
    );

    test('a locking screen ignores dismiss', () async {
      final rig = Rig(appVersion: '1.0.0')
        ..reply(rulesJson(update: requiredUpdate('2.0.0')));
      rig.start();
      await rig.settle();
      rig.client.dismiss();
      await rig.settle();
      expect(rig.client.state.kind, ControlKind.updateRequired);
    });

    test('an announcement is shown once per device', () async {
      final rig = Rig();
      rig.reply(
        rulesJson(
          announcement: {
            'id': 'a7',
            'title': 'Winter event',
            'body': 'Snow is here.',
            'url': null,
            'buttonText': null,
            'until': rig.time.now
                .add(const Duration(days: 3))
                .toIso8601String(),
            'platforms': null,
          },
        ),
      );
      rig.start();
      await rig.settle();
      expect(rig.client.state.kind, ControlKind.announcement);
      expect(rig.client.state.title, 'Winter event');
      rig.client.dismiss();
      await rig.settle();
      expect(rig.client.state.kind, ControlKind.normal);
    });

    test('what is new shows after an update and only once', () async {
      final rig = Rig(appVersion: '2.0.0');
      rig.reply(
        rulesJson(whatsNew: {'version': '2.0.0', 'body': 'Bigger gardens.'}),
      );
      // First launch of this version: the saved version is older.
      final local = 'control-local-${hashText(controlKey).substring(0, 16)}';
      rig.storage.files[local] = '{"appVersion":"1.9.0"}'.codeUnits;
      rig.start();
      await rig.settle();
      expect(rig.client.state.kind, ControlKind.whatsNew);
      expect(rig.client.state.body, 'Bigger gardens.');
      rig.client.dismiss();
      await rig.settle();
      expect(rig.client.state.kind, ControlKind.normal);
    });

    test(
      'the maintenance bar shows before the start and the screen inside the window',
      () async {
        final rig = Rig();
        final start = rig.time.now.add(const Duration(minutes: 30));
        rig.reply(
          rulesJson(
            maintenance: {
              'startsAt': start.toIso8601String(),
              'endsAt': start.add(const Duration(hours: 1)).toIso8601String(),
              'headsUpMinutes': 60,
              'exemptAboveStore': false,
              'platforms': null,
            },
          ),
        );
        rig.start();
        await rig.settle();
        expect(rig.client.state.kind, ControlKind.maintenanceUpcoming);
        expect(
          rig.client.state.body,
          matches(RegExp(r'^Scheduled maintenance at \d+:\d\d (AM|PM)\.$')),
        );
        await rig.advance(31 * 60);
        expect(rig.client.state.kind, ControlKind.maintenance);
        expect(rig.client.state.allowContinue, false);
      },
    );

    test('a debug build adds the test banner and a Continue button', () async {
      final rig = Rig(appVersion: '1.0.0')
        ..reply(rulesJson(update: requiredUpdate('2.0.0')));
      rig.start(debug: true);
      await rig.settle();
      expect(rig.client.state.isTestBuild, true);
      expect(rig.client.state.testBuildText, 'Test build: App Control preview');
      expect(rig.client.state.allowContinue, true);
      expect(rig.client.state.secondaryButtonText, 'Continue');
      rig.client.dismiss();
      await rig.settle();
      expect(rig.client.state.kind, ControlKind.normal);
    });
  });

  group('time', () {
    test(
      'a scheduled maintenance starts and ends within 5 seconds, offline',
      () async {
        final rig = Rig();
        final start = rig.time.now.add(const Duration(minutes: 10));
        final end = start.add(const Duration(minutes: 20));
        rig.reply(
          rulesJson(
            maintenance: {
              'startsAt': start.toIso8601String(),
              'endsAt': end.toIso8601String(),
              'headsUpMinutes': 0,
              'exemptAboveStore': false,
              'platforms': null,
            },
          ),
        );
        rig.start();
        await rig.settle();
        expect(rig.client.state.kind, ControlKind.normal);
        rig.transport.controlHandler = () async => const PulseResponse(0);
        await rig.advance(10 * 60 - 1);
        expect(rig.client.state.kind, ControlKind.normal);
        await rig.advance(2);
        expect(rig.client.state.kind, ControlKind.maintenance);
        await rig.advance(20 * 60);
        expect(rig.client.state.kind, ControlKind.normal);
      },
    );

    test('foreground checks are at least 60 seconds apart', () async {
      final rig = Rig()..reply(rulesJson());
      rig.start();
      await rig.settle();
      expect(rig.requests, 1);
      rig.client.onForeground();
      await rig.advance(30);
      rig.client.onForeground();
      await rig.settle();
      expect(rig.requests, 1);
      await rig.advance(31);
      rig.client.onForeground();
      await rig.settle();
      expect(rig.requests, 2);
    });
  });

  group('through the runtime', () {
    test('init returns at once even when App Control never answers', () async {
      final times = <int>[];
      for (var i = 0; i < 20; i++) {
        final h = Harness(initialize: false);
        h.transport.controlHandler = () => Completer<PulseResponse>().future;
        final sw = Stopwatch()..start();
        await h.runtime.initialize(
          'synthetic-key',
          options: const PulseOptions(debug: false),
        );
        times.add(sw.elapsedMicroseconds);
      }
      final average = times.reduce((a, b) => a + b) / times.length / 1000;
      expect(average, lessThan(5), reason: 'average ms over 20 runs: $average');
    });

    test(
      'opt-out does not stop App Control and the request carries no key',
      () async {
        final h = Harness(initialize: false);
        h.transport.controlReply = PulseResponse(200, body: rulesJson());
        await h.runtime.setOptOut(true);
        await h.runtime.initialize(
          'synthetic-key',
          options: const PulseOptions(debug: false),
        );
        await h.settle();
        expect(h.transport.controlRequests, hasLength(1));
        expect(
          h.transport.controlRequests.single.url.toString(),
          contains('/api/v1/control/'),
        );
        expect(
          h.transport.controlRequests.single.url.toString(),
          isNot(contains('synthetic-key')),
        );
        expect(
          h.transport.configRequests,
          isEmpty,
          reason: 'analytics config is off while opted out',
        );
      },
    );

    test('mode off through the options makes no request', () async {
      final h = Harness(initialize: false);
      await h.runtime.initialize(
        'synthetic-key',
        options: const PulseOptions(debug: false, control: ControlMode.off),
      );
      await h.settle();
      h.runtime.appForeground(cold: false);
      await h.advance(120);
      h.runtime.appForeground(cold: false);
      await h.settle();
      expect(h.transport.controlRequests, isEmpty);
    });

    test(
      'the controlId and cache name use the key, the key is never sent',
      () async {
        final h = Harness(initialize: false);
        h.transport.controlReply = PulseResponse(200, body: rulesJson());
        await h.runtime.initialize(
          'synthetic-key',
          options: const PulseOptions(debug: false),
        );
        await h.settle();
        expect(
          h.transport.controlRequests.single.url.toString(),
          'https://in.mightys.dev/api/v1/control/${controlUrl.split('/').last}',
        );
        expect(
          h.storage.files.keys.where((n) => n.startsWith('control-')),
          hasLength(2),
        );
      },
    );
  });
}
