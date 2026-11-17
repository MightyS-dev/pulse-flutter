import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support_control_ui.dart';

/// Pictures of every state in four looks (Android light, iOS dark, Android dark
/// with the longest language at 1.3x on a small screen, iOS light the same)
/// plus the debug build bar. They are made on macOS; elsewhere these tests skip.
final _skip = Platform.isMacOS ? null : 'goldens are generated on macOS';

typedef _Look = ({
  String name,
  TargetPlatform platform,
  bool dark,
  String language,
  double scale,
  Size size,
});

const _looks = <_Look>[
  (
    name: 'android_light_en_x10_393x852',
    platform: TargetPlatform.android,
    dark: false,
    language: 'en',
    scale: 1.0,
    size: Size(393, 852),
  ),
  (
    name: 'ios_dark_en_x10_393x852',
    platform: TargetPlatform.iOS,
    dark: true,
    language: 'en',
    scale: 1.0,
    size: Size(393, 852),
  ),
  (
    name: 'android_dark_de_x13_360x640',
    platform: TargetPlatform.android,
    dark: true,
    language: 'de',
    scale: 1.3,
    size: Size(360, 640),
  ),
  (
    name: 'ios_light_de_x13_360x640',
    platform: TargetPlatform.iOS,
    dark: false,
    language: 'de',
    scale: 1.3,
    size: Size(360, 640),
  ),
];

void main() {
  setUpAll(loadTestFonts);

  for (final look in _looks) {
    for (final kind in controlKinds.where((k) => k != 'normal')) {
      testWidgets('$kind ${look.name}', (tester) async {
        setScreen(tester, look.size.width, look.size.height);
        final control = await startControl(
          rigFor(kind),
          language: look.language,
        );
        await tester.pumpWidget(
          controlApp(
            control,
            platform: look.platform,
            brightness: look.dark ? Brightness.dark : Brightness.light,
            textScale: look.scale,
            locale: Locale(look.language),
          ),
        );
        await tester.pump();
        await tester.pump();
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/control/${kind}_${look.name}.png'),
        );
      }, skip: _skip != null);
    }
  }

  for (final kind in ['updateRequired', 'versionBlocked', 'maintenance']) {
    testWidgets('$kind debug build bar', (tester) async {
      setScreen(tester, 393, 852);
      final control = await startControl(rigFor(kind), debug: true);
      await tester.pumpWidget(controlApp(control));
      await tester.pump();
      await tester.pump();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          'goldens/control/${kind}_debug_android_light_en_x10_393x852.png',
        ),
      );
    }, skip: _skip != null);
  }
}
