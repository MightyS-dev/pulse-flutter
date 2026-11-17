import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Keeps taps inside [child] out of the heatmaps. Wrap anything the heatmap
/// must never see, for example a card with personal content.
///
/// It changes nothing for the user: it neither consumes taps nor changes
/// layout, painting or hit testing of [child]. Taps on text fields are never
/// captured, with or without this widget.
class PulseHeatmapIgnore extends SingleChildRenderObjectWidget {
  /// Creates a marker around [child].
  const PulseHeatmapIgnore({super.key, required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderPulseHeatmapIgnore();
}

/// The marker the heatmap hook finds in a hit test result.
///
/// It adds itself to the hit test path of every position inside its size, also
/// when the child is not hit (a plain label has no hit target of its own), and
/// never reports a hit of its own, so widgets behind it keep working.
class RenderPulseHeatmapIgnore extends RenderProxyBox {
  /// Creates the marker.
  RenderPulseHeatmapIgnore([super.child]);

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    final hit = super.hitTest(result, position: position);
    if (!hit && size.contains(position)) {
      result.add(BoxHitTestEntry(this, position));
    }
    return hit;
  }
}
