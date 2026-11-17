import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mightys_pulse/src/platform/heatmap_hook.dart';
import 'package:mightys_pulse/src/sdk_ui.dart';
import 'support.dart';
import 'support_control_ui.dart';

/// App Control screens are SDK UI: never a heatmap point, never a screenshot.
void main() {
  setUpAll(loadTestFonts);

  Future<(Harness, HeatmapHook)> heatmapOn(WidgetTester t) async {
    final h = Harness(
      storage: FakeStorage(),
      automatic: true,
      debugBuild: () => false,
    );
    h.storage.files['config'] = utf8.encode('{"version":1,"heatmaps":true}');
    final hook = HeatmapHook(h.runtime, debugBuild: () => false)..install();
    addTearDown(hook.dispose);
    return (h, hook);
  }

  Future<List<Object?>> points(WidgetTester t, Harness h) async {
    h.runtime.flush();
    for (var i = 0; i < 40; i++) {
      await t.pump();
    }
    return h.allEvents
        .where((e) => e['type'] == 'pulse.heatmap')
        .expand((e) => (e['heatmap']! as Map)['points']! as List)
        .toList();
  }

  Future<void> mount(WidgetTester t, Harness h, String kind) async {
    setScreen(t, 393, 852);
    final control = await startControl(rigFor(kind));
    await t.pumpWidget(
      controlApp(
        control,
        home: const Scaffold(
          body: SizedBox.expand(child: ColoredBox(color: Colors.white)),
        ),
      ),
    );
    for (var i = 0; i < 40; i++) {
      await t.pump();
    }
    h.runtime.track('pulse.screen_view', props: {'screen': 'Home'});
    for (var i = 0; i < 40; i++) {
      await t.pump();
    }
  }

  testWidgets('a tap on a blocking screen is not a heatmap point', (t) async {
    final (h, _) = await heatmapOn(t);
    await mount(t, h, 'updateRequired');
    expect(PulseSdkUi.visible, isTrue);
    await t.tapAt(const Offset(200, 20));
    await t.tap(find.text('Update'), warnIfMissed: false);
    expect(await points(t, h), isEmpty);
  });

  testWidgets('a tap on the suggested update dialog is not a point', (t) async {
    final (h, _) = await heatmapOn(t);
    await mount(t, h, 'updateSuggested');
    await t.tap(find.text('Not now'), warnIfMissed: false);
    expect(await points(t, h), isEmpty);
  });

  testWidgets('the heads-up bar is ignored but the app below it is not', (
    t,
  ) async {
    final (h, _) = await heatmapOn(t);
    await mount(t, h, 'maintenanceUpcoming');
    await t.tapAt(const Offset(100, 20));
    expect(await points(t, h), isEmpty, reason: 'a tap on the bar');
    await t.tapAt(const Offset(100, 500));
    expect(await points(t, h), hasLength(1), reason: 'a tap on the app');
  });

  testWidgets('no picture is taken while an App Control screen is up', (
    t,
  ) async {
    final (h, hook) = await heatmapOn(t);
    await mount(t, h, 'maintenance');
    expect(await hook.shootNow('Home'), isFalse);
  });
}
