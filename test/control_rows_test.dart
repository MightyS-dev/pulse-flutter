import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mightys_pulse/src/control_views.dart';

/// The size-light layouts of the App Control screens place their children
/// exactly where the Flex widgets they replace would.
void main() {
  textButtonEquivalence();
  const lead = Key('lead'), end = Key('end');
  Widget texts(String body, double endSize) =>
      Text(body, key: lead, style: const TextStyle(fontSize: 14, height: 1.25));
  Widget cross(double endSize) => Text(
    'x',
    key: end,
    style: TextStyle(fontSize: endSize, height: 1),
  );

  Future<List<Rect>> rects(
    WidgetTester tester,
    Widget row,
    TextDirection direction,
    double width,
  ) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: direction,
        child: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: width,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 28),
              child: row,
            ),
          ),
        ),
      ),
    );
    return [tester.getRect(find.byKey(lead)), tester.getRect(find.byKey(end))];
  }

  testWidgets('ControlEndRow matches Row with an Expanded first child', (
    tester,
  ) async {
    for (final direction in TextDirection.values) {
      for (final width in [120.0, 328.0, 600.0]) {
        for (final endSize in [26.0, 60.0]) {
          for (final body in ['Short', 'A much longer text ' * 6]) {
            final want = await rects(
              tester,
              Row(
                children: [
                  Expanded(child: texts(body, endSize)),
                  const SizedBox(width: 12),
                  cross(endSize),
                ],
              ),
              direction,
              width,
            );
            final got = await rects(
              tester,
              ControlEndRow(children: [texts(body, endSize), cross(endSize)]),
              direction,
              width,
            );
            expect(got, want, reason: '$direction $width $endSize $body');
          }
        }
      }
    }
  });

  testWidgets('ControlColumn matches ListBody', (tester) async {
    for (final width in [200.0, 328.0]) {
      final children = [
        const Align(
          alignment: AlignmentDirectional.centerStart,
          child: SizedBox(width: 44, height: 6),
        ),
        const SizedBox(height: 20),
        Text('Title ' * 8, style: const TextStyle(fontSize: 24)),
        const SizedBox(height: 12),
        Text('Body ' * 12, textAlign: TextAlign.center),
      ];
      Future<List<Rect>> place(Widget layout) async {
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Align(
              alignment: Alignment.topCenter,
              child: UnconstrainedBox(
                constrainedAxis: Axis.horizontal,
                child: SizedBox(width: width, child: layout),
              ),
            ),
          ),
        );
        return [
          tester.getRect(find.byWidget(layout)),
          for (final child in children) tester.getRect(find.byWidget(child)),
        ];
      }

      final want = await place(ListBody(children: children));
      final got = await place(ControlColumn(children: children));
      expect(got, want, reason: 'width $width');
    }
  });

  testWidgets('ControlBannerLayout matches Column with an Expanded body', (
    tester,
  ) async {
    for (final banner in [true, false]) {
      Widget top() => const SizedBox(
        key: lead,
        width: double.infinity,
        child: Text('Test build', style: TextStyle(fontSize: 13)),
      );
      const body = SizedBox.expand(key: end);
      Future<List<Rect>> place(Widget layout) async {
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: SizedBox(width: 300, height: 500, child: layout),
            ),
          ),
        );
        return [
          if (banner) tester.getRect(find.byKey(lead)),
          tester.getRect(find.byKey(end)),
        ];
      }

      final want = await place(
        Column(
          children: [
            if (banner) top(),
            const Expanded(child: body),
          ],
        ),
      );
      final got = await place(
        ControlBannerLayout(banner: banner ? top() : null, body: body),
      );
      expect(got, want, reason: 'banner $banner');
    }
  });
}

/// The second button is a FilledButton with no fill: in every state it
/// resolves to the same style a TextButton with the old style had.
void textButtonEquivalence() {
  testWidgets('the text button resolves like TextButton in every state', (
    tester,
  ) async {
    for (final brightness in Brightness.values) {
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            colorSchemeSeed: Colors.teal,
            brightness: brightness,
          ),
          home: Builder(
            builder: (c) {
              context = c;
              return const SizedBox();
            },
          ),
        ),
      );
      const accent = Color(0xFF0B6E4F);
      final text = TextButton(
        onPressed: () {},
        style: TextButton.styleFrom(
          foregroundColor: accent,
          minimumSize: const Size.fromHeight(48),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        ),
        child: const Text('x'),
      );
      final filled = FilledButton(
        onPressed: () {},
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0x00000000),
          foregroundColor: accent,
          elevation: 0,
          minimumSize: const Size.fromHeight(48),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        ),
        child: const Text('x'),
      );
      // As ButtonStyleButton does: each style resolved, the first non-null.
      // The theme and default styles are protected; reading them here is the
      // point of the check.
      T? pick<T>(ButtonStyleButton b, T? Function(ButtonStyle? s) f) =>
          f(b.style) ??
          // ignore: invalid_use_of_protected_member
          f(b.themeStyleOf(context)) ??
          // ignore: invalid_use_of_protected_member
          f(b.defaultStyleOf(context));
      for (final states in <Set<WidgetState>>[
        {},
        {WidgetState.pressed},
        {WidgetState.hovered},
        {WidgetState.focused},
      ]) {
        Object? all(ButtonStyleButton b) => [
          pick(b, (s) => s?.backgroundColor?.resolve(states)),
          pick(b, (s) => s?.foregroundColor?.resolve(states)),
          pick(b, (s) => s?.overlayColor?.resolve(states)),
          pick(b, (s) => s?.elevation?.resolve(states)),
          pick(b, (s) => s?.textStyle?.resolve(states)),
          pick(b, (s) => s?.padding?.resolve(states)),
          pick(b, (s) => s?.minimumSize?.resolve(states)),
          pick(b, (s) => s?.maximumSize?.resolve(states)),
          pick(b, (s) => s?.shape?.resolve(states)),
          pick(b, (s) => s?.side?.resolve(states)),
          pick(b, (s) => s?.mouseCursor?.resolve(states)),
          pick(b, (s) => s?.visualDensity),
          pick(b, (s) => s?.tapTargetSize),
          pick(b, (s) => s?.alignment),
          pick(b, (s) => s?.splashFactory),
          pick(b, (s) => s?.animationDuration),
          pick(b, (s) => s?.enableFeedback),
        ].toString();
        expect(all(filled), all(text), reason: '$brightness $states');
      }
    }
  });
}
