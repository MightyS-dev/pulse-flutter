import 'info.dart';

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
  );
}
