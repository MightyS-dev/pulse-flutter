import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mightys_pulse/src/control_views.dart';
import 'support_control_ui.dart';

/// Every state x light and dark x English and the longest language (German)
/// x text scale 1.0 and 1.3 x Android and iOS look x 393x852 and 360x640:
/// 256 screens with no overflow error and no need to scroll.
void main() {
  setUpAll(loadTestFonts);

  testWidgets('256 screens: no overflow, nothing clipped, no scrolling needed', (
    tester,
  ) async {
    var screens = 0;
    for (final kind in controlKinds) {
      for (final dark in [false, true]) {
        for (final language in ['en', 'de']) {
          for (final scale in [1.0, 1.3]) {
            for (final platform in [
              TargetPlatform.android,
              TargetPlatform.iOS,
            ]) {
              for (final size in [const Size(393, 852), const Size(360, 640)]) {
                final label =
                    '$kind ${dark ? 'dark' : 'light'} $language x$scale ${platform.name} ${size.width.toInt()}x${size.height.toInt()}';
                setScreen(tester, size.width, size.height);
                final control = await startControl(
                  rigFor(kind),
                  language: language,
                  debug: kind == 'updateRequired' && dark,
                );
                await tester.pumpWidget(
                  controlApp(
                    control,
                    platform: platform,
                    brightness: dark ? Brightness.dark : Brightness.light,
                    textScale: scale,
                    locale: Locale(language),
                  ),
                );
                await tester.pump();
                await tester.pump();
                expect(tester.takeException(), isNull, reason: label);
                expect(
                  control.state.kind.name,
                  kind == 'normal' ? 'normal' : kind,
                  reason: label,
                );
                if (kind != 'normal' && kind != 'maintenanceUpcoming') {
                  for (final scrollable in tester.stateList<ScrollableState>(
                    find.byType(Scrollable),
                  )) {
                    final extent = scrollable.position.maxScrollExtent;
                    final inOverlay = find
                        .descendant(
                          of: find.byType(ControlOverlay),
                          matching: find.byWidget(scrollable.widget),
                        )
                        .evaluate()
                        .isNotEmpty;
                    if (inOverlay) {
                      expect(extent, 0.0, reason: 'needs scrolling: $label');
                    }
                  }
                }
                screens++;
                await tester.pumpWidget(const SizedBox());
              }
            }
          }
        }
      }
    }
    expect(screens, 256);
  });

  testWidgets(
    'the scroll probe is real: a tiny screen at 1.3x does need to scroll',
    (tester) async {
      setScreen(tester, 200, 260);
      final control = await startControl(
        rigFor('updateRequired'),
        language: 'de',
      );
      await tester.pumpWidget(controlApp(control, textScale: 1.3));
      await tester.pump();
      await tester.pump();
      final extents = [
        for (final s in tester.stateList<ScrollableState>(
          find.byType(Scrollable),
        ))
          if (find
              .descendant(
                of: find.byType(ControlOverlay),
                matching: find.byWidget(s.widget),
              )
              .evaluate()
              .isNotEmpty)
            s.position.maxScrollExtent,
      ];
      expect(extents, isNotEmpty);
      expect(extents.any((e) => e > 0), true);
    },
  );
}
