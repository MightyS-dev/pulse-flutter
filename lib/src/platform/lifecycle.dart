import 'dart:async';
import 'package:flutter/widgets.dart';

class PulseLifecycle with WidgetsBindingObserver {
  PulseLifecycle(this.save) {
    WidgetsBinding.instance.addObserver(this);
  }
  final Future<void> Function() save;
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
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
