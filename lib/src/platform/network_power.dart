import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';

/// Active connections from either plugin shape: a single result (older
/// plugin versions) or a list (newer ones).
List<ConnectivityResult> connectionResults(Object? raw) {
  if (raw is Iterable) {
    return raw.whereType<ConnectivityResult>().toList();
  }
  if (raw is ConnectivityResult) {
    return [raw];
  }
  return const [];
}

/// Connection type for the wire, from the active connections.
String? connectionTypeOf(List<ConnectivityResult> results) {
  if (results.isEmpty) {
    return null;
  }
  if (results.contains(ConnectivityResult.wifi)) {
    return 'wifi';
  }
  if (results.contains(ConnectivityResult.ethernet)) {
    return 'ethernet';
  }
  if (results.contains(ConnectivityResult.mobile)) {
    return 'cellular';
  }
  if (results.every((r) => r == ConnectivityResult.none)) {
    return 'none';
  }
  return 'other';
}

/// Cached connection type and battery saver state. The plugins answer
/// asynchronously, so reads return the last known values and refresh quietly.
class NetworkPower {
  NetworkPower({
    required this.connectivity,
    required this.changes,
    required this.powerSave,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;
  final Future<Object?> Function() connectivity;
  final Stream<Object?> Function() changes;
  final Future<bool> Function() powerSave;
  final DateTime Function() _now;
  String? _connection;
  bool? _power;
  DateTime _checked = DateTime.fromMillisecondsSinceEpoch(0);
  StreamSubscription<Object?>? _subscription;
  bool _refreshing = false;

  Future<void> warmUp() async {
    try {
      _connection = connectionTypeOf(connectionResults(await connectivity()));
    } catch (_) {
      /* Connection type stays unknown. */
    }
    _subscription ??= _listen();
    await refreshPower();
  }

  StreamSubscription<Object?>? _listen() {
    try {
      return changes().listen(
        (results) => _connection = connectionTypeOf(connectionResults(results)),
        onError: (Object _) {},
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> refreshPower() async {
    if (_refreshing) {
      return;
    }
    _refreshing = true;
    _checked = _now();
    try {
      _power = await powerSave();
    } catch (_) {
      _power = null;
    } finally {
      _refreshing = false;
    }
  }

  Map<String, String> read() {
    if (_now().difference(_checked).inSeconds >= 60) {
      unawaited(refreshPower());
    }
    return {
      'connectionType': ?_connection,
      if (_power != null) 'lowPowerMode': '$_power',
    };
  }

  void dispose() {
    unawaited(_subscription?.cancel());
    _subscription = null;
  }
}
