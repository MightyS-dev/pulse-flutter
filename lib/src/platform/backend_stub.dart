import 'package:flutter/foundation.dart';
import '../core/backend.dart';
import '../core/options.dart';
import '../core/info.dart';

PulseBackend createBackend() => WebBackend();

/// Web is deliberately unsupported; this backend never creates effects.
class WebBackend implements PulseBackend {
  WebBackend({void Function(String)? log}) : _log = log ?? debugPrint;
  final void Function(String) _log;
  bool _warned = false, _optOut = false;
  @override
  bool get optOut => _optOut;
  @override
  Future<void> initialize(
    String key, {
    PulseOptions options = const PulseOptions(),
  }) async {
    if (options.debug && !_warned) {
      _warned = true;
      try {
        _log(
          '${PulseInfo.displayName}: web not supported; analytics disabled.',
        );
      } catch (_) {
        /* No-op stays safe with a failing logger. */
      }
    }
  }

  @override
  void track(String type, {num? value, Map<String, Object?>? props}) {}
  @override
  void setUser(String? identifier) {}
  @override
  Future<void> flush() async {}
  @override
  Future<void> setOptOut(bool value) async {
    _optOut = value;
  }
}
