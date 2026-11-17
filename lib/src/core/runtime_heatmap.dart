part of 'runtime.dart';

/// Heatmap glue of the runtime: switches, signal emission, flush triggers.
extension _Heat on PulseRuntime {
  /// Heatmaps need the package switch, the code options, the newest portal
  /// settings (the switch, automatic signals, the type, screen views), the
  /// cached screen view permission, no opt-out and a started client.
  bool _heatmapAllowed() =>
      automaticSignals &&
      _options.automaticSignals &&
      _options.captureHeatmaps &&
      !_optOut &&
      _key != null &&
      _live.allows(heatmapType) &&
      _config.screenViewsAllowed;

  /// The newest settings may have switched heatmaps off (drop the buffer) or
  /// on (a picture of the current screen may be wanted).
  void _heatmapChanged() {
    if (!_heatmapAllowed()) {
      _heatmap.drop();
      return;
    }
    _notifyScreen();
  }

  void _notifyScreen() {
    try {
      onHeatmapScreen?.call();
    } catch (_) {
      _warn('Heatmap screenshot hook failed safely.');
    }
  }

  /// The session a signal captured at [at] would belong to.
  String _heatmapSession(DateTime at) =>
      _capture.continuing(at) ?? HeatmapCapture.pendingSession;

  /// Queues one buffer as a `pulse.heatmap` signal. It follows the normal
  /// session rule at its own timestamp; the AE1 caps do not count it.
  void _emitHeatmap(Map<String, Object?> payload) {
    final at = clock.now;
    final snapshot = _liveAt(at);
    _enqueue(() async {
      if (_optOut || !_heatmapAllowed()) return;
      await _ensureInstall();
      await _ensureUsage();
      if (_optOut || !_heatmapAllowed()) return;
      await _admit(at, snapshot, heatmapType, const {}, heatmap: payload);
      final session = _capture.continuing(at);
      if (session != null) _heatmap.adoptSession(session);
    });
  }

  /// The current screen follows the `pulse.screen_view` signals of this SDK.
  /// The buffer of the old screen is sent before the new view is queued.
  void _heatmapScreen(Map<String, Object?> props) {
    final name = props['screen'];
    if (name is! String) return;
    _heatmap.setScreen(_config.screenViewsAllowed ? name : null);
    _notifyScreen();
  }

  void _heatmapOptOut() {
    _heatmap.drop();
    _heatmap.setScreen(null);
    unawaited(_shots?.forget());
  }
}
