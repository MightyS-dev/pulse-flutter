import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mightys_pulse/src/core/config.dart';
import 'package:mightys_pulse/src/core/options.dart';

import 'support.dart';

Map<String, Object?> systemOf(Map<String, Object?> e) =>
    e['system']! as Map<String, Object?>;
Map<String, Object?> propsOf(Map<String, Object?> e) =>
    e['props']! as Map<String, Object?>;

String config({
  List<String> enabled = const [],
  List<String> paused = const [],
  List<String> disabled = const [],
  bool automatic = true,
}) => jsonEncode({
  'version': 1,
  'automaticSignals': automatic,
  'enabledSignals': enabled,
  'pausedSignals': paused,
  'disabledSignals': disabled,
});

const opened = 'pulse.app_opened', backgrounded = 'pulse.app_backgrounded';

Harness launch({
  String? settings,
  FakeStorage? storage,
  PulseOptions options = const PulseOptions(debug: false),
  bool automatic = true,
  DateTime? at,
}) {
  final s = storage ?? FakeStorage();
  if (settings != null) s.files['config'] = utf8.encode(settings);
  return Harness(
    storage: s,
    time: FakeTime(at ?? DateTime.utc(2026, 11, 13, 12)),
    automatic: automatic,
    options: options,
  );
}

Iterable<Map<String, Object?>> ofType(Harness h, String type) =>
    h.allEvents.where((e) => e['type'] == type);

void main() {
  group('config keys', () {
    test('enabledSignals and pausedSignals parse defensively', () {
      final c = PulseConfig.parse(
        jsonEncode({
          'enabledSignals': [opened, 'bogus', 7, 'pulse.screen_view'],
          'pausedSignals': ['pulse.screen_view', 'bogus', null],
          'pauseExpensiveAt90': true,
        }),
      )!;
      expect(c.enabledSignals, {opened});
      expect(c.pausedSignals, {'pulse.screen_view'});
      final bad = PulseConfig.parse(
        '{"enabledSignals":{},"pausedSignals":"x"}',
      )!;
      expect(bad.enabledSignals, isEmpty);
      expect(bad.pausedSignals, isEmpty);
    });

    test('allows: opt-in types need enabledSignals, paused types are off', () {
      const none = PulseConfig();
      expect(none.allows(opened), false);
      expect(none.allows(backgrounded), true);
      expect(none.allows('pulse.deep_link'), true);
      expect(none.allows('pulse.permission_changed'), true);
      final on = PulseConfig.parse(config(enabled: [opened]))!;
      expect(on.allows(opened), true);
      expect(on.allows(backgrounded), true);
      final paused = PulseConfig.parse(
        config(enabled: [opened], paused: [opened, 'pulse.screen_view']),
      )!;
      expect(paused.allows(opened), false);
      expect(paused.allows('pulse.screen_view'), false);
      expect(paused.allows('my_event'), true);
      expect(paused.allows('pulse.error'), true);
    });

    test('the stored form keeps both new keys', () {
      final c = PulseConfig.parse(
        config(enabled: [backgrounded, opened], paused: ['pulse.deep_link']),
      )!;
      final again = PulseConfig.parse(utf8.decode(c.encode()))!;
      expect(again.enabledSignals, {opened});
      expect(again.pausedSignals, {'pulse.deep_link'});
    });
  });

  group('app opened and backgrounded', () {
    test('opened stays opt in and background never opens a session', () async {
      final h = launch();
      h.runtime.appForeground(cold: true);
      h.runtime.appBackground();
      await h.send('x');
      expect(ofType(h, opened), isEmpty);
      expect(ofType(h, backgrounded), isEmpty);
    });

    test('a failed read of the config means not sent', () async {
      final s = FakeStorage()..failing.add('config');
      final h = launch(storage: s);
      h.runtime.appForeground(cold: true);
      await h.flush();
      expect(ofType(h, opened), isEmpty);
    });

    test('sent once per transition, cold start only the first', () async {
      final h = launch(settings: config(enabled: [opened, backgrounded]));
      h.runtime.appForeground(cold: true);
      await h.advance(5);
      h.runtime.appBackground();
      await h.advance(60);
      h.runtime.appForeground(cold: false);
      await h.flush();
      expect(ofType(h, opened).map((e) => propsOf(e)['coldStart']), [
        'true',
        'false',
      ]);
      expect(
        ofType(h, backgrounded).map((e) => propsOf(e)['foregroundSeconds']),
        [5],
      );
    });

    test(
      'the opened signal starts the session after session_started',
      () async {
        final h = launch(settings: config(enabled: [opened]));
        h.runtime.appForeground(cold: true);
        await h.flush();
        expect(h.allEvents.map((e) => e['type']), [
          'pulse.new_install',
          'pulse.session_started',
          opened,
        ]);
      },
    );

    test(
      'portal pause, disabled type and automaticSignals=false stop them',
      () async {
        for (final settings in [
          config(enabled: [opened], paused: [opened]),
          config(enabled: [opened], disabled: [opened]),
          config(enabled: [opened], automatic: false),
        ]) {
          final h = launch(settings: settings);
          h.runtime.appForeground(cold: true);
          await h.flush();
          expect(ofType(h, opened), isEmpty, reason: settings);
        }
      },
    );

    test(
      'code automaticSignals=false and the harness switch stop them',
      () async {
        final off = launch(
          settings: config(enabled: [opened]),
          options: const PulseOptions(debug: false, automaticSignals: false),
        );
        off.runtime.appForeground(cold: true);
        await off.flush();
        expect(ofType(off, opened), isEmpty);
        final plain = launch(
          settings: config(enabled: [opened]),
          automatic: false,
        );
        plain.runtime.appForeground(cold: true);
        await plain.flush();
        expect(ofType(plain, opened), isEmpty);
      },
    );

    test('opt-out sends nothing and keeps no counters', () async {
      final h = launch(settings: config(enabled: [opened]));
      await h.runtime.setOptOut(true);
      h.runtime.appForeground(cold: true);
      await h.flush();
      expect(h.transport.requests, isEmpty);
      expect(h.storage.files.containsKey('usage'), false);
    });

    test('the debug flag rides on the signal', () async {
      final h = launch(
        settings: config(enabled: [opened]),
        options: const PulseOptions(debug: true),
      );
      h.runtime.appForeground(cold: true);
      await h.flush();
      expect(ofType(h, opened).single['debug'], true);
    });

    test('a background after 30 minutes of silence opens no session', () async {
      final h = launch(settings: config(enabled: [backgrounded]));
      h.runtime.appForeground(cold: true);
      await h.send('x');
      await h.advance(3600);
      h.runtime.appBackground();
      await h.flush();
      expect(ofType(h, backgrounded), isEmpty);
      expect(
        h.allEvents.where((e) => e['type'] == 'pulse.session_started'),
        hasLength(1),
      );
      // The counters still moved: the next signal carries the finished period.
      h.runtime.appForeground(cold: false);
      await h.send('later');
      final later = h.allEvents.last;
      expect(systemOf(later)['previousForegroundSeconds'], '3600');
      expect(systemOf(later)['foregroundsToday'], '2');
    });

    test('a background within the session is sent', () async {
      final h = launch(settings: config(enabled: [backgrounded]));
      h.runtime.appForeground(cold: true);
      await h.send('x');
      await h.advance(1700);
      h.runtime.appBackground();
      await h.flush();
      expect(
        propsOf(ofType(h, backgrounded).single)['foregroundSeconds'],
        1700,
      );
    });

    test('a second background without a foreground is ignored', () async {
      final h = launch(settings: config(enabled: [backgrounded]));
      h.runtime.appForeground(cold: true);
      await h.send('x');
      h.runtime.appBackground();
      h.runtime.appBackground();
      await h.flush();
      expect(ofType(h, backgrounded), hasLength(1));
    });
  });

  group('foreground counters', () {
    test('foregroundsToday counts per local day and rolls over', () async {
      final h = launch(at: DateTime.utc(2026, 11, 13, 23, 0));
      h.runtime.appForeground(cold: true);
      await h.send('a');
      h.runtime.appBackground();
      h.runtime.appForeground(cold: false);
      await h.send('b');
      expect(systemOf(h.allEvents.last)['foregroundsToday'], '2');
      h.runtime.appBackground();
      await h.advance(3 * 3600);
      h.runtime.appForeground(cold: false);
      await h.send('c');
      expect(systemOf(h.allEvents.last)['foregroundsToday'], '1');
    });

    test('previousForegroundSeconds survives a restart', () async {
      final s = FakeStorage();
      final first = launch(storage: s);
      first.runtime.appForeground(cold: true);
      await first.send('a');
      await first.advance(42);
      first.runtime.appBackground();
      await first.runtime.backgroundSave();
      final second = launch(storage: s, at: DateTime.utc(2026, 11, 13, 12, 10));
      second.runtime.appForeground(cold: true);
      await second.send('b');
      final sys = systemOf(second.allEvents.last);
      expect(sys['previousForegroundSeconds'], '42');
      expect(sys['foregroundsToday'], '2');
    });

    test('the usage group switch removes all three keys', () async {
      final h = launch(
        settings: jsonEncode({
          'groups': {'usage': false},
        }),
      );
      h.runtime.appForeground(cold: true);
      await h.send('a');
      final sys = systemOf(h.allEvents.last);
      for (final k in [
        'foregroundsToday',
        'previousForegroundSeconds',
        'launchMs',
      ]) {
        expect(sys.containsKey(k), false);
      }
    });
  });

  group('launchMs', () {
    test('only on the session_started of a cold start', () async {
      final h = launch();
      h.runtime.appForeground(cold: true);
      await h.advance(2);
      await h.send('a');
      await h.advance(3600);
      await h.send('b');
      final starts = ofType(h, 'pulse.session_started').toList();
      expect(starts, hasLength(2));
      expect(systemOf(starts[0]).containsKey('launchMs'), true);
      expect(systemOf(starts[1]).containsKey('launchMs'), false);
      expect(
        systemOf(
          h.allEvents.firstWhere((e) => e['type'] == 'a'),
        ).containsKey('launchMs'),
        false,
      );
    });

    test('measures to the first frame when it is known', () async {
      final h = launch();
      await h.settle();
      h.time.advance(1.5);
      h.runtime.firstFrameRendered();
      await h.advance(10);
      await h.send('a');
      final start = ofType(h, 'pulse.session_started').single;
      expect(systemOf(start)['launchMs'], '1500');
    });

    test('measures to the first signal when no frame is known', () async {
      final h = launch();
      await h.settle();
      await h.advance(4);
      await h.send('a');
      expect(
        systemOf(ofType(h, 'pulse.session_started').single)['launchMs'],
        '4000',
      );
    });

    test('an absurd value is left out', () async {
      final h = launch();
      await h.settle();
      await h.advance(2 * 3600);
      await h.send('a');
      expect(
        systemOf(
          ofType(h, 'pulse.session_started').single,
        ).containsKey('launchMs'),
        false,
      );
    });
  });

  group('deep links', () {
    test('sent with scheme, host, id-free path and utm tags only', () async {
      final h = launch();
      h.runtime.deepLink(
        Uri.parse(
          'myapp://shop.example/item/123/uuid/'
          '123e4567-e89b-12d3-a456-426614174000?utm_source=news&utm_medium='
          'email&utm_campaign=spring&token=SECRET&email=a%40b.co#frag',
        ),
      );
      await h.flush();
      final p = propsOf(ofType(h, 'pulse.deep_link').single);
      expect(p, {
        'scheme': 'myapp',
        'host': 'shop.example',
        'path': '/item/:id/uuid/:id',
        'utmSource': 'news',
        'utmMedium': 'email',
        'utmCampaign': 'spring',
      });
      expect(plain(h.transport.requests.first).contains('SECRET'), false);
    });

    test('automatic switches apply', () async {
      for (final settings in [
        config(paused: ['pulse.deep_link']),
        config(disabled: ['pulse.deep_link']),
        config(automatic: false),
      ]) {
        final h = launch(settings: settings);
        h.runtime.deepLink(Uri.parse('myapp://a/b'));
        await h.flush();
        expect(ofType(h, 'pulse.deep_link'), isEmpty, reason: settings);
      }
      final off = launch(
        options: const PulseOptions(debug: false, automaticSignals: false),
      );
      off.runtime.deepLink(Uri.parse('myapp://a/b'));
      await off.flush();
      expect(ofType(off, 'pulse.deep_link'), isEmpty);
    });

    test('an unusable link sends nothing', () async {
      final h = launch();
      h.runtime.deepLink(Uri.parse('/just/a/path'));
      await h.flush();
      expect(ofType(h, 'pulse.deep_link'), isEmpty);
    });
  });

  group('screen time', () {
    test('previousScreenSeconds excludes background time', () async {
      final h = launch();
      h.runtime.track('pulse.screen_view', props: {'screen': 'A'});
      await h.advance(10);
      h.runtime.appBackground();
      await h.advance(500);
      h.runtime.appForeground(cold: false);
      await h.advance(5);
      h.runtime.track(
        'pulse.screen_view',
        props: {'screen': 'B', 'previousScreen': 'A'},
      );
      await h.advance(7);
      h.runtime.track(
        'pulse.screen_view',
        props: {'screen': 'C', 'previousScreen': 'B'},
      );
      await h.flush();
      final views = ofType(h, 'pulse.screen_view').map(propsOf).toList();
      expect(views[0].containsKey('previousScreenSeconds'), false);
      expect(views[1]['previousScreenSeconds'], 15);
      expect(views[2]['previousScreenSeconds'], 7);
    });
  });

  group('quota guards', () {
    test('20 app_opened per session, the drop count is sent once', () async {
      final h = launch(
        settings: config(enabled: [opened], disabled: [backgrounded]),
      );
      for (var i = 0; i < 25; i++) {
        h.runtime.appBackground();
        h.runtime.appForeground(cold: false);
      }
      await h.send('mine');
      expect(ofType(h, opened), hasLength(20));
      final carried = h.allEvents
          .where((e) => systemOf(e).containsKey('droppedAutomatic'))
          .toList();
      expect(carried, hasLength(1));
      expect(systemOf(carried.single)['droppedAutomatic'], '5');
      await h.send('again');
      expect(systemOf(h.allEvents.last).containsKey('droppedAutomatic'), false);
    });

    test('caps per type: backgrounded 20, deep link 10', () async {
      final h = launch(settings: config(enabled: [backgrounded]));
      h.runtime.appForeground(cold: true);
      await h.send('x');
      for (var i = 0; i < 22; i++) {
        h.runtime.appBackground();
        h.runtime.appForeground(cold: false);
      }
      for (var i = 0; i < 12; i++) {
        h.runtime.deepLink(Uri.parse('myapp://a/$i'));
      }
      await h.flush();
      expect(ofType(h, backgrounded), hasLength(20));
      expect(ofType(h, 'pulse.deep_link'), hasLength(10));
    });

    test('permission_changed cap is 5 and screen_view cap is 100', () async {
      final h = launch();
      for (var i = 0; i < 105; i++) {
        h.runtime.track('pulse.screen_view', props: {'screen': 's$i'});
      }
      await h.flush();
      expect(ofType(h, 'pulse.screen_view'), hasLength(100));
      for (var i = 0; i < 7; i++) {
        h.runtime.track('pulse.permission_changed');
      }
      await h.flush();
      expect(ofType(h, 'pulse.permission_changed'), hasLength(5));
    });

    test('a new session starts new type counts', () async {
      final h = launch(settings: config(enabled: [opened]));
      for (var i = 0; i < 22; i++) {
        h.runtime.appBackground();
        h.runtime.appForeground(cold: false);
      }
      await h.flush();
      expect(ofType(h, opened), hasLength(20));
      await h.advance(3600);
      h.runtime.appBackground();
      h.runtime.appForeground(cold: false);
      await h.flush();
      expect(ofType(h, opened), hasLength(21));
    });

    test(
      '300 automatic signals per local day, then the day rolls over',
      () async {
        final h = launch(at: DateTime.utc(2026, 11, 13, 1));
        // Four sessions of 100 screen views each: only the daily cap bites.
        for (var session = 0; session < 4; session++) {
          for (var i = 0; i < 100; i++) {
            h.runtime.track('pulse.screen_view', props: {'screen': 's$i'});
          }
          await h.advance(1900);
        }
        await h.flush();
        int automatic() => h.allEvents
            .where((e) => (e['type']! as String).startsWith('pulse.'))
            .length;
        expect(automatic(), 300);
        h.runtime.track('my_event');
        await h.flush();
        expect(h.events, hasLength(1));
        await h.advance(24 * 3600);
        h.runtime.track('pulse.screen_view', props: {'screen': 'next'});
        await h.flush();
        // A new session after 24 hours: session_started and the screen view.
        expect(automatic(), 302);
        final carried = h.allEvents.where(
          (e) => systemOf(e).containsKey('droppedAutomatic'),
        );
        expect(carried, hasLength(1));
        expect(systemOf(carried.single)['droppedAutomatic'], isNotEmpty);
      },
    );

    test('manual signals and errors are never capped', () async {
      final h = launch();
      for (var i = 0; i < 400; i++) {
        h.runtime.track('my_event');
      }
      for (var i = 0; i < 12; i++) {
        h.runtime.trackError(StateError('x$i'), null, null, kind: 'handled');
      }
      await h.flush();
      expect(h.events.where((e) => e['type'] == 'my_event'), hasLength(400));
      expect(ofType(h, 'pulse.error'), hasLength(10));
      expect(
        h.allEvents.any((e) => systemOf(e).containsKey('droppedAutomatic')),
        false,
      );
    });
  });

  test('no permission keys are ever sent', () async {
    final h = launch(settings: config(enabled: [opened]));
    h.runtime.appForeground(cold: true);
    await h.send('x');
    for (final e in h.allEvents) {
      expect(systemOf(e).containsKey('notificationPermission'), false);
      expect(systemOf(e).containsKey('trackingPermission'), false);
    }
  });
}
