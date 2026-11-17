import 'dart:async';
import 'dart:ui';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mightys_pulse/src/platform/display_state.dart';
import 'package:mightys_pulse/src/platform/host.dart';
import 'package:mightys_pulse/src/platform/network_power.dart';
import 'support.dart';

Map<String, Object?> systemOf(Map<String, Object?> event) =>
    event['system']! as Map<String, Object?>;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('display state', () {
    testWidgets('screen, language and settings on Android', (wt) async {
      wt.view.physicalSize = const Size(1080, 2400);
      wt.view.devicePixelRatio = 2.625;
      final dispatcher = wt.platformDispatcher;
      dispatcher.platformBrightnessTestValue = Brightness.dark;
      dispatcher.textScaleFactorTestValue = 1.15;
      dispatcher.localesTestValue = const [Locale('de', 'DE'), Locale('en')];
      dispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(
            disableAnimations: true,
            boldText: true,
            invertColors: false,
            highContrast: true,
          );
      addTearDown(() {
        wt.view.reset();
        dispatcher.clearAllTestValues();
      });
      final state = readDisplayState(dispatcher, HostOs.android);
      expect(state['colorScheme'], 'dark');
      expect(state['fontScale'], '1.15');
      expect(state['language'], 'de');
      expect(state['preferredLanguage'], 'de');
      expect(state['region'], 'DE');
      expect(state['layoutDirection'], 'ltr');
      expect(state['reduceMotion'], 'true');
      expect(state['boldText'], 'true');
      expect(state['invertColors'], 'false');
      expect(state['increaseContrast'], 'true');
      expect(state.containsKey('contentSizeCategory'), false);
      expect(state.containsKey('reduceTransparency'), false);
      expect(state.containsKey('differentiateWithoutColor'), false);
      expect(state['screenCount'], isNotEmpty);
      expect(state['screenScale'], matches(RegExp(r'^\d+(\.\d{1,3})?$')));
      expect(state['orientation'], anyOf('portrait', 'landscape', 'square'));
      expect(state['screenDpi'], matches(RegExp(r'^\d+$')));
      final width = double.parse(state['screenWidth']!);
      final px = int.parse(state['screenWidthPx']!);
      expect((width * double.parse(state['screenScale']!)).round(), px);
    });
    testWidgets('iOS adds the size category, desktop has no orientation', (
      wt,
    ) async {
      final dispatcher = wt.platformDispatcher;
      dispatcher.textScaleFactorTestValue = 1.24;
      dispatcher.localesTestValue = const [Locale('ar', 'EG')];
      addTearDown(dispatcher.clearAllTestValues);
      final ios = readDisplayState(dispatcher, HostOs.ios);
      expect(ios['contentSizeCategory'], 'XXL');
      expect(ios['layoutDirection'], 'rtl');
      expect(ios.containsKey('screenDpi'), false);
      final desktop = readDisplayState(dispatcher, HostOs.macos);
      expect(desktop.containsKey('orientation'), false);
      expect(desktop.containsKey('contentSizeCategory'), false);
    });
    test('content size category is the nearest Apple category', () {
      expect(contentSizeCategoryFor(1.0), 'L');
      expect(contentSizeCategoryFor(0.82), 'XS');
      expect(contentSizeCategoryFor(1.34), 'XXXL');
      expect(contentSizeCategoryFor(2.8), 'AccessibilityXXL');
      expect(contentSizeCategoryFor(9), 'AccessibilityXXXL');
    });
    test('numbers keep at most three decimals and no exponent', () {
      expect(shortNumber(393), '393');
      expect(shortNumber(411.42857), '411.429');
      expect(shortNumber(2.5), '2.5');
      expect(shortNumber(double.nan), '');
    });
  });

  group('connection and battery saver', () {
    test('plugin answers of both shapes are understood', () {
      expect(connectionResults(ConnectivityResult.wifi), [
        ConnectivityResult.wifi,
      ]);
      expect(connectionResults([ConnectivityResult.mobile]), [
        ConnectivityResult.mobile,
      ]);
      expect(connectionResults(null), isEmpty);
    });

    test('connection type is chosen by one fixed order', () {
      String? type(List<ConnectivityResult> r) => connectionTypeOf(r);
      expect(
        type([ConnectivityResult.wifi, ConnectivityResult.mobile]),
        'wifi',
      );
      expect(type([ConnectivityResult.mobile]), 'cellular');
      expect(type([ConnectivityResult.ethernet]), 'ethernet');
      expect(type([ConnectivityResult.none]), 'none');
      expect(type([ConnectivityResult.vpn]), 'other');
      expect(type([ConnectivityResult.bluetooth]), 'other');
      expect(type([]), isNull);
    });
    test('cache follows changes and refreshes the battery saver', () async {
      final changes = StreamController<List<ConnectivityResult>>.broadcast();
      var saver = false;
      var now = DateTime.utc(2026, 11, 15);
      final cache = NetworkPower(
        connectivity: () async => [ConnectivityResult.wifi],
        changes: () => changes.stream,
        powerSave: () async => saver,
        now: () => now,
      );
      expect(cache.read(), isEmpty);
      await cache.warmUp();
      expect(cache.read(), {'connectionType': 'wifi', 'lowPowerMode': 'false'});
      changes.add([ConnectivityResult.mobile]);
      await Future<void>.delayed(Duration.zero);
      expect(cache.read()['connectionType'], 'cellular');
      saver = true;
      now = now.add(const Duration(seconds: 61));
      cache.read();
      await Future<void>.delayed(Duration.zero);
      expect(cache.read()['lowPowerMode'], 'true');
      cache.dispose();
      await changes.close();
    });
    test('failing plugins leave the keys out and never throw', () async {
      final cache = NetworkPower(
        connectivity: () async => throw StateError('no'),
        changes: () => throw StateError('no'),
        powerSave: () async => throw UnsupportedError('no'),
      );
      await cache.warmUp();
      expect(cache.read(), isEmpty);
      cache.dispose();
    });
  });

  group('dynamic values in signals', () {
    test(
      'orientation, colour scheme, font scale and flags change between two signals',
      () async {
        final live = FakeLive({
          'orientation': 'portrait',
          'colorScheme': 'light',
          'fontScale': '1',
          'reduceMotion': 'false',
          'connectionType': 'wifi',
          'lowPowerMode': 'false',
        });
        final h = Harness(live: live);
        await h.send('a');
        live.values = {
          'orientation': 'landscape',
          'colorScheme': 'dark',
          'fontScale': '1.3',
          'reduceMotion': 'true',
          'connectionType': 'cellular',
          'lowPowerMode': 'true',
        };
        await h.send('b');
        final first = systemOf(h.events[0]);
        final second = systemOf(h.events[1]);
        for (final key in live.values.keys) {
          expect(first[key], isNot(second[key]), reason: key);
        }
        expect(second['orientation'], 'landscape');
        expect(second['connectionType'], 'cellular');
      },
    );
    test('the UTC offset follows the local time rule', () async {
      final h = Harness();
      await h.send('a');
      expect(systemOf(h.events.single)['utcOffsetMinutes'], '0');
    });
    test('session seconds grow with the session', () async {
      final h = Harness();
      await h.send('a');
      await h.advance(95);
      await h.send('b');
      expect(systemOf(h.events[0])['sessionSeconds'], '0');
      expect(systemOf(h.events[1])['sessionSeconds'], '95');
    });
    test(
      'first signals carry the full set including cached live values',
      () async {
        final gate = Completer<void>();
        final live = FakeLive({
          'connectionType': 'wifi',
          'colorScheme': 'dark',
        });
        final h = Harness(
          environment: FakeEnvironment(gate: gate.future),
          live: live,
        );
        h.runtime.track('early');
        unawaited(h.runtime.flush());
        for (var i = 0; i < 60; i++) {
          await Future<void>.value();
        }
        expect(h.transport.requests, isEmpty);
        gate.complete();
        await h.settle();
        final system = systemOf(h.events.single);
        expect(live.warmUps, 1);
        expect(system['osVersion'], '18.0');
        expect(system['connectionType'], 'wifi');
        expect(system['colorScheme'], 'dark');
        expect(system['totalSessionsCount'], '1');
      },
    );
    test('every key sent is in the allowlist and values stay short', () async {
      const allowed = {
        'platform',
        'osName',
        'osVersion',
        'appVersion',
        'appBuildNumber',
        'deviceModel',
        'locale',
        'sdkName',
        'sdkVersion',
        'bundleId',
        'deviceType',
        'deviceBrand',
        'architecture',
        'osApiLevel',
        'runtimeVersion',
        'scriptingBackend',
        'appName',
        'installSource',
        'isSimulator',
        'isDebugBuild',
        'targetEnvironment',
        'extensionId',
        'screenWidth',
        'screenHeight',
        'screenScale',
        'screenWidthPx',
        'screenHeightPx',
        'screenDpi',
        'screenCount',
        'orientation',
        'colorScheme',
        'layoutDirection',
        'timeZone',
        'utcOffsetMinutes',
        'language',
        'preferredLanguage',
        'region',
        'fontScale',
        'contentSizeCategory',
        'reduceMotion',
        'boldText',
        'invertColors',
        'increaseContrast',
        'reduceTransparency',
        'differentiateWithoutColor',
        'fontWeightAdjustment',
        'connectionType',
        'lowPowerMode',
        'isNewInstall',
        'firstSessionDate',
        'totalSessionsCount',
        'distinctDaysUsed',
        'distinctDaysUsedLastMonth',
        'previousSessionSeconds',
        'averageSessionSeconds',
        'sessionSeconds',
        'launchMs',
        'foregroundsToday',
        'previousForegroundSeconds',
        'notificationPermission',
        'trackingPermission',
        'droppedAutomatic',
      };
      final h = Harness(
        automatic: true,
        live: FakeLive({'colorScheme': 'dark'}),
      );
      await h.send('a');
      await h.advance(1800);
      await h.send('b');
      for (final event in h.allEvents) {
        for (final entry in systemOf(event).entries) {
          expect(allowed, contains(entry.key));
          expect(entry.value! as String, hasLength(lessThanOrEqualTo(64)));
        }
      }
    });
    test('a throwing live source never stops signals', () async {
      final h = Harness(live: _ThrowingLive());
      await h.send('a');
      expect(h.events.single['type'], 'a');
    });
  });
}

class _ThrowingLive extends FakeLive {
  @override
  Map<String, String> read() => throw StateError('no');
  @override
  Future<void> warmUp() async => throw StateError('no');
}
