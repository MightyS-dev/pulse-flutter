import 'control_state.dart';
import 'info.dart';

/// How much of an error is sent.
enum ErrorDetail {
  /// Type, filtered message and frames (default).
  full,

  /// Only the error type. No message and no frames.
  typeOnly,
}

/// Delivery and privacy configuration passed to `Pulse.initialize`.
///
/// Every field has a safe default. Out-of-range limits are clamped to a
/// supported range instead of throwing.
class PulseOptions {
  /// Creates options. Omit any argument to keep its default.
  const PulseOptions({
    this.host = PulseInfo.defaultHost,
    this.flushIntervalSeconds = 20,
    this.maxBatchSize = 100,
    this.maxQueueSize = 1000,
    this.maxQueueAgeDays = 7,
    this.gzip = true,
    this.debug =
        !const bool.fromEnvironment('dart.vm.product') &&
        !const bool.fromEnvironment('dart.vm.profile'),
    this.sendAppIdentity = true,
    this.appVersion,
    this.automaticScreenViews = true,
    this.automaticSignals = true,
    this.captureErrors = true,
    this.errorDetail = ErrorDetail.full,
    this.captureHeatmaps = true,
    this.control = ControlMode.automatic,
  });

  /// Base URL of the ingest host (HTTP or HTTPS, no credentials, query or
  /// fragment). Defaults to `https://in.mightys.dev`.
  final String host;

  /// Seconds between batches after the first one. Defaults to 20 and is
  /// clamped to 0.05 through 3600.
  final double flushIntervalSeconds;

  /// Largest number of signals in one request. Defaults to 100 and is clamped
  /// to 1 through 1000.
  final int maxBatchSize;

  /// Largest number of signals kept in the offline queue. Defaults to 1000 and
  /// is clamped to 1 through 10000. The oldest signals drop first.
  final int maxQueueSize;

  /// Days a queued signal is kept before it expires. Defaults to 7 and is
  /// clamped to at most 29.
  final double maxQueueAgeDays;

  /// Whether larger batches are gzip-compressed. Defaults to true.
  final bool gzip;

  /// Marks signals as test data and prints short diagnostics. Defaults to true
  /// in debug builds and false in profile and release builds.
  final bool debug;

  /// Whether the app package name is sent as `system.bundleId`. Defaults to
  /// true.
  final bool sendAppIdentity;

  /// Overrides the app version taken from the platform package info.
  final String? appVersion;

  /// Whether `Pulse.navigatorObserver` sends screen views. Defaults to true.
  /// `Pulse.screen` always works.
  final bool automaticScreenViews;

  /// Whether `pulse.session_started`, `pulse.new_install` and
  /// `pulse.app_updated` are sent. Defaults to true. Like
  /// [automaticScreenViews] it can only switch things off: the portal settings
  /// apply on top of it.
  final bool automaticSignals;

  /// Whether unhandled errors are sent as `pulse.error` (kind `error`).
  /// Defaults to true. When false no error handler is installed.
  /// `Pulse.trackError` works either way.
  final bool captureErrors;

  /// How much of an error is sent: [ErrorDetail.full] (default) or
  /// [ErrorDetail.typeOnly].
  final ErrorDetail errorDetail;

  /// Whether taps are captured for heatmaps when the portal has them on.
  /// Defaults to true (follow the portal). Like [automaticSignals] it can
  /// only switch capture off, never on. Screen views and `automaticSignals`
  /// must stay on as well.
  final bool captureHeatmaps;

  /// How App Control behaves. [ControlMode.automatic] (default) checks the
  /// rules and shows the built-in screens through `Pulse.control.builder`,
  /// [ControlMode.manual] checks and keeps `Pulse.control.state` up to date but
  /// shows nothing, [ControlMode.off] makes no request for App Control at all.
  final ControlMode control;

  /// Returns a copy with every limit clamped to its supported range.
  PulseOptions normalized() => PulseOptions(
    host: host,
    flushIntervalSeconds:
        flushIntervalSeconds.isFinite && flushIntervalSeconds > 0
        ? flushIntervalSeconds.clamp(0.05, 3600)
        : 20,
    maxBatchSize: maxBatchSize.clamp(1, 1000),
    maxQueueSize: maxQueueSize.clamp(1, 10000),
    maxQueueAgeDays: maxQueueAgeDays.isFinite && maxQueueAgeDays > 0
        ? maxQueueAgeDays.clamp(0.000001, 29)
        : 7,
    gzip: gzip,
    debug: debug,
    sendAppIdentity: sendAppIdentity,
    appVersion: appVersion,
    automaticScreenViews: automaticScreenViews,
    automaticSignals: automaticSignals,
    captureErrors: captureErrors,
    errorDetail: errorDetail,
    captureHeatmaps: captureHeatmaps,
    control: control,
  );
}
