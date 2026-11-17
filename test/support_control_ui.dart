import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mightys_pulse/src/control.dart';
import 'package:mightys_pulse/src/core/control_state.dart';
import 'package:mightys_pulse/src/core/model.dart';
import 'support_control.dart';

/// Loads Roboto from the Flutter SDK so pictures show real letters instead of
/// the test font's blocks. Without the SDK folder the layout is measured with
/// the blocks, which are wider and so only stricter.
Future<void> loadTestFonts() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) return;
  final loader = FontLoader('Roboto');
  for (final name in ['Regular', 'Medium', 'Bold']) {
    final file = File(
      '$root/bin/cache/artifacts/material_fonts/Roboto-$name.ttf',
    );
    if (!file.existsSync()) return;
    loader.addFont(
      Future.value(
        ByteData.sublistView(Uint8List.fromList(file.readAsBytesSync())),
      ),
    );
  }
  await loader.load();
}

/// Every state of App Control, by name.
const controlKinds = [
  'updateRequired',
  'updateSuggested',
  'versionBlocked',
  'maintenance',
  'maintenanceUpcoming',
  'announcement',
  'whatsNew',
  'normal',
];

/// A rig whose rules produce the state [kind] for the app version 1.0.0.
Rig rigFor(String kind, {bool debug = false}) {
  final rig = Rig(appVersion: '1.0.0');
  final now = rig.time.now;
  String at(Duration d) => now.add(d).toIso8601String();
  const store = 'https://pulse.mightys.dev/app';
  switch (kind) {
    case 'updateRequired':
      rig.reply(rulesJson(update: requiredUpdate('2.0.0')));
    case 'updateSuggested':
      rig.reply(
        rulesJson(
          update: {
            'ios': {
              'min': null,
              'latest': '2.0.0',
              'mode': 'suggested',
              'storeVersion': null,
              'storeUrl': store,
            },
          },
        ),
      );
    case 'versionBlocked':
      rig.reply(
        rulesJson(
          update: {
            'ios': {
              'min': null,
              'latest': null,
              'mode': null,
              'storeVersion': '1.1.0',
              'storeUrl': store,
            },
          },
          blocked: [
            {'version': '1.0.0', 'platforms': null, 'allowContinue': false},
          ],
        ),
      );
    case 'maintenance':
      rig.reply(
        rulesJson(
          maintenance: {
            'startsAt': at(const Duration(minutes: -5)),
            'endsAt': at(const Duration(hours: 2)),
            'headsUpMinutes': 30,
            'exemptAboveStore': false,
            'platforms': null,
          },
        ),
      );
    case 'maintenanceUpcoming':
      rig.reply(
        rulesJson(
          maintenance: {
            'startsAt': at(const Duration(minutes: 20)),
            'endsAt': at(const Duration(hours: 2)),
            'headsUpMinutes': 60,
            'exemptAboveStore': false,
            'platforms': null,
          },
        ),
      );
    case 'announcement':
      rig.reply(
        rulesJson(
          announcement: {
            'id': 'a7',
            'title': 'Winter event',
            'body':
                'Snow has arrived in the garden. Collect five snowdrops this week to unlock a new frame.',
            'url': null,
            'buttonText': null,
            'until': at(const Duration(days: 3)),
            'platforms': null,
          },
        ),
      );
    case 'whatsNew':
      rig.reply(
        rulesJson(
          whatsNew: {
            'version': '1.0.0',
            'body': 'Bigger gardens, a calmer night mode and faster saves.',
          },
        ),
      );
      rig
              .storage
              .files['control-local-${hashText(controlKey).substring(0, 16)}'] =
          '{"appVersion":"0.9.0"}'.codeUnits;
    default:
      rig.reply(rulesJson());
  }
  return rig;
}

/// Starts the rig for [kind] and returns the control it feeds.
Future<PulseControl> startControl(
  Rig rig, {
  String language = 'en',
  bool debug = false,
  ControlMode mode = ControlMode.automatic,
  bool opener = true,
}) async {
  final control = PulseControl();
  if (opener) control.onOpenStore = (_) {};
  control.setAppLanguage(language);
  control.attach(rig.client, mode, debug: false);
  rig.start(mode: mode, debug: debug);
  await rig.settle();
  return control;
}

class _AnyMaterial extends LocalizationsDelegate<MaterialLocalizations> {
  const _AnyMaterial();
  @override
  bool isSupported(Locale locale) => true;
  @override
  Future<MaterialLocalizations> load(Locale locale) =>
      DefaultMaterialLocalizations.delegate.load(const Locale('en'));
  @override
  bool shouldReload(
    covariant LocalizationsDelegate<MaterialLocalizations> old,
  ) => false;
}

class _AnyCupertino extends LocalizationsDelegate<CupertinoLocalizations> {
  const _AnyCupertino();
  @override
  bool isSupported(Locale locale) => true;
  @override
  Future<CupertinoLocalizations> load(Locale locale) =>
      DefaultCupertinoLocalizations.delegate.load(const Locale('en'));
  @override
  bool shouldReload(
    covariant LocalizationsDelegate<CupertinoLocalizations> old,
  ) => false;
}

/// The app under test: the one line, a platform, a theme, a text scale.
Widget controlApp(
  PulseControl control, {
  TargetPlatform platform = TargetPlatform.android,
  Brightness brightness = Brightness.light,
  double textScale = 1.0,
  Widget? home,
  Locale? locale,
}) {
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF2E7D5B),
    brightness: brightness,
  );
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    locale: locale,
    localizationsDelegates: const [
      _AnyMaterial(),
      _AnyCupertino(),
      DefaultWidgetsLocalizations.delegate,
    ],
    supportedLocales: [?locale, const Locale('en', 'US')],
    theme: ThemeData(
      colorScheme: scheme,
      platform: platform,
      fontFamily: 'Roboto',
    ),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: control.builder(context, child),
    ),
    home:
        home ??
        Scaffold(
          appBar: AppBar(title: const Text('Garden')),
          body: const Center(child: Text('Home screen')),
        ),
  );
}

void setScreen(WidgetTester tester, double width, double height) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}
