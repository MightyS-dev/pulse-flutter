import 'dart:async';
import 'dart:ui' show PlatformDispatcher;
import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import '../core/ports.dart';
import 'display_state.dart';
import 'host.dart';
import 'network_power.dart';

/// Reads the values that change while the app runs: screen, language,
/// accessibility settings, connection type and battery saver.
class NativeLive with WidgetsBindingObserver implements PulseLive {
  NativeLive({
    PlatformDispatcher? dispatcher,
    HostOs? host,
    NetworkPower? network,
  }) : _dispatcher = dispatcher ?? PlatformDispatcher.instance,
       _host = host ?? HostOs.current,
       _network = network ?? _defaultNetwork() {
    try {
      WidgetsBinding.instance.addObserver(this);
    } catch (_) {
      /* Without a binding the cached values simply refresh on read. */
    }
  }
  final PlatformDispatcher _dispatcher;
  final HostOs _host;
  final NetworkPower _network;

  static NetworkPower _defaultNetwork() => NetworkPower(
    connectivity: Connectivity().checkConnectivity,
    changes: () => Connectivity().onConnectivityChanged,
    powerSave: () => Battery().isInBatterySaveMode,
  );

  @override
  Map<String, String> read() => {
    ...readDisplayState(_dispatcher, _host),
    ..._network.read(),
  };

  @override
  Future<void> warmUp() => _network.warmUp();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_network.refreshPower());
    }
  }

  void dispose() {
    try {
      WidgetsBinding.instance.removeObserver(this);
    } catch (_) {
      /* Nothing to remove without a binding. */
    }
    _network.dispose();
  }
}
