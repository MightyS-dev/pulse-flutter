import 'package:flutter/foundation.dart';
import 'control.dart';
import 'core/backend.dart';
import 'core/control_client.dart';
import 'core/options.dart';
import 'core/info.dart';
import 'core/screen_views.dart';
import 'error_hooks.dart';

/// Failure boundary around platform creation and every public operation.
class PulseClient {
  PulseClient(this.factory, {ErrorSlots? errorSlots, bool? hooksSupported})
    : _slots = errorSlots,
      _hooksSupported = hooksSupported ?? !kIsWeb;
  final PulseBackend Function() factory;
  final ErrorSlots? _slots;
  final bool _hooksSupported;
  ErrorHooks? _hooks;
  PulseBackend? _instance;

  /// App Control as the app sees it. It works before `initialize` (state is
  /// normal) and never creates the backend by itself.
  final PulseControl control = PulseControl();
  bool _debug = kDebugMode;
  late final ScreenViews screens = ScreenViews(
    (type, props) => track(type, props: props),
  );
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

  bool _portalAllowsScreens() {
    try {
      return _backend.config.screenViewsAllowed;
    } catch (_) {
      return true;
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
    screens.automatic = options.automaticScreenViews;
    screens.portalAllows = _portalAllowsScreens;
    _installHooks(options);
    try {
      await _backend.initialize(key, options: options);
    } catch (_) {
      _warn();
    }
    _attachControl(options);
  }

  void _attachControl(PulseOptions options) {
    try {
      final Object? backend = _instance;
      if (backend is ControlBackend) {
        final ControlClient client = backend.control;
        control.attach(client, options.control, debug: options.debug);
      }
    } catch (_) {
      _warn();
    }
  }

  void _installHooks(PulseOptions options) {
    try {
      if (!options.captureErrors || !_hooksSupported || _hooks != null) return;
      final hooks = ErrorHooks(
        (error, stack) =>
            _backend.trackError(error, stack, null, kind: 'error'),
        _slots ?? const SystemErrorSlots(),
      );
      _hooks = hooks;
      hooks.install();
    } catch (_) {
      _warn();
    }
  }

  void trackError(
    Object error,
    StackTrace? stack,
    Map<String, Object?>? props,
  ) {
    try {
      _backend.trackError(
        error,
        stack ?? StackTrace.current,
        props,
        kind: 'handled',
      );
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

  void screen(String name) {
    try {
      screens.screen(name);
    } catch (_) {
      _warn();
    }
  }

  void deepLink(Uri uri) {
    try {
      _backend.deepLink(uri);
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
