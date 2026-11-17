import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'control.dart';
import 'control_buttons.dart';
import 'control_dialogs.dart';
import 'control_theme.dart';
import 'core/control_state.dart';
import 'heatmap_widgets.dart';

/// Whether a state covers the app (so the app below must not take touches,
/// focus or screen reader attention). Only the maintenance bar does not.
bool controlLocksApp(ControlState state) =>
    state.kind != ControlKind.maintenanceUpcoming;

/// The screen for [state]: full screen, dialog, card or bar.
class ControlOverlay extends StatelessWidget {
  const ControlOverlay({
    super.key,
    required this.state,
    required this.control,
    required this.look,
  });
  final ControlState state;
  final PulseControl control;
  final ControlLook look;

  @override
  Widget build(BuildContext context) {
    // SDK screens are never app usage: taps on them are not heatmap points. A
    // screen that covers the app is marked as a whole; the bar marks its own strip.
    final screen = Directionality(
      textDirection: Directionality.of(context),
      child: switch (state.kind) {
        ControlKind.updateRequired ||
        ControlKind.versionBlocked ||
        ControlKind.maintenance => ControlFullScreen(
          state: state,
          control: control,
          look: look,
        ),
        ControlKind.updateSuggested => ControlDialog(
          state: state,
          control: control,
          look: look,
        ),
        ControlKind.announcement || ControlKind.whatsNew => ControlCard(
          state: state,
          control: control,
          look: look,
        ),
        ControlKind.maintenanceUpcoming => ControlBar(
          state: state,
          control: control,
          look: look,
        ),
        ControlKind.normal => const SizedBox.shrink(),
      },
    );
    return controlLocksApp(state) ? PulseHeatmapIgnore(child: screen) : screen;
  }
}

/// Whether the main button of an update screen can do anything.
bool controlCanUpdate(ControlState state, PulseControl control) =>
    state.url != null && control.canOpenStore;

/// A thin strip that says this is a debug build preview.
class ControlTestBanner extends StatelessWidget {
  const ControlTestBanner({super.key, required this.text, required this.look});
  final String text;
  final ControlLook look;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: ColoredBox(
      color: look.banner,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: look.body.copyWith(
            color: look.onBanner,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            height: 1.25,
          ),
        ),
      ),
    ),
  );
}

/// Update required, version blocked and maintenance: the whole screen.
class ControlFullScreen extends StatelessWidget {
  const ControlFullScreen({
    super.key,
    required this.state,
    required this.control,
    required this.look,
  });
  final ControlState state;
  final PulseControl control;
  final ControlLook look;

  void _primary() {
    switch (state.kind) {
      case ControlKind.maintenance:
        control.checkNow();
      default:
        control.openStore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final showPrimary =
        state.buttonText != null &&
        (state.kind == ControlKind.maintenance ||
            controlCanUpdate(state, control));
    final textAlign = look.cupertino ? TextAlign.center : TextAlign.start;
    final banner = state.isTestBuild && state.testBuildText != null
        ? ControlTestBanner(text: state.testBuildText!, look: look)
        : null;
    final body = LayoutBuilder(
      builder: (context, box) => ListView(
        padding: EdgeInsets.zero,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(minHeight: box.maxHeight),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                  child: ControlColumn(
                    children: [
                      Align(
                        alignment: look.cupertino
                            ? Alignment.center
                            : AlignmentDirectional.centerStart,
                        child: SizedBox(
                          width: 44,
                          height: 6,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: look.accent,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      if (state.title != null)
                        Semantics(
                          header: true,
                          child: Text(
                            state.title!,
                            textAlign: textAlign,
                            style: look.title,
                          ),
                        ),
                      if (state.body != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          state.body!,
                          textAlign: textAlign,
                          style: look.body,
                        ),
                      ],
                      const SizedBox(height: 28),
                      if (showPrimary)
                        ControlPrimaryButton(
                          look: look,
                          label: state.buttonText!,
                          onPressed: _primary,
                        ),
                      if (state.allowContinue &&
                          state.secondaryButtonText != null) ...[
                        if (showPrimary) const SizedBox(height: 8),
                        ControlTextButton(
                          look: look,
                          label: state.secondaryButtonText!,
                          onPressed: control.dismiss,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: state.title,
      child: Material(
        color: look.background,
        child: SafeArea(
          child: ControlBannerLayout(banner: banner, body: body),
        ),
      ),
    );
  }
}

/// A banner on top and the body in the rest of the height (a column with
/// one expanded child, without the flex machinery).
class ControlBannerLayout extends StatelessWidget {
  const ControlBannerLayout({super.key, this.banner, required this.body});
  final Widget? banner;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    final top = banner;
    if (top == null) return body;
    return CustomMultiChildLayout(
      delegate: _BannerDelegate(),
      children: [
        LayoutId(id: 0, child: top),
        LayoutId(id: 1, child: body),
      ],
    );
  }
}

class _BannerDelegate extends MultiChildLayoutDelegate {
  _BannerDelegate();

  @override
  void performLayout(Size size) {
    final top = layoutChild(0, BoxConstraints(maxWidth: size.width)).height;
    layoutChild(
      1,
      BoxConstraints.tightFor(
        width: size.width,
        height: size.height > top ? size.height - top : 0,
      ),
    );
    positionChild(1, Offset(0, top));
  }

  @override
  bool shouldRelayout(_BannerDelegate oldDelegate) => false;
}

/// The maintenance heads-up bar at the top. It never covers the app: only the
/// bar itself takes touches.
class ControlBar extends StatelessWidget {
  const ControlBar({
    super.key,
    required this.state,
    required this.control,
    required this.look,
  });
  final ControlState state;
  final PulseControl control;
  final ControlLook look;

  @override
  Widget build(BuildContext context) {
    final label = state.secondaryButtonText;
    return Align(
      alignment: Alignment.topCenter,
      child: SafeArea(
        bottom: false,
        child: PulseHeatmapIgnore(
          child: Semantics(
            container: true,
            liveRegion: true,
            child: Material(
              color: look.banner,
              child: InkWell(
                onTap: control.dismiss,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    child: ControlEndRow(
                      children: [
                        Text(
                          state.body ?? '',
                          style: look.body.copyWith(
                            color: look.onBanner,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            height: 1.25,
                          ),
                        ),
                        Semantics(
                          button: true,
                          label: label,
                          excludeSemantics: true,
                          child: Text(
                            '×',
                            style: look.title.copyWith(
                              color: look.onBanner,
                              fontSize: 26,
                              height: 1,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Children one under the other at full width, as tall as they are together
/// (a `ListBody` or a `Column` with `mainAxisSize.min` and stretch, without
/// their machinery).
class ControlColumn extends Stack {
  const ControlColumn({super.key, super.children});

  @override
  RenderStack createRenderObject(BuildContext context) => _RenderColumn();
}

class _RenderColumn extends RenderStack {
  Size _layout(BoxConstraints c, ChildLayouter layout, bool place) {
    final width = BoxConstraints.tightFor(width: c.maxWidth);
    var y = 0.0;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      if (place) (child.parentData! as StackParentData).offset = Offset(0, y);
      y += layout(child, width).height;
    }
    return c.constrain(Size(c.maxWidth, y));
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      _layout(constraints, ChildLayoutHelper.dryLayoutChild, false);

  @override
  void performLayout() {
    size = _layout(constraints, ChildLayoutHelper.layoutChild, true);
  }
}

/// A row of two: the first child takes the width the second one leaves, 12
/// apart, both centered in height (a `Row` with one `Expanded` child, without
/// the flex machinery).
class ControlEndRow extends Stack {
  const ControlEndRow({super.key, super.children});

  @override
  RenderStack createRenderObject(BuildContext context) =>
      _RenderEndRow(Directionality.of(context));

  @override
  void updateRenderObject(BuildContext context, RenderStack renderObject) =>
      renderObject.textDirection = Directionality.of(context);
}

class _RenderEndRow extends RenderStack {
  _RenderEndRow(TextDirection direction) : super(textDirection: direction);
  static const _gap = 12.0;

  Size _layout(BoxConstraints c, ChildLayouter layout, bool place) {
    final lead = firstChild!, end = lastChild!;
    final loose = BoxConstraints(maxHeight: c.maxHeight);
    final endSize = layout(end, loose);
    final width = c.maxWidth - _gap - endSize.width;
    final leadSize = layout(lead, loose.tighten(width: width < 0 ? 0 : width));
    final size = c.constrain(
      Size(
        c.maxWidth,
        leadSize.height > endSize.height ? leadSize.height : endSize.height,
      ),
    );
    if (place) {
      final rtl = textDirection == TextDirection.rtl;
      (lead.parentData! as StackParentData).offset = Offset(
        rtl ? size.width - leadSize.width : 0,
        (size.height - leadSize.height) / 2,
      );
      (end.parentData! as StackParentData).offset = Offset(
        rtl ? 0 : size.width - endSize.width,
        (size.height - endSize.height) / 2,
      );
    }
    return size;
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      _layout(constraints, ChildLayoutHelper.dryLayoutChild, false);

  @override
  void performLayout() {
    size = _layout(constraints, ChildLayoutHelper.layoutChild, true);
  }
}
