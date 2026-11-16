import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mightys_pulse/mightys_pulse.dart';
import 'package:mightys_pulse/src/client.dart';
import 'package:mightys_pulse/src/core/config.dart';
import 'package:mightys_pulse/src/core/ports.dart';
import 'support.dart';

Map<String, Object?> systemOf(Map<String, Object?> e) =>
    e['system']! as Map<String, Object?>;

String body({
  int version = 3,
  Object? screenViews = true,
  Object? automaticSignals = true,
  Map<String, Object?> groups = const {},
  List<Object?> disabled = const [],
}) => jsonEncode({
  'version': version,
  'screenViews': screenViews,
  'automaticSignals': automaticSignals,
  'groups': {for (final n in fieldGroups.keys) n: true, ...groups},
  'disabledSignals': disabled,
});

void seed(FakeStorage s, String text) => s.files['config'] = utf8.encode(text);

final _liveKeys = {
  for (final e in fieldGroups.entries)
    if (e.key != 'usage') ...e.value,
};

/// One app launch on [storage] with the portal answering [reply].
Future<Harness> launch(
  FakeStorage storage, {
  PulseResponse? reply,
  Future<PulseResponse> Function()? handler,
  PulseOptions options = const PulseOptions(debug: false),
  bool withLive = false,
}) async {
  final h = Harness(
    storage: storage,
    automatic: true,
    initialize: false,
    options: options,
    live: withLive ? FakeLive({for (final k in _liveKeys) k: 'x'}) : null,
  );
  h.transport.configReply = reply;
  h.transport.configHandler = handler;
  unawaited(h.runtime.initialize('synthetic-key', options: options));
  await h.settle();
  return h;
}

Iterable<String> types(Harness h) =>
    h.allEvents.map((e) => e['type']! as String);

void main() {
  group('parsing', () {
    test('missing keys, wrong types and unknown names mean on', () {
      final c = PulseConfig.parse(
        jsonEncode({
          'version': 'x',
          'screenViews': 'no',
          'automaticSignals': 0,
          'groups': {'device': null, 'screen': 'false', 'extra': false},
          'disabledSignals': ['pulse.app_updated', 'bogus', 7, null],
          'future': 1,
        }),
      )!;
      expect(c.version, 0);
      expect(c.screenViews, true);
      expect(c.automaticSignals, true);
      expect(c.groups.values.every((v) => v), true);
      expect(c.disabledSignals, {'pulse.app_updated'});
      final empty = PulseConfig.parse('{}')!;
      expect(empty.allows('pulse.screen_view'), true);
      expect(empty.filterSystem({'timeZone': 'x'}), {'timeZone': 'x'});
    });

    test('bad bodies never throw and give null', () {
      for (final text in ['', 'nope', '[]', '3', 'null', '{"groups":']) {
        expect(PulseConfig.parse(text), isNull, reason: text);
      }
      expect(
        PulseConfig.parse('{"groups":[1],"disabledSignals":{}}'),
        isNotNull,
      );
    });

    test('encode round trips', () {
      final c = PulseConfig.parse(
        body(version: 9, screenViews: false, groups: {'app': false}),
      )!;
      final back = PulseConfig.parse(utf8.decode(c.encode()))!;
      expect(back.version, 9);
      expect(back.screenViews, false);
      expect(back.groups['app'], false);
      expect(back.groups['device'], true);
    });

    test('the group mapping holds 46 keys, each in one group', () {
      final all = fieldGroups.values.expand((e) => e).toList();
      expect(all.length, 46);
      expect(all.toSet().length, 46);
      expect(all.contains('bundleId'), false);
    });
  });

  group('fetch', () {
    test('once per launch; first has no etag; 200 is stored', () async {
      final s = FakeStorage();
      final h = await launch(s, reply: PulseResponse(200, body: body()));
      expect(h.transport.configRequests.length, 1);
      final r = h.transport.configRequests.single;
      expect(r.etag, isNull);
      expect(r.key, 'synthetic-key');
      expect(r.url.toString(), 'https://in.mightys.dev/api/v1/config');
      await h.send('a');
      await h.send('b');
      expect(h.transport.configRequests.length, 1);
      expect(PulseConfig.parse(utf8.decode(s.files['config']!))!.version, 3);
    });

    test('the cached version is sent as If-None-Match; 304 keeps it', () async {
      final s = FakeStorage();
      seed(s, body(version: 3, disabled: ['pulse.new_install']));
      final h = await launch(s, reply: const PulseResponse(304));
      expect(h.transport.configRequests.single.etag, '"3"');
      expect(
        PulseConfig.parse(utf8.decode(s.files['config']!))!.disabledSignals,
        {'pulse.new_install'},
      );
      expect(types(h), isNot(contains('pulse.new_install')));
    });

    test('a new version replaces the cache', () async {
      final s = FakeStorage();
      seed(s, body(version: 3));
      await launch(s, reply: PulseResponse(200, body: body(version: 4)));
      expect(PulseConfig.parse(utf8.decode(s.files['config']!))!.version, 4);
    });

    test(
      'failures keep the cache and leave no file when there is none',
      () async {
        for (final reply in [
          const PulseResponse(401),
          const PulseResponse(500),
          const PulseResponse(0),
          const PulseResponse(200, body: 'garbage'),
          const PulseResponse(404),
        ]) {
          final s = FakeStorage();
          seed(s, body(version: 5, screenViews: false));
          final h = await launch(s, reply: reply);
          expect(
            PulseConfig.parse(utf8.decode(s.files['config']!))!.version,
            5,
          );
          expect(h.runtime.config.screenViews, false);
          final empty = FakeStorage();
          await launch(empty, reply: reply);
          expect(empty.files.containsKey('config'), false);
        }
      },
    );

    test('a throwing transport and unreadable cache fail safely', () async {
      final s = FakeStorage()..failing.add('config');
      final h = await launch(s, handler: () async => throw StateError('x'));
      expect(h.runtime.config.allows('pulse.screen_view'), true);
      await h.send('a');
      expect(h.events.length, 1);
    });

    test('applied from the next launch only', () async {
      final s = FakeStorage();
      final first = await launch(
        s,
        reply: PulseResponse(200, body: body(automaticSignals: false)),
      );
      await first.send('a');
      expect(types(first), contains('pulse.session_started'));
      final second = await launch(s, reply: const PulseResponse(304));
      await second.send('a');
      expect(types(second), ['a']);
    });

    test('no cache means everything on', () async {
      final h = await launch(FakeStorage());
      await h.send('a');
      expect(types(h), ['pulse.new_install', 'pulse.session_started', 'a']);
    });

    test('a hung config request never delays track or flush', () async {
      final never = Completer<PulseResponse>();
      final h = await launch(FakeStorage(), handler: () => never.future);
      await h.send('a');
      expect(h.events.length, 1);
      await h.flush();
    });
  });

  group('effects', () {
    test('automaticSignals false drops the three automatic signals', () async {
      final s = FakeStorage();
      seed(s, body(automaticSignals: false));
      final h = await launch(s);
      await h.send('a');
      expect(types(h), ['a']);
    });

    test('one disabled type drops only that type', () async {
      final s = FakeStorage();
      seed(s, body(disabled: ['pulse.session_started']));
      final h = await launch(s);
      await h.send('a');
      expect(types(h), ['pulse.new_install', 'a']);
    });

    test('each group off removes exactly its keys', () async {
      final base = await launch(FakeStorage(), withLive: true);
      await base.send('a');
      final baseline = systemOf(base.events.single).keys.toSet();
      expect(baseline, containsAll(_liveKeys));
      for (final name in fieldGroups.keys) {
        final s = FakeStorage();
        seed(s, body(groups: {name: false}));
        final h = await launch(s, withLive: true);
        await h.send('a');
        final keys = systemOf(h.events.single).keys.toSet();
        final owned = fieldGroups[name]!.toSet();
        expect(keys, baseline.difference(owned), reason: name);
        expect(baseline.intersection(owned), isNotEmpty, reason: name);
        for (final k in [
          'platform',
          'osName',
          'osVersion',
          'appVersion',
          'appBuildNumber',
          'deviceModel',
          'locale',
          'bundleId',
          'sdkName',
          'sdkVersion',
        ]) {
          expect(keys, contains(k), reason: '$name keeps $k');
        }
      }
    });

    test('opt-out deletes the config file', () async {
      final s = FakeStorage();
      final h = await launch(s, reply: PulseResponse(200, body: body()));
      expect(s.files.containsKey('config'), true);
      await h.runtime.setOptOut(true);
      await h.settle();
      expect(s.files.containsKey('config'), false);
    });

    test('opted out at launch: no request and no file', () async {
      final s = FakeStorage();
      final first = await launch(s);
      await first.runtime.setOptOut(true);
      await first.settle();
      final h = await launch(s, reply: PulseResponse(200, body: body()));
      expect(h.transport.configRequests, isEmpty);
      expect(s.files.containsKey('config'), false);
    });
  });

  group('precedence', () {
    test(
      'code automaticSignals false switches off with the portal on',
      () async {
        final h = await launch(
          FakeStorage(),
          options: const PulseOptions(debug: false, automaticSignals: false),
        );
        await h.send('a');
        expect(types(h), ['a']);
      },
    );

    test('code true cannot force on what the portal switched off', () async {
      final s = FakeStorage();
      seed(s, body(automaticSignals: false));
      final h = await launch(
        s,
        options: const PulseOptions(debug: false, automaticSignals: true),
      );
      await h.send('a');
      expect(types(h), ['a']);
    });
  });

  group('screen views', () {
    Future<(PulseClient, PulseNavigatorObserver, Harness)> setup(
      String? cached, {
      PulseOptions options = const PulseOptions(debug: false),
    }) async {
      final s = FakeStorage();
      if (cached != null) seed(s, cached);
      final h = await launch(s, options: options);
      final client = PulseClient(() => h.runtime);
      await client.initialize('synthetic-key', options: options);
      return (client, PulseNavigatorObserver(client.screens), h);
    }

    Future<List<Object?>> sent(Harness h) async {
      await h.flush();
      return h.allEvents
          .where((e) => e['type'] == 'pulse.screen_view')
          .map((e) => (e['props']! as Map)['screen'])
          .toList();
    }

    Route<void> page(String name) => MaterialPageRoute<void>(
      settings: RouteSettings(name: name),
      builder: (_) => const SizedBox(),
    );

    test('portal on, code default: observer and manual both send', () async {
      final (c, o, h) = await setup(body());
      o.didPush(page('a'), null);
      c.screen('Manual');
      expect(await sent(h), ['a', 'Manual']);
    });

    test('screenViews false: observer and manual send nothing', () async {
      final (c, o, h) = await setup(body(screenViews: false));
      o.didPush(page('a'), null);
      c.screen('Manual');
      expect(await sent(h), isEmpty);
    });

    test('automaticSignals false also stops screen views', () async {
      final (c, o, h) = await setup(body(automaticSignals: false));
      o.didPush(page('a'), null);
      c.screen('Manual');
      expect(await sent(h), isEmpty);
    });

    test('disabled screen_view stops both; another type does not', () async {
      final (c, o, h) = await setup(body(disabled: ['pulse.screen_view']));
      o.didPush(page('a'), null);
      c.screen('Manual');
      expect(await sent(h), isEmpty);
      final (c2, o2, h2) = await setup(body(disabled: ['pulse.app_updated']));
      o2.didPush(page('a'), null);
      expect(await sent(h2), ['a']);
      c2.screen('b');
    });

    test('code automaticScreenViews false: observer off, manual on', () async {
      final (c, o, h) = await setup(
        body(),
        options: const PulseOptions(debug: false, automaticScreenViews: false),
      );
      o.didPush(page('a'), null);
      c.screen('Manual');
      expect(await sent(h), ['Manual']);
    });

    test('code automaticScreenViews false and portal off: nothing', () async {
      final (c, o, h) = await setup(
        body(screenViews: false),
        options: const PulseOptions(debug: false, automaticScreenViews: false),
      );
      o.didPush(page('a'), null);
      c.screen('Manual');
      expect(await sent(h), isEmpty);
    });

    test(
      'a screen sent before initialize is dropped when the portal says so',
      () async {
        final s = FakeStorage();
        seed(s, body(screenViews: false));
        final h = Harness(storage: s, initialize: false);
        h.runtime.track('pulse.screen_view', props: {'screen': 'early'});
        unawaited(h.runtime.initialize('synthetic-key'));
        await h.settle();
        await h.flush();
        expect(types(h), isNot(contains('pulse.screen_view')));
      },
    );
  });
}
