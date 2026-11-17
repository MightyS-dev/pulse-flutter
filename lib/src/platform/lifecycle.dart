import 'dart:async';
import 'package:flutter/widgets.dart';

/// Watches the app lifecycle: saves state when the app leaves the foreground
/// and reports real foreground and background transitions.
///
/// `resumed` is foreground. `paused` and `hidden` are background. `inactive`
/// (a call, the app switcher) is neither, and `detached` only saves.
class PulseLifecycle with WidgetsBindingObserver {
  PulseLifecycle(
    this.save, {
    this.onForeground,
    this.onBackground,
    AppLifecycleState? initialState,
  }) {
    final state = initialState ?? _currentState();
    _foreground =
        state != AppLifecycleState.paused &&
        state != AppLifecycleState.hidden &&
        state != AppLifecycleState.detached;
    WidgetsBinding.instance.addObserver(this);
  }
  final Future<void> Function() save;

  /// Called with true for the first foreground of this process, else false.
  final void Function(bool cold)? onForeground;
  final void Function()? onBackground;
  late bool _foreground;
  bool _cold = true, _started = false;

  static AppLifecycleState? _currentState() {
    try {
      return WidgetsBinding.instance.lifecycleState;
    } catch (_) {
      return null;
    }
  }

  /// Reports the foreground the app is already in as the cold start. An app
  /// that started in the background reports it on its first resume instead.
  void start() {
    if (_started) return;
    _started = true;
    if (_foreground) _enter();
  }

  void _enter() {
    final cold = _cold;
    _cold = false;
    _call(() => onForeground?.call(cold));
  }

  void _call(void Function() action) {
    try {
      action();
    } catch (_) {
      /* Lifecycle cannot surface errors into the host. */
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!_foreground) {
        _foreground = true;
        if (_started) _enter();
      }
      return;
    }
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      if (_foreground) {
        _foreground = false;
        if (_started) _call(() => onBackground?.call());
      }
      unawaited(_save());
    }
  }

  Future<void> _save() async {
    try {
      await save().timeout(const Duration(seconds: 2));
    } catch (_) {
      /* Lifecycle cannot surface errors into the host. */
    }
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
  }
}
