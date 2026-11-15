/// Privacy-first analytics for Flutter with durable offline delivery.
library;

import 'src/client.dart';
import 'src/core/options.dart';
import 'src/platform/backend_stub.dart'
    if (dart.library.io) 'src/platform/backend_native.dart'
    as platform;
export 'src/core/options.dart' show PulseOptions;

/// The process-wide analytics client. Initialize once near application startup.
abstract final class Pulse {
  static final _client = PulseClient(platform.createBackend);

  /// Starts the client with the application key. Later calls are ignored. Never throws.
  static Future<void> initialize(
    String appKey, {
    PulseOptions options = const PulseOptions(),
  }) => _client.initialize(appKey, options: options);

  /// Captures one signal with an optional finite [value] and primitive [props]
  /// (String, bool, int, finite double). Invalid input is dropped, never thrown.
  static void track(String type, {num? value, Map<String, Object?>? props}) =>
      _client.track(type, value: value, props: props);

  /// Sets a stable user id that is hashed (SHA-256) on the device before use, or
  /// clears it with null. The raw id is never stored or sent.
  static void setUser(String? identifier) => _client.setUser(identifier);

  /// Waits for captured signals to leave the queue. Can wait indefinitely offline.
  static Future<void> flush() => _client.flush();

  /// Persists the opt-out preference. Opting out clears the queue and stops
  /// collection and sending.
  static Future<void> setOptOut(bool value) => _client.setOptOut(value);

  /// True until the durable preference has been read, or when storage fails closed.
  static bool get optOut => _client.optOut;
}
