import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mightys_pulse/mightys_pulse.dart';
import 'package:mightys_pulse/src/core/control_client.dart';
import 'package:mightys_pulse/src/core/ports.dart';
import 'package:mightys_pulse/src/client.dart';
import 'package:mightys_pulse/src/platform/backend_native.dart';
import 'support.dart';
import 'support_control.dart';
import 'support_control_ui.dart';

void main() {
  test('the real backend hands its control client to Pulse.control', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final h = Harness(initialize: false);
    final backend = NativeBackend(() {}, h.runtime);
    expect(backend, isA<ControlBackend>());
    expect(backend.control, same(h.runtime.control));
    // The real facade path: PulseClient.initialize attaches what the backend offers.
    final client = PulseClient(() => backend);
    client.control.onOpenStore = (_) {};
    h.transport.controlReply = PulseResponse(
      200,
      body: rulesJson(update: requiredUpdate('9.0.0')),
    );
    unawaited(
      client.initialize(
        'synthetic-key',
        options: const PulseOptions(
          debug: false,
          appVersion: '1.0.0',
          captureHeatmaps: false,
        ),
      ),
    );
    await h.settle();
    final control = client.control;
    expect(control.state.kind, ControlKind.updateRequired);
  });

  test('options: automatic is the default and the three modes exist', () {
    expect(const PulseOptions().control, ControlMode.automatic);
    expect(
      const PulseOptions(control: ControlMode.off).normalized().control,
      ControlMode.off,
    );
    expect(ControlMode.values, [
      ControlMode.automatic,
      ControlMode.manual,
      ControlMode.off,
    ]);
  });

  test('Pulse.control exists before initialize and is normal', () {
    expect(Pulse.control.state, ControlState.normal);
    expect(Pulse.control.state.isActive, false);
    expect(Pulse.control.builder, isA<TransitionBuilder>());
    Pulse.control.checkNow();
    Pulse.control.dismiss();
    expect(Pulse.control.openStore(), false);
  });

  test('state and stream follow the client', () async {
    final rig = rigFor('updateRequired');
    final control = PulseControl()..onOpenStore = (_) {};
    final seen = <ControlKind>[];
    control.stream.listen((s) => seen.add(s.kind));
    control.attach(rig.client, ControlMode.automatic, debug: false);
    rig.start();
    await rig.settle();
    await Future<void>.delayed(Duration.zero);
    expect(control.state.kind, ControlKind.updateRequired);
    expect(seen, [ControlKind.updateRequired]);
    expect(control.mode, ControlMode.automatic);
  });

  test('openStore passes the link to the app and counts the press', () async {
    final rig = rigFor('updateRequired');
    final opened = <Uri>[];
    final control = await startControl(rig);
    control.onOpenStore = opened.add;
    expect(control.openStore(), true);
    expect(opened.single.toString(), 'https://pulse.mightys.dev/app');
    for (var i = 0; i < 2; i++) {
      await rig.advance(61);
      rig.client.onForeground();
      await rig.settle();
      control.openStore();
    }
    await rig.advance(61);
    rig.client.onForeground();
    await rig.settle();
    expect(
      control.state.kind,
      ControlKind.updateSuggested,
      reason: 'three returns on the same version',
    );
  });

  test(
    'without an opener openStore is false and a required update only suggests',
    () async {
      final rig = rigFor('updateRequired');
      final control = await startControl(rig, opener: false);
      expect(control.canOpenStore, false);
      expect(control.state.kind, ControlKind.updateSuggested);
      expect(control.openStore(), false);
      control.onOpenStore = (_) {};
      await rig.settle();
      expect(
        control.state.kind,
        ControlKind.updateRequired,
        reason: 'an opener set later locks as the rules say',
      );
    },
  );

  test('an opener that throws never reaches the app', () async {
    final rig = rigFor('updateRequired');
    final control = await startControl(rig);
    control.onOpenStore = (_) => throw StateError('no browser');
    expect(control.openStore(), false);
  });

  test('checkNow asks the server again, dismiss follows the state', () async {
    final rig = rigFor('updateSuggested');
    final control = await startControl(rig);
    expect(rig.requests, 1);
    control.checkNow();
    await rig.settle();
    expect(rig.requests, 2);
    control.dismiss();
    await rig.settle();
    expect(control.state.kind, ControlKind.normal);
  });

  test('off: no request, normal state, calls are harmless', () async {
    final rig = rigFor('updateRequired');
    final control = await startControl(rig, mode: ControlMode.off);
    control.checkNow();
    control.dismiss();
    await rig.settle();
    expect(rig.requests, 0);
    expect(control.state, ControlState.normal);
  });

  testWidgets('manual: state works, nothing is drawn', (tester) async {
    final rig = rigFor('updateRequired');
    final control = await startControl(rig, mode: ControlMode.manual);
    await tester.pumpWidget(controlApp(control));
    await tester.pump();
    expect(control.state.kind, ControlKind.updateRequired);
    expect(find.text('Home screen'), findsOneWidget);
    expect(find.text('Update required'), findsNothing);
  });

  testWidgets(
    'automatic without the builder line: one hint, never an exception',
    (tester) async {
      final lines = <String>[];
      final saved = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) =>
          lines.add(message ?? '');
      final rig = rigFor('updateRequired');
      final control = PulseControl()..onOpenStore = (_) {};
      control.attach(rig.client, ControlMode.automatic, debug: true);
      rig.start();
      await tester.pumpWidget(
        MaterialApp(home: const Scaffold(body: Text('plain'))),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(
        lines.where((l) => l.contains('add builder: Pulse.control.builder')),
        hasLength(1),
      );
      expect(tester.takeException(), isNull);
      expect(control.state.kind, ControlKind.updateRequired);
      debugPrint = saved;
    },
  );

  testWidgets('with the builder line no hint is printed', (tester) async {
    final lines = <String>[];
    final saved = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) =>
        lines.add(message ?? '');
    final rig = rigFor('normal');
    final control = PulseControl();
    control.attach(rig.client, ControlMode.automatic, debug: true);
    rig.start();
    await tester.pumpWidget(controlApp(control));
    await tester.pump();
    await tester.pump();
    expect(lines.where((l) => l.contains('add builder')), isEmpty);
    debugPrint = saved;
  });
}
