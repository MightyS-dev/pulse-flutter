import 'package:flutter/foundation.dart';
import 'core/backend.dart';
import 'core/options.dart';
import 'core/info.dart';

/// Failure boundary around platform creation and every public operation.
class PulseClient {
  PulseClient(this.factory);
  final PulseBackend Function() factory;
  PulseBackend? _instance;
  bool _debug = kDebugMode;
  PulseBackend get _backend => _instance ??= factory();
  void _warn() {
    if (_debug) {
      try {
        debugPrint('${PulseInfo.displayName}: operation failed safely.');
      } catch (_) {
        /* Host logging is optional. */
      }
    }
  }

  bool get optOut {
    try {
      return _backend.optOut;
    } catch (_) {
      return true;
    }
  }

  Future<void> initialize(
    String key, {
    PulseOptions options = const PulseOptions(),
  }) async {
    _debug = options.debug;
    try {
      await _backend.initialize(key, options: options);
    } catch (_) {
      _warn();
    }
  }

  void track(String type, {num? value, Map<String, Object?>? props}) {
    try {
      _backend.track(type, value: value, props: props);
    } catch (_) {
      _warn();
    }
  }

  void setUser(String? identifier) {
    try {
      _backend.setUser(identifier);
    } catch (_) {
      _warn();
    }
  }

  Future<void> flush() async {
    try {
      await _backend.flush();
    } catch (_) {
      _warn();
    }
  }

  Future<void> setOptOut(bool value) async {
    try {
      await _backend.setOptOut(value);
    } catch (_) {
      _warn();
    }
  }
}
