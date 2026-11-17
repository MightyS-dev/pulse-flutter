import 'dart:ui' show ErrorCallback, PlatformDispatcher;
import 'package:flutter/foundation.dart';

/// Where the host's error handlers live. Replaceable in tests.
abstract interface class ErrorSlots {
  FlutterExceptionHandler? get flutterHandler;
  set flutterHandler(FlutterExceptionHandler? value);
  ErrorCallback? get platformHandler;
  set platformHandler(ErrorCallback? value);
}

/// The real `FlutterError.onError` and `PlatformDispatcher.instance.onError`.
class SystemErrorSlots implements ErrorSlots {
  const SystemErrorSlots();
  @override
  FlutterExceptionHandler? get flutterHandler => FlutterError.onError;
  @override
  set flutterHandler(FlutterExceptionHandler? value) =>
      FlutterError.onError = value;
  @override
  ErrorCallback? get platformHandler => PlatformDispatcher.instance.onError;
  @override
  set platformHandler(ErrorCallback? value) =>
      PlatformDispatcher.instance.onError = value;
}

/// Sends unhandled errors to [sink] and always passes them on to the handler
/// that was installed before. Never swallows an error and never throws.
class ErrorHooks {
  ErrorHooks(this._sink, [this._slots = const SystemErrorSlots()]);
  final void Function(Object error, StackTrace? stack) _sink;
  final ErrorSlots _slots;
  bool _installed = false, _inside = false;

  void _capture(Object error, StackTrace? stack) {
    if (_inside) return;
    _inside = true;
    try {
      _sink(error, stack);
    } catch (_) {
      /* An error inside the hook is ignored. */
    } finally {
      _inside = false;
    }
  }

  /// Installs both hooks once.
  void install() {
    if (_installed) return;
    _installed = true;
    final previousFlutter = _slots.flutterHandler;
    _slots.flutterHandler = (details) {
      _capture(details.exception, details.stack);
      previousFlutter?.call(details);
    };
    final previousPlatform = _slots.platformHandler;
    _slots.platformHandler = (error, stack) {
      _capture(error, stack);
      // With no previous handler, false keeps Flutter's default handling.
      return previousPlatform?.call(error, stack) ?? false;
    };
  }
}
