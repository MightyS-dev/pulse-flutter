import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mightys_pulse/mightys_pulse.dart';
import 'support_control.dart';
import 'support_control_ui.dart';

class _Counter extends StatefulWidget {
  const _Counter();
  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int taps = 0;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: TextButton(
        onPressed: () => setState(() => taps++),
        child: Text('taps $taps'),
      ),
    ),
  );
}

void main() {
  setUpAll(loadTestFonts);

  testWidgets('update required covers the app and blocks touches below', (
    tester,
  ) async {
    setScreen(tester, 393, 852);
    final control = await startControl(rigFor('updateRequired'));
    await tester.pumpWidget(controlApp(control, home: const _Counter()));
    await tester.pump();
    expect(find.text('Update required'), findsOneWidget);
    expect(find.text('Update'), findsOneWidget);
    expect(find.text('Not now'), findsNothing);
    await tester.tap(find.text('taps 0'), warnIfMissed: false);
    await tester.pump();
    final state = tester.state<_CounterState>(
      find.byType(_Counter, skipOffstage: false),
    );
    expect(state.taps, 0);
  });

  testWidgets('Update opens the store link through the app', (tester) async {
    setScreen(tester, 393, 852);
    final rig = rigFor('updateRequired');
    final opened = <Uri>[];
    final control = await startControl(rig);
    control.onOpenStore = opened.add;
    await tester.pumpWidget(controlApp(control));
    await tester.pump();
    await tester.tap(find.text('Update'));
    await tester.pump();
    expect(opened.single.toString(), 'https://pulse.mightys.dev/app');
  });

  testWidgets('without an opener there is no Update button and no lock', (
    tester,
  ) async {
    setScreen(tester, 393, 852);
    final control = await startControl(rigFor('updateRequired'), opener: false);
    await tester.pumpWidget(controlApp(control));
    await tester.pump();
    expect(find.text('Update available'), findsOneWidget);
    expect(find.text('Update'), findsNothing);
    expect(find.text('Not now'), findsOneWidget);
    await tester.tap(find.text('Not now'));
    await tester.pump();
    expect(find.text('Update available'), findsNothing);
  });

  testWidgets('the suggestion dialog: Update and Not now, Not now clears it', (
    tester,
  ) async {
    setScreen(tester, 393, 852);
    final control = await startControl(rigFor('updateSuggested'));
    await tester.pumpWidget(controlApp(control));
    await tester.pump();
    expect(find.text('Update available'), findsOneWidget);
    expect(find.text('Update'), findsOneWidget);
    await tester.tap(find.text('Not now'));
    await tester.pump();
    expect(find.text('Update available'), findsNothing);
    expect(find.text('Home screen'), findsOneWidget);
  });

  testWidgets('maintenance has Try again that asks the server', (tester) async {
    setScreen(tester, 393, 852);
    final rig = rigFor('maintenance');
    final control = await startControl(rig);
    await tester.pumpWidget(controlApp(control));
    await tester.pump();
    expect(find.text('Down for maintenance'), findsOneWidget);
    expect(find.textContaining('We will be back by'), findsOneWidget);
    expect(find.text('Continue'), findsNothing);
    final before = rig.requests;
    await tester.tap(find.text('Try again'));
    await tester.pump();
    await rig.settle();
    expect(rig.requests, before + 1);
  });

  testWidgets(
    'a blocked version without a store link says a fix is on the way',
    (tester) async {
      setScreen(tester, 393, 852);
      final control = await startControl(
        rigFor('versionBlocked'),
        opener: false,
      );
      await tester.pumpWidget(controlApp(control));
      await tester.pump();
      expect(find.text('Please update'), findsOneWidget);
      expect(find.textContaining('A fix is on the way'), findsOneWidget);
      expect(find.text('Update'), findsNothing);
    },
  );

  testWidgets('the upcoming bar lets touches through to the app', (
    tester,
  ) async {
    setScreen(tester, 393, 852);
    final control = await startControl(rigFor('maintenanceUpcoming'));
    await tester.pumpWidget(controlApp(control, home: const _Counter()));
    await tester.pump();
    expect(find.textContaining('Scheduled maintenance at'), findsOneWidget);
    await tester.tap(find.text('taps 0'));
    await tester.pump();
    expect(find.text('taps 1'), findsOneWidget);
    await tester.tap(find.textContaining('Scheduled maintenance at'));
    await tester.pump();
    expect(find.textContaining('Scheduled maintenance at'), findsNothing);
  });

  testWidgets('cards: announcement and what is new close with OK', (
    tester,
  ) async {
    setScreen(tester, 393, 852);
    for (final entry in {
      'announcement': 'Winter event',
      'whatsNew': "What's new in 1.0.0",
    }.entries) {
      final control = await startControl(rigFor(entry.key));
      await tester.pumpWidget(controlApp(control));
      await tester.pump();
      expect(find.text(entry.value), findsOneWidget, reason: entry.key);
      await tester.tap(find.text('OK'));
      await tester.pump();
      expect(find.text(entry.value), findsNothing, reason: entry.key);
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('a debug build shows the test bar and a Continue that leaves', (
    tester,
  ) async {
    setScreen(tester, 393, 852);
    final control = await startControl(rigFor('updateRequired'), debug: true);
    await tester.pumpWidget(controlApp(control));
    await tester.pump();
    expect(find.text('Test build: App Control preview'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pump();
    expect(find.text('Update required'), findsNothing);
    expect(find.text('Home screen'), findsOneWidget);
  });

  testWidgets('Back never closes the app from a screen', (tester) async {
    setScreen(tester, 393, 852);
    final calls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        calls.add(call.method);
        return null;
      },
    );
    final control = await startControl(rigFor('updateRequired'));
    await tester.pumpWidget(controlApp(control));
    await tester.pump();
    expect(await tester.binding.handlePopRoute(), isNot(isNull));
    await tester.pump();
    expect(calls, isNot(contains('SystemNavigator.pop')));
    expect(find.text('Update required'), findsOneWidget);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    );
  });

  testWidgets('the app below keeps its state when a screen comes and goes', (
    tester,
  ) async {
    setScreen(tester, 393, 852);
    final rig = rigFor('normal');
    final control = await startControl(rig);
    await tester.pumpWidget(controlApp(control, home: const _Counter()));
    await tester.tap(find.text('taps 0'));
    await tester.pump();
    rig.reply(rulesJson(version: 2, update: requiredUpdate('2.0.0')));
    control.checkNow();
    await rig.settle();
    await tester.pump();
    expect(find.text('Update required'), findsOneWidget);
    rig.reply(rulesJson(version: 3));
    await rig.advance(61);
    rig.client.onForeground();
    await rig.settle();
    await tester.pump();
    expect(find.text('Update required'), findsNothing);
    expect(find.text('taps 1'), findsOneWidget);
  });

  testWidgets('Material on Android, Cupertino on iOS', (tester) async {
    setScreen(tester, 393, 852);
    final control = await startControl(rigFor('updateRequired'));
    await tester.pumpWidget(controlApp(control));
    await tester.pump();
    expect(find.byType(FilledButton), findsOneWidget);
    expect(find.byType(CupertinoButton), findsNothing);
    await tester.pumpWidget(controlApp(control, platform: TargetPlatform.iOS));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoButton), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets(
    'the screen reader hears the title as a header and the buttons by name',
    (tester) async {
      setScreen(tester, 393, 852);
      final handle = tester.ensureSemantics();
      final control = await startControl(rigFor('updateRequired'));
      await tester.pumpWidget(controlApp(control));
      await tester.pump();
      final title = tester.getSemantics(find.text('Update required'));
      expect(title.flagsCollection.isHeader, true);
      expect(find.bySemanticsLabel('Update'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Home screen'),
        findsNothing,
        reason: 'the app below is hidden from the reader',
      );
      handle.dispose();
    },
  );

  testWidgets('the app language picks the text', (tester) async {
    setScreen(tester, 393, 852);
    final control = await startControl(rigFor('updateRequired'));
    await tester.pumpWidget(
      controlApp(
        control,
        locale: const Locale('de'),
        home: const Center(child: Text('x')),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Update erforderlich'), findsOneWidget);
  });

  testWidgets('the theme override colors the main button', (tester) async {
    setScreen(tester, 393, 852);
    final control = await startControl(rigFor('updateRequired'));
    control.theme = const PulseControlTheme(accentColor: Color(0xFFAA0000));
    await tester.pumpWidget(controlApp(control));
    await tester.pump();
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.style!.backgroundColor!.resolve({}), const Color(0xFFAA0000));
  });

  test('the code of App Control never closes the app', () {
    final hits = <String>[];
    for (final file in Directory(
      'lib',
    ).listSync(recursive: true).whereType<File>()) {
      final text = file.readAsStringSync();
      if (text.contains('SystemNavigator.pop') ||
          RegExp(r'\bexit\(').hasMatch(text)) {
        hits.add(file.path);
      }
    }
    expect(hits, isEmpty);
  });
}
