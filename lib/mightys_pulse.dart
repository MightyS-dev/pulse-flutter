/// Privacy-first analytics for Flutter with durable offline delivery.
library;

import 'src/client.dart';
import 'src/control.dart';
import 'src/core/options.dart';
import 'src/screen_observer.dart';
import 'src/platform/backend_stub.dart'
    if (dart.library.io) 'src/platform/backend_native.dart'
    as platform;
export 'src/control.dart' show PulseControl;
export 'src/control_theme.dart' show PulseControlTheme;
export 'src/core/control_state.dart'
    show ControlKind, ControlMode, ControlState;
export 'src/core/options.dart' show ErrorDetail, PulseOptions;
export 'src/heatmap_widgets.dart' show PulseHeatmapIgnore;
export 'src/screen_observer.dart' show PulseNavigatorObserver;

/// The process-wide analytics client. Initialize once near application startup.
abstract final class Pulse {
  static final _client = PulseClient(platform.createBackend);

  /// App Control: require an update, suggest one or show maintenance from the
  /// portal. One line shows the built-in screens:
  /// `MaterialApp(builder: Pulse.control.builder)`.
  static final PulseControl control = _client.control;

  /// Starts the client with the application key. Later calls are ignored. Never throws.
  static Future<void> initialize(
    String appKey, {
    PulseOptions options = const PulseOptions(),
  }) => _client.initialize(appKey, options: options);

  /// Captures one signal with an optional finite [value] and primitive [props]
  /// (String, bool, int, finite double). Invalid input is dropped, never thrown.
  static void track(String type, {num? value, Map<String, Object?>? props}) =>
      _client.track(type, value: value, props: props);

  /// Sends a handled error as `pulse.error` with kind `handled`: its type, a
  /// filtered message and readable frames of [stack] (the current stack when
  /// none is given), plus optional primitive [props]. Works even when
  /// `captureErrors` is false. At most 10 per error type and session are sent.
  /// Never throws.
  static void trackError(
    Object error, [
    StackTrace? stack,
    Map<String, Object?>? props,
  ]) => _client.trackError(error, stack, props);

  /// Add to `navigatorObservers` (or a router's observers) to send a
  /// `pulse.screen_view` for each screen. Switch off with
  /// `PulseOptions(automaticScreenViews: false)`.
  static final PulseNavigatorObserver navigatorObserver =
      PulseNavigatorObserver(_client.screens);

  /// Sends a `pulse.screen_view` for [name] (at most 128 characters). Use it
  /// where the observer cannot see a screen. Follows opt-out.
  static void screen(String name) => _client.screen(name);

  /// Reports a link that opened the app as `pulse.deep_link`: its scheme, host
  /// and path (numeric and uuid-like segments become `:id`, at most 128
  /// characters) and the `utm_source`, `utm_medium` and `utm_campaign` tags.
  /// Never the rest of the query, the fragment, credentials or a port. Call it
  /// from your router or from the `app_links` stream. Follows opt-out and the
  /// automatic signal switches. Never throws.
  static void deepLink(Uri uri) => _client.deepLink(uri);

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
