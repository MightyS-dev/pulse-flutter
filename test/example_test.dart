import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// The public example is exercised from the package's own test suite.
// ignore: avoid_relative_lib_imports
import '../example/lib/main.dart';

void main() {
  testWidgets('buttons call track, setUser and flush; the switch opts out', (
    tester,
  ) async {
    final tracked = <String>[];
    final users = <String?>[];
    var flushed = 0;
    var optedOut = false;
    final actions = PulseActions(
      track: (type, {value, props}) => tracked.add(type),
      setUser: users.add,
      flush: () async => flushed++,
      setOptOut: (value) async => optedOut = value,
      getOptOut: () => optedOut,
    );
    await tester.pumpWidget(ExampleApp(actions: actions));
    await tester.tap(find.text('Track signal'));
    await tester.tap(find.text('Set user'));
    await tester.pump();
    expect(find.text('Clear user'), findsOneWidget);
    await tester.tap(find.text('Clear user'));
    await tester.tap(find.text('Flush'));
    await tester.pumpAndSettle();
    expect(tracked, ['button.tap']);
    expect(users, ['demo-user-1', null]);
    expect(flushed, 1);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(optedOut, isTrue);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Track signal'),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('without a key the controls stay disabled', (tester) async {
    await tester.pumpWidget(
      ExampleApp(actions: const PulseActions(), configured: false),
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Track signal'),
          )
          .onPressed,
      isNull,
    );
    expect(find.textContaining('PULSE_APP_KEY'), findsOneWidget);
  });

  for (final size in [const Size(320, 568), const Size(820, 1180)]) {
    testWidgets('fits $size at 1.3 text scale', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
          child: ExampleApp(actions: const PulseActions()),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Track signal').hitTestable(), findsOneWidget);
    });
  }
}
