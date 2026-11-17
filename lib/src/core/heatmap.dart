import 'dart:math' as math;
import 'heatmap_shots.dart';
import 'ports.dart';

/// Signal type of one buffer of taps.
const heatmapType = 'pulse.heatmap';

/// What the platform hook needs from the runtime.
abstract interface class HeatmapSink {
  /// True while taps are being captured: the portal switch, the options and
  /// opt-out all allow it and a screen is known. Hooks may skip their work
  /// otherwise.
  bool get heatmapActive;

  /// The screen name taps are filed under, or null when none is known.
  String? get heatmapScreen;

  /// One tap in logical pixels, with the privacy flags the hook can see.
  void heatmapTap(
    double x,
    double y,
    double width,
    double height, {
    required bool keyboardVisible,
    required bool inputTarget,
    required bool ignored,
  });

  /// Called when the current screen changed or heatmaps were switched on.
  void Function()? onHeatmapScreen;

  /// Whether a debug screenshot of the current screen is wanted now.
  Future<HeatmapShotTicket?> heatmapShotTicket(double width, double height);

  /// Uploads a picture for [ticket]. True only when stored.
  Future<bool> heatmapScreenshot(
    HeatmapShotTicket? ticket,
    List<int> bytes,
    String contentType,
  );
}

/// Taps folded into one buffer per (screen, bucket, orientation), handed to
/// [emit] as the `heatmap` object of a `pulse.heatmap` signal.
///
/// The platform hook reports a tap in logical pixels together with the three
/// privacy flags it can see; this class applies every other rule. It keeps
/// no lock: all calls come from the one isolate that owns the SDK.
class HeatmapCapture {
  HeatmapCapture({
    required this.clock,
    required this.enabled,
    required this.sessionAt,
    required this.emit,
  });

  static const maxPointsPerSignal = 200, maxPointsPerSession = 1000;
  static const rageWindow = Duration(seconds: 1);
  static const rageRadius = 30.0, maxY = 100000.0;

  /// Stands for a session that does not exist yet.
  static const pendingSession = 'pending';

  final PulseClock clock;

  /// Whether capture is allowed right now (portal, options, opt-out).
  final bool Function() enabled;

  /// The session a signal captured at the given time would belong to, or
  /// [pendingSession] when it would start a new one.
  final String Function(DateTime) sessionAt;
  final void Function(Map<String, Object?>) emit;

  final _points = <Map<String, Object?>>[];
  String? _screen, _bufferScreen, _bufferBucket, _bufferOrientation;
  String? _sessionId;
  int _sessionCount = 0, _clusterCount = 0;
  DateTime _clusterTime = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  double _clusterX = 0, _clusterY = 0;

  /// The screen taps are filed under, or null when none is known.
  String? get screen => _screen;

  static String bucketOf(double width) =>
      width < 600 ? 'phone' : (width < 1024 ? 'tablet' : 'desktop');

  static String orientationOf(double width, double height) =>
      height >= width ? 'portrait' : 'landscape';

  bool _safeEnabled() {
    try {
      return enabled();
    } catch (_) {
      return false;
    }
  }

  /// Whole numbers are written without a fraction.
  static num _tidy(double value) =>
      value == value.roundToDouble() ? value.toInt() : value;

  /// Sets the current screen (null when none is known). The buffer of the
  /// old screen is sent first.
  void setScreen(String? name) {
    if (name == _screen) return;
    final payload = _take();
    _screen = name;
    _clusterCount = 0;
    _send(payload);
  }

  /// One tap. [x] and [y] are logical pixels from the top left, [width] and
  /// [height] the size of the screen in the same unit.
  void onTap(
    double x,
    double y,
    double width,
    double height, {
    required bool keyboardVisible,
    required bool inputTarget,
    required bool ignored,
  }) {
    if (keyboardVisible || inputTarget || ignored) return;
    if (!x.isFinite ||
        !y.isFinite ||
        !width.isFinite ||
        !height.isFinite ||
        width <= 0 ||
        height <= 0) {
      return;
    }
    if (!_safeEnabled()) {
      drop();
      return;
    }
    final now = clock.now;
    final String session;
    try {
      session = sessionAt(now);
    } catch (_) {
      return;
    }
    final fraction = (x / width).clamp(0.0, 1.0);
    final rounded = (fraction * 1000).round() / 1000;
    final top = (y.clamp(0.0, maxY) * 10).round() / 10;
    final bucket = bucketOf(width), orientation = orientationOf(width, height);
    final screen = _screen;
    if (screen == null) return;
    if (_sessionId != session) {
      _sessionId = session;
      _sessionCount = 0;
    }
    if (_sessionCount >= maxPointsPerSession) return;
    final ready = <Map<String, Object?>>[];
    if (_points.isNotEmpty &&
        (bucket != _bufferBucket || orientation != _bufferOrientation)) {
      ready.add(_take()!);
    }
    if (_points.isEmpty) {
      _bufferScreen = screen;
      _bufferBucket = bucket;
      _bufferOrientation = orientation;
    }
    final px = rounded * width;
    var kind = 'tap';
    if (_clusterCount > 0 &&
        now.difference(_clusterTime) <= rageWindow &&
        math.sqrt(
              (px - _clusterX) * (px - _clusterX) +
                  (top - _clusterY) * (top - _clusterY),
            ) <=
            rageRadius) {
      _clusterCount++;
      if (_clusterCount >= 3) kind = 'rage';
    } else {
      _clusterCount = 1;
      _clusterTime = now;
      _clusterX = px;
      _clusterY = top;
    }
    _points.add({'x': _tidy(rounded), 'y': _tidy(top), 'kind': kind});
    _sessionCount++;
    if (_points.length >= maxPointsPerSignal) ready.add(_take()!);
    ready.forEach(_send);
  }

  /// Sends the open buffer, if any.
  void flush() => _send(_take());

  /// Forgets the open buffer without sending it (switched off or opt-out).
  void drop() {
    _points.clear();
    _clusterCount = 0;
  }

  /// After a heatmap signal started or joined a session, the point count
  /// follows that session.
  void adoptSession(String id) {
    if (_sessionId == pendingSession) _sessionId = id;
  }

  Map<String, Object?>? _take() {
    if (_points.isEmpty) return null;
    final payload = <String, Object?>{
      'screen': _bufferScreen,
      'bucket': _bufferBucket,
      'orientation': _bufferOrientation,
      'points': List<Map<String, Object?>>.of(_points),
    };
    _points.clear();
    return payload;
  }

  void _send(Map<String, Object?>? payload) {
    if (payload == null) return;
    try {
      if (_safeEnabled()) emit(payload);
    } catch (_) {
      /* A heatmap must never break the app. */
    }
  }
}
