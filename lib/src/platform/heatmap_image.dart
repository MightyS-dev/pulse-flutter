import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Longest side of a debug screenshot, in pixels.
const heatmapShotMaxSide = 2048;

/// Largest picture the server takes.
const heatmapShotMaxBytes = 2 * 1024 * 1024;

/// A PNG of the view [viewId], taken from the root layer of the render tree
/// (no widget has to wrap the app). Only works in debug builds, where Flutter
/// keeps a handle on that layer; elsewhere it returns null. The longest side
/// is at most [maxSide] pixels and the PNG at most [maxBytes]: when it is
/// larger the picture is taken again at a smaller scale (Dart has no JPEG
/// encoder). Never throws.
Future<List<int>?> captureViewPng(
  int viewId, {
  int maxSide = heatmapShotMaxSide,
  int maxBytes = heatmapShotMaxBytes,
}) async {
  try {
    final binding = WidgetsBinding.instance;
    final view = binding.platformDispatcher.view(id: viewId);
    if (view == null || !(view.devicePixelRatio > 0)) return null;
    RenderView? renderView;
    for (final candidate in binding.renderViews) {
      if (candidate.flutterView.viewId == viewId) renderView = candidate;
    }
    final layer = renderView?.debugLayer;
    if (layer is! OffsetLayer) return null;
    final physical = view.physicalSize;
    if (!(physical.width > 0) || !(physical.height > 0)) return null;
    final dpr = view.devicePixelRatio;
    final logicalLongest = math.max(physical.width, physical.height) / dpr;
    var scale = math.min(dpr, maxSide / logicalLongest);
    for (var attempt = 0; attempt < 4; attempt++) {
      final bytes = await _png(layer, physical, dpr, scale);
      if (bytes == null) return null;
      if (bytes.length <= maxBytes) return bytes;
      scale *= 0.7;
    }
  } catch (_) {
    /* A picture is optional. */
  }
  return null;
}

/// The root layer carries the device pixel ratio itself, so the layer is asked
/// for its physical size at a pixel ratio of scale / dpr.
Future<List<int>?> _png(
  OffsetLayer layer,
  Size physical,
  double dpr,
  double scale,
) async {
  final image = await layer.toImage(
    Offset.zero & physical,
    pixelRatio: scale / dpr,
  );
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    image.dispose();
  }
}
