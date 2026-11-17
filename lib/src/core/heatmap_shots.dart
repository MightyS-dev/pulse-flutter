import 'dart:convert';
import 'heatmap.dart';
import 'model.dart';
import 'ports.dart';

/// A picture of one view that the server wants: where it belongs.
class HeatmapShotTicket {
  const HeatmapShotTicket(this.screen, this.bucket, this.orientation);
  final String screen, bucket, orientation;
}

/// Debug screenshot: at most one picture per (screen, bucket, orientation,
/// app version) per install, only from debug builds. The platform takes and
/// encodes the picture; this class decides whether one is wanted and uploads
/// the raw bytes. Nothing here throws.
class HeatmapShots {
  HeatmapShots({
    required this.storage,
    required this.transport,
    required this.clock,
    required this.appKey,
    required Uri endpoint,
    required String appVersion,
    required this.debugBuild,
    required this.warn,
  }) : _endpoint = endpoint,
       _appVersion = appVersion;

  static const maxBytes = 2 * 1024 * 1024, maxPerHour = 20, maxMarkers = 1000;
  static const fileName = 'heatmap-shots';
  static const _rasters = {'image/png', 'image/jpeg', 'image/webp'};

  final PulseStorage storage;
  final PulseTransport transport;
  final PulseClock clock;
  final String appKey;
  final bool Function() debugBuild;
  final void Function(String) warn;
  final Uri _endpoint;
  final String _appVersion;
  final _markers = <String>[];
  final _attempts = <DateTime>[];
  final _inFlight = <String>{};
  DateTime _retryUntil = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  bool _loaded = false;

  String _key(String screen, String bucket, String orientation) =>
      hashText('$screen|$bucket|$orientation|$_appVersion');

  /// Opt-out: forgets the markers and deletes the file.
  Future<void> forget() async {
    _markers.clear();
    _attempts.clear();
    _loaded = true;
    _retryUntil = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    try {
      await storage.remove(fileName);
    } catch (_) {
      /* Nothing to remove, or it cannot be removed now. */
    }
  }

  Future<void> _load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final bytes = await storage.read(fileName);
      if (bytes == null) return;
      for (final line in utf8.decode(bytes, allowMalformed: true).split('\n')) {
        if (line.length == 64 && !_markers.contains(line)) _markers.add(line);
      }
    } catch (_) {
      /* No markers: a picture may be sent again, which is harmless. */
    }
  }

  int _recent(DateTime now) {
    _attempts.removeWhere((t) => now.difference(t) >= const Duration(hours: 1));
    return _attempts.length;
  }

  bool _wanted(String key) {
    final now = clock.now;
    return !_markers.contains(key) &&
        !_inFlight.contains(key) &&
        !now.isBefore(_retryUntil) &&
        _recent(now) < maxPerHour;
  }

  /// Whether a picture of this view is wanted now (null when not).
  Future<HeatmapShotTicket?> ticket(
    String? screen,
    double width,
    double height,
  ) async {
    try {
      if (screen == null ||
          screen.isEmpty ||
          !debugBuild() ||
          !(width > 0) ||
          !(height > 0)) {
        return null;
      }
      final bucket = HeatmapCapture.bucketOf(width);
      final orientation = HeatmapCapture.orientationOf(width, height);
      await _load();
      return _wanted(_key(screen, bucket, orientation))
          ? HeatmapShotTicket(screen, bucket, orientation)
          : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _mark(String key) async {
    await _load();
    if (!_markers.contains(key)) _markers.add(key);
    while (_markers.length > maxMarkers) {
      _markers.removeAt(0);
    }
    try {
      await storage.replace(fileName, utf8.encode(_markers.join('\n')));
    } catch (_) {
      warn('Heatmap marker could not be saved.');
    }
  }

  Uri _url(HeatmapShotTicket t) {
    String e(String v) => Uri.encodeComponent(v);
    final path = _endpoint.path.replaceFirst(
      RegExp(r'signals$'),
      'heatmap/screenshot',
    );
    return _endpoint.replace(
      path: path,
      query:
          'screen=${e(t.screen)}&bucket=${t.bucket}'
          '&orientation=${t.orientation}&appVersion=${e(_appVersion)}'
          '&debug=true',
    );
  }

  /// Uploads one picture. True only when the server stored it (201).
  Future<bool> upload(
    HeatmapShotTicket? ticket,
    List<int>? bytes,
    String contentType,
  ) async {
    String? key;
    try {
      if (ticket == null ||
          bytes == null ||
          bytes.isEmpty ||
          bytes.length > maxBytes ||
          !_rasters.contains(contentType) ||
          !debugBuild()) {
        return false;
      }
      key = _key(ticket.screen, ticket.bucket, ticket.orientation);
      await _load();
      if (!_wanted(key)) {
        key = null;
        return false;
      }
      _inFlight.add(key);
      _attempts.add(clock.now);
      final response = await transport.upload(
        _url(ticket),
        appKey,
        bytes,
        contentType,
      );
      final status = response.status;
      if (status == 201) {
        await _mark(key);
        return true;
      }
      if (const {403, 415, 413, 422}.contains(status)) {
        await _mark(key);
        return false;
      }
      if (const {0, 429, 503, 507}.contains(status)) {
        final parsed = double.tryParse(response.retryAfter ?? '');
        final seconds = parsed != null && parsed >= 0
            ? (parsed > 3600 ? 3600.0 : parsed)
            : 60.0;
        _retryUntil = clock.now.add(
          Duration(microseconds: (seconds * 1000000).round()),
        );
      }
      return false;
    } catch (_) {
      return false;
    } finally {
      if (key != null) _inFlight.remove(key);
    }
  }
}
