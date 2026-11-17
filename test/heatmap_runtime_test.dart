import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:mightys_pulse/src/core/config.dart';
import 'package:mightys_pulse/src/core/options.dart';
import 'package:mightys_pulse/src/core/ports.dart';
import 'support.dart';

const _on = '{"version":1,"heatmaps":true}';

class _Rig {
  _Rig({
    String? config = _on,
    PulseOptions options = const PulseOptions(debug: false),
    FakeStorage? storage,
  }) {
    final s = storage ?? FakeStorage();
    if (config != null) s.files['config'] = utf8.encode(config);
    h = Harness(storage: s, options: options, automatic: true);
  }
  late final Harness h;

  Future<void> ready() => h.settle();

  void screen(String name, {String? previous}) => h.runtime.track(
    'pulse.screen_view',
    props: {'screen': name, 'previousScreen': ?previous},
  );

  void tap(
    double x,
    double y, {
    double w = 400,
    double hgt = 800,
    bool keyboard = false,
    bool input = false,
    bool ignored = false,
  }) => h.runtime.heatmapTap(
    x,
    y,
    w,
    hgt,
    keyboardVisible: keyboard,
    inputTarget: input,
    ignored: ignored,
  );

  Future<List<Map<String, Object?>>> heatmaps() async {
    await h.flush();
    return h.allEvents.where((e) => e['type'] == 'pulse.heatmap').toList();
  }
}

void main() {
  group('config key', () {
    test('heatmaps is false unless the settings say true', () {
      expect(PulseConfig.defaults.heatmaps, false);
      expect(PulseConfig.parse('{"version":1}')!.heatmaps, false);
      expect(PulseConfig.parse('{"heatmaps":"yes"}')!.heatmaps, false);
      expect(PulseConfig.parse('{"heatmaps":1}')!.heatmaps, false);
      expect(PulseConfig.parse('{"heatmaps":true}')!.heatmaps, true);
    });
    test('it survives encode and decode', () {
      final c = PulseConfig.parse(
        '{"heatmaps":true,"disabledSignals":["pulse.heatmap"],"pausedSignals":["pulse.heatmap"]}',
      )!;
      final back = PulseConfig.parse(utf8.decode(c.encode()))!;
      expect(back.heatmaps, true);
      expect(back.disabledSignals, {'pulse.heatmap'});
      expect(back.pausedSignals, {'pulse.heatmap'});
    });
    test('allows follows the switch, disabled, paused and screen views', () {
      bool allows(String json) =>
          PulseConfig.parse(json)!.allows('pulse.heatmap');
      expect(allows('{}'), false);
      expect(allows('{"heatmaps":true}'), true);
      expect(
        allows('{"heatmaps":true,"disabledSignals":["pulse.heatmap"]}'),
        false,
      );
      expect(
        allows('{"heatmaps":true,"pausedSignals":["pulse.heatmap"]}'),
        false,
      );
      expect(allows('{"heatmaps":true,"automaticSignals":false}'), false);
      expect(allows('{"heatmaps":true,"screenViews":false}'), false);
      expect(
        allows('{"heatmaps":true,"disabledSignals":["pulse.screen_view"]}'),
        false,
      );
    });
  });

  group('capture', () {
    test('off by default: no cache means no heatmap', () async {
      final r = _Rig(config: null);
      await r.ready();
      r.screen('Shop');
      r.tap(10, 10);
      expect(await r.heatmaps(), isEmpty);
    });

    test('an unreadable cache is off', () async {
      final s = FakeStorage()..failing.add('config');
      final r = _Rig(config: null, storage: s);
      await r.ready();
      r.screen('Shop');
      r.tap(10, 10);
      expect(await r.heatmaps(), isEmpty);
    });

    test('on: one signal with the top-level heatmap object', () async {
      final r = _Rig();
      await r.ready();
      r.screen('Shop');
      r.tap(205.2, 340.04);
      r.tap(40, 1210.5);
      final sent = await r.heatmaps();
      expect(sent.length, 1);
      final s = sent.single;
      expect(s['heatmap'], {
        'screen': 'Shop',
        'bucket': 'phone',
        'orientation': 'portrait',
        'points': [
          {'x': 0.513, 'y': 340, 'kind': 'tap'},
          {'x': 0.1, 'y': 1210.5, 'kind': 'tap'},
        ],
      });
      expect(s['props'], isEmpty);
      expect((s['system']! as Map)['sdkName'], 'pulse-flutter');
      expect(s['sessionId'], isNotEmpty);
    });

    test('the code option switches it off and never on', () async {
      final r = _Rig(
        options: const PulseOptions(debug: false, captureHeatmaps: false),
      );
      await r.ready();
      r.screen('Shop');
      r.tap(10, 10);
      expect(await r.heatmaps(), isEmpty);
      final off = _Rig(config: null);
      await off.ready();
      off.screen('Shop');
      off.tap(10, 10);
      expect(await off.heatmaps(), isEmpty);
    });

    test('the automaticSignals option switches it off', () async {
      final r = _Rig(
        options: const PulseOptions(debug: false, automaticSignals: false),
      );
      await r.ready();
      r.screen('Shop');
      r.tap(10, 10);
      expect(await r.heatmaps(), isEmpty);
    });

    for (final json in [
      '{"heatmaps":true,"disabledSignals":["pulse.heatmap"]}',
      '{"heatmaps":true,"pausedSignals":["pulse.heatmap"]}',
      '{"heatmaps":true,"automaticSignals":false}',
      '{"heatmaps":true,"screenViews":false}',
    ]) {
      test('cached $json sends nothing', () async {
        final r = _Rig(config: json);
        await r.ready();
        r.screen('Shop');
        r.tap(10, 10);
        expect(await r.heatmaps(), isEmpty);
      });
    }

    test('no screen means no capture', () async {
      final r = _Rig();
      await r.ready();
      r.tap(10, 10);
      expect(await r.heatmaps(), isEmpty);
    });

    test('keyboard, inputs and ignored elements are never captured', () async {
      final r = _Rig();
      await r.ready();
      r.screen('Form');
      r.tap(10, 10, keyboard: true);
      r.tap(10, 10, input: true);
      r.tap(10, 10, ignored: true);
      expect(await r.heatmaps(), isEmpty);
    });

    test('a screen change sends the old buffer before the new view', () async {
      final r = _Rig();
      await r.ready();
      r.screen('A');
      r.tap(10, 10);
      r.screen('B', previous: 'A');
      await r.h.flush();
      final types = r.h.allEvents
          .map((e) => e['type'])
          .where((t) => t == 'pulse.heatmap' || t == 'pulse.screen_view')
          .toList();
      expect(types, [
        'pulse.screen_view',
        'pulse.heatmap',
        'pulse.screen_view',
      ]);
    });

    test('background and flush send the open buffer', () async {
      final r = _Rig();
      await r.ready();
      r.screen('A');
      r.tap(10, 10);
      r.h.runtime.appBackground();
      await r.h.settle();
      r.tap(20, 20);
      expect((await r.heatmaps()).length, 2);
    });

    test('opt-out drops the buffer and stops capture', () async {
      final r = _Rig();
      await r.ready();
      r.screen('A');
      r.tap(10, 10);
      await r.h.runtime.setOptOut(true);
      r.tap(20, 20);
      expect(await r.heatmaps(), isEmpty);
      expect(r.h.runtime.heatmapScreen, isNull);
    });
  });

  group('refresh in the run', () {
    test(
      'switched off by a refresh: capture stops and the buffer is dropped',
      () async {
        final r = _Rig();
        r.h.transport.configReply = const PulseResponse(
          200,
          body: '{"version":2,"heatmaps":false}',
        );
        r.screen('A');
        r.tap(10, 10);
        await r.ready();
        r.tap(20, 20);
        expect(await r.heatmaps(), isEmpty);
        expect(r.h.runtime.heatmapActive, false);
      },
    );

    test('switched on by a refresh: capture starts at once', () async {
      final r = _Rig(config: '{"version":1}');
      r.h.transport.configReply = const PulseResponse(
        200,
        body: '{"version":2,"heatmaps":true}',
      );
      await r.ready();
      r.screen('A');
      r.tap(10, 10);
      expect((await r.heatmaps()).length, 1);
    });

    test('a refresh does not change other settings of the run', () async {
      final r = _Rig(config: '{"version":1}');
      r.h.transport.configReply = const PulseResponse(
        200,
        body: '{"version":2,"screenViews":false,"heatmaps":true}',
      );
      await r.ready();
      expect(r.h.runtime.config.screenViews, true);
    });
  });

  group('quota and sessions', () {
    test('not counted by the daily cap and never droppedAutomatic', () async {
      final r = _Rig();
      await r.ready();
      r.screen('A');
      for (var i = 0; i < 320; i++) {
        r.h.time.date = r.h.time.date.add(const Duration(seconds: 3));
        r.tap(10, 10);
        r.h.runtime.appBackground();
      }
      final sent = await r.heatmaps();
      expect(sent.length, 320);
      for (final e in sent) {
        expect((e['system']! as Map).containsKey('droppedAutomatic'), false);
      }
    });

    test('a heatmap does not consume the dropped counter', () async {
      final r = _Rig();
      await r.ready();
      r.screen('A');
      await r.h.settle();
      for (var i = 0; i < 12; i++) {
        r.h.runtime.deepLink(Uri.parse('myapp://page/x$i'));
      }
      await r.h.settle();
      r.tap(10, 10);
      r.h.runtime.appBackground();
      await r.h.settle();
      r.h.runtime.track('custom');
      await r.h.flush();
      final heat = r.h.allEvents.firstWhere(
        (e) => e['type'] == 'pulse.heatmap',
      );
      expect((heat['system']! as Map).containsKey('droppedAutomatic'), false);
      final custom = r.h.allEvents.firstWhere((e) => e['type'] == 'custom');
      expect((custom['system']! as Map)['droppedAutomatic'], '2');
    });

    test(
      'a signal after 30 minutes starts a new session by the normal rule',
      () async {
        final r = _Rig();
        await r.ready();
        r.screen('A');
        await r.h.settle();
        r.tap(10, 10);
        r.h.runtime.appBackground();
        await r.h.settle();
        final first = (await r.heatmaps()).single['sessionId'];
        r.h.time.date = r.h.time.date.add(const Duration(minutes: 31));
        r.tap(10, 10);
        final all = await r.heatmaps();
        expect(all.length, 2);
        expect(all.last['sessionId'], isNot(first));
        expect(
          r.h.allEvents
              .where((e) => e['type'] == 'pulse.session_started')
              .length,
          2,
        );
      },
    );

    test('1000 points per session, later ones are dropped', () async {
      final r = _Rig();
      await r.ready();
      r.screen('A');
      for (var i = 0; i < 1100; i++) {
        r.h.time.date = r.h.time.date.add(const Duration(seconds: 2));
        r.tap(10, 10);
      }
      await r.h.settle();
      final sent = await r.heatmaps();
      final total = sent.fold<int>(
        0,
        (n, e) => n + (((e['heatmap']! as Map)['points']! as List).length),
      );
      expect(total, 1000);
      expect(
        sent.every(
          (e) => ((e['heatmap']! as Map)['points']! as List).length <= 200,
        ),
        true,
      );
    });
  });
}
