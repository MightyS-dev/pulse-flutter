import 'dart:convert';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mightys_pulse/mightys_pulse.dart';
import 'package:mightys_pulse/src/core/ports.dart';
import 'package:mightys_pulse/src/platform/heatmap_hook.dart';
import 'support.dart';

const _on = '{"version":1,"heatmaps":true}';

class _Rig {
  _Rig(WidgetTester t, {String? config = _on, bool debug = false})
    : tester = t,
      h = Harness(
        storage: FakeStorage(),
        automatic: true,
        debugBuild: () => debug,
      ) {
    if (config != null) h.storage.files['config'] = utf8.encode(config);
    t.view.physicalSize = const Size(1200, 2400);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    addTearDown(t.view.resetViewInsets);
    hook = HeatmapHook(h.runtime, debugBuild: () => debug)..install();
    addTearDown(hook.dispose);
  }
  final WidgetTester tester;
  final Harness h;
  late final HeatmapHook hook;

  Future<void> settle() async {
    for (var i = 0; i < 40; i++) {
      await tester.pump();
    }
  }

  Future<List<Map<String, Object?>>> points() async {
    h.runtime.flush();
    await settle();
    return h.allEvents
        .where((e) => e['type'] == 'pulse.heatmap')
        .expand(
          (e) => ((e['heatmap']! as Map)['points']! as List)
              .cast<Map<String, Object?>>(),
        )
        .toList();
  }

  Future<void> start(Widget body, {String screen = 'Home'}) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: body)));
    await settle();
    h.runtime.track('pulse.screen_view', props: {'screen': screen});
    await settle();
  }
}

Widget _area({void Function()? onTap}) => SizedBox.expand(
  child: GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: const ColoredBox(color: Colors.white),
  ),
);

void main() {
  testWidgets('a tap is captured in logical pixels and still reaches the app', (
    t,
  ) async {
    final r = _Rig(t);
    var taps = 0;
    await r.start(_area(onTap: () => taps++));
    await t.tapAt(const Offset(100, 200));
    await r.settle();
    expect(taps, 1);
    expect(await r.points(), [
      {'x': 0.25, 'y': 200, 'kind': 'tap'},
    ]);
  });

  testWidgets('the signal carries the bucket and orientation of the view', (
    t,
  ) async {
    final r = _Rig(t);
    await r.start(_area());
    await t.tapAt(const Offset(10, 10));
    r.h.runtime.flush();
    await r.settle();
    final heat = r.h.allEvents.firstWhere((e) => e['type'] == 'pulse.heatmap');
    expect((heat['heatmap']! as Map)['bucket'], 'phone');
    expect((heat['heatmap']! as Map)['orientation'], 'portrait');
    expect((heat['heatmap']! as Map)['screen'], 'Home');
  });

  testWidgets('a small wobble is still a tap, a drag is not', (t) async {
    final r = _Rig(t);
    await r.start(_area());
    final wobble = await t.startGesture(const Offset(100, 100));
    await wobble.moveBy(const Offset(5, 5));
    await wobble.up();
    final drag = await t.startGesture(const Offset(100, 300));
    await drag.moveBy(const Offset(0, kTouchSlop + 20));
    await drag.up();
    final away = await t.startGesture(const Offset(100, 500));
    await away.moveBy(const Offset(0, kTouchSlop + 20));
    await away.moveBy(const Offset(0, -(kTouchSlop + 20)));
    await away.up();
    final p = await r.points();
    expect(p.length, 1);
    expect(p.single['y'], 105);
  });

  testWidgets('a cancelled gesture is not a tap', (t) async {
    final r = _Rig(t);
    await r.start(_area());
    final g = await t.startGesture(const Offset(100, 100));
    await g.cancel();
    expect(await r.points(), isEmpty);
  });

  testWidgets('a second finger makes it a multi-touch gesture, not a tap', (
    t,
  ) async {
    final r = _Rig(t);
    await r.start(_area());
    final a = await t.startGesture(const Offset(100, 100));
    final b = await t.startGesture(const Offset(200, 100));
    await a.up();
    await b.up();
    expect(await r.points(), isEmpty);
    await t.tapAt(const Offset(50, 50));
    expect((await r.points()).length, 1);
  });

  testWidgets('only the primary mouse button counts', (t) async {
    final r = _Rig(t);
    await r.start(_area());
    final right = await t.startGesture(
      const Offset(100, 100),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await right.up();
    expect(await r.points(), isEmpty);
    final left = await t.startGesture(
      const Offset(100, 100),
      kind: PointerDeviceKind.mouse,
    );
    await left.up();
    expect((await r.points()).length, 1);
  });

  testWidgets('three quick taps in place: the third is rage', (t) async {
    final r = _Rig(t);
    await r.start(_area());
    for (var i = 0; i < 3; i++) {
      await t.tapAt(const Offset(100, 100));
    }
    expect((await r.points()).map((p) => p['kind']), ['tap', 'tap', 'rage']);
  });

  group('never captured', () {
    testWidgets('a tap on a text field', (t) async {
      final r = _Rig(t);
      await r.start(
        const Align(child: SizedBox(width: 300, child: TextField())),
      );
      await t.tap(find.byType(TextField));
      await r.settle();
      expect(await r.points(), isEmpty);
    });

    testWidgets('a tap on a password field', (t) async {
      final r = _Rig(t);
      await r.start(
        const Align(
          child: SizedBox(width: 300, child: TextField(obscureText: true)),
        ),
      );
      await t.tap(find.byType(TextField));
      await r.settle();
      expect(await r.points(), isEmpty);
    });

    testWidgets('a tap elsewhere while a field has the focus', (t) async {
      final r = _Rig(t);
      await r.start(
        Column(
          children: [
            const SizedBox(width: 300, child: TextField(autofocus: true)),
            Expanded(child: _area()),
          ],
        ),
      );
      await r.settle();
      await t.tapAt(const Offset(100, 700));
      expect(await r.points(), isEmpty);
    });

    testWidgets('while the keyboard is visible', (t) async {
      final r = _Rig(t);
      await r.start(_area());
      t.view.viewInsets = const FakeViewPadding(bottom: 900);
      await t.pump();
      await t.tapAt(const Offset(100, 100));
      expect(await r.points(), isEmpty);
      t.view.resetViewInsets();
      await t.pump();
      await t.tapAt(const Offset(100, 100));
      expect((await r.points()).length, 1);
    });

    testWidgets('inside PulseHeatmapIgnore, on a target or on plain content', (
      t,
    ) async {
      final r = _Rig(t);
      var inner = 0, behind = 0;
      await r.start(
        Stack(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => behind++,
              child: const SizedBox.expand(),
            ),
            Positioned(
              left: 0,
              top: 0,
              width: 200,
              height: 400,
              child: PulseHeatmapIgnore(
                child: Column(
                  children: [
                    SizedBox(
                      height: 100,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => inner++,
                      ),
                    ),
                    const Text('private'),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
      await t.tapAt(const Offset(50, 50));
      await t.tapAt(const Offset(50, 300));
      await r.settle();
      expect(inner, 1);
      expect(behind, 1);
      expect(await r.points(), isEmpty);
      await t.tapAt(const Offset(300, 300));
      expect((await r.points()).length, 1);
      expect(behind, 2);
    });

    testWidgets('the ignore marker never blocks a widget behind it', (t) async {
      final r = _Rig(t);
      var behind = 0;
      await r.start(
        Stack(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => behind++,
              child: const SizedBox.expand(),
            ),
            const Positioned(
              left: 0,
              top: 0,
              width: 100,
              height: 100,
              child: PulseHeatmapIgnore(child: SizedBox.expand()),
            ),
          ],
        ),
      );
      await t.tapAt(const Offset(10, 10));
      expect(behind, 1);
    });
  });

  group('switches', () {
    testWidgets('portal off: nothing captured, the app still works', (t) async {
      final r = _Rig(t, config: null);
      var taps = 0;
      await r.start(_area(onTap: () => taps++));
      await t.tapAt(const Offset(100, 100));
      expect(taps, 1);
      expect(await r.points(), isEmpty);
    });

    testWidgets('no screen: nothing captured', (t) async {
      final r = _Rig(t);
      await t.pumpWidget(MaterialApp(home: Scaffold(body: _area())));
      await r.settle();
      await t.tapAt(const Offset(100, 100));
      expect(await r.points(), isEmpty);
    });

    testWidgets('dispose removes the route', (t) async {
      final r = _Rig(t);
      final before =
          GestureBinding.instance.pointerRouter.debugGlobalRouteCount;
      await r.start(_area());
      r.hook.dispose();
      expect(
        GestureBinding.instance.pointerRouter.debugGlobalRouteCount,
        before - 1,
      );
      await t.tapAt(const Offset(100, 100));
      expect(await r.points(), isEmpty);
    });

    testWidgets('install twice adds one route', (t) async {
      final r = _Rig(t);
      final count = GestureBinding.instance.pointerRouter.debugGlobalRouteCount;
      r.hook.install();
      expect(
        GestureBinding.instance.pointerRouter.debugGlobalRouteCount,
        count,
      );
    });
  });

  group('debug screenshot', () {
    Future<bool> shoot(_Rig r) async {
      final result = await r.tester.runAsync(() => r.hook.shootNow());
      await r.settle();
      return result!;
    }

    // The hook plans a picture one second after a screen starts; the test
    // ends the plan so no timer is left pending.
    Future<void> end(_Rig r) async {
      r.hook.dispose();
      await r.settle();
    }

    testWidgets('a debug build uploads one PNG, then never again', (t) async {
      final r = _Rig(t, debug: true);
      r.h.transport.uploadReplies.add(const PulseResponse(201));
      await r.start(_area());
      expect(await shoot(r), isTrue);
      final u = r.h.transport.uploads.single;
      expect(u.contentType, 'image/png');
      expect(u.bytes.sublist(0, 4), [0x89, 0x50, 0x4e, 0x47]);
      expect(u.url.path, '/api/v1/heatmap/screenshot');
      expect(u.url.queryParameters['screen'], 'Home');
      expect(u.url.queryParameters['debug'], 'true');
      expect(await shoot(r), isFalse);
      expect(r.h.transport.uploads.length, 1);
      await end(r);
    });

    testWidgets('the picture is scaled to at most 2048 px on the long side', (
      t,
    ) async {
      final r = _Rig(t, debug: true);
      t.view.physicalSize = const Size(1200, 4800);
      r.h.transport.uploadReplies.add(const PulseResponse(201));
      await r.start(_area());
      expect(await shoot(r), isTrue);
      final bytes = r.h.transport.uploads.single.bytes;
      final data = ByteData.sublistView(Uint8List.fromList(bytes));
      expect(data.getUint32(16), lessThanOrEqualTo(2048));
      expect(data.getUint32(20), lessThanOrEqualTo(2048));
      expect(data.getUint32(20), greaterThan(2000));
      await end(r);
    });

    testWidgets('a release build never takes a picture', (t) async {
      final r = _Rig(t);
      await r.start(_area());
      expect(await shoot(r), isFalse);
      expect(r.h.transport.uploads, isEmpty);
    });

    testWidgets('never while the keyboard is visible', (t) async {
      final r = _Rig(t, debug: true);
      await r.start(_area());
      t.view.viewInsets = const FakeViewPadding(bottom: 900);
      expect(await shoot(r), isFalse);
      expect(r.h.transport.uploads, isEmpty);
      await end(r);
    });

    testWidgets('portal off: no picture', (t) async {
      final r = _Rig(t, debug: true, config: null);
      await r.start(_area());
      expect(await shoot(r), isFalse);
      await end(r);
    });

    testWidgets('a retry status is tried again on a later visit', (t) async {
      final r = _Rig(t, debug: true);
      r.h.transport.uploadReplies.add(
        const PulseResponse(503, retryAfter: '30'),
      );
      await r.start(_area());
      expect(await shoot(r), isFalse);
      r.h.time.advance(31);
      r.h.transport.uploadReplies.add(const PulseResponse(201));
      expect(await shoot(r), isTrue);
      expect(r.h.transport.uploads.length, 2);
      await end(r);
    });

    testWidgets('a screen change plans a picture after one second', (t) async {
      final r = _Rig(t, debug: true);
      r.h.transport.uploadReplies.add(const PulseResponse(201));
      await r.start(_area());
      await t.pump(const Duration(milliseconds: 900));
      expect(r.h.transport.uploads, isEmpty);
      r.h.runtime.track('pulse.screen_view', props: {'screen': 'Next'});
      await r.settle();
      await t.pump(const Duration(milliseconds: 999));
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await r.settle();
      expect(r.h.transport.uploads, isEmpty);
      await t.pump(const Duration(milliseconds: 2));
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 500)),
      );
      await r.settle();
      expect(
        r.h.transport.uploads.single.url.queryParameters['screen'],
        'Next',
      );
      await end(r);
    });
  });
}
