import 'model.dart';
import 'ports.dart';

/// Process-local sessions and pseudonymous user state. Raw users are never retained.
class Capture {
  Capture(this.random);
  final PulseRandom random;
  String? _session;
  DateTime? _lastActivity;
  String? userHash;

  /// Hash of the anonymous install id, used while no user is set.
  String? installHash;

  /// True when the latest [sessionAt] call created a new session.
  bool startedSession = false;
  String sessionAt(DateTime now) {
    startedSession =
        _lastActivity == null ||
        now.difference(_lastActivity!).inSeconds >= 1800;
    if (startedSession) {
      _session = random.token();
    }
    _lastActivity = now;
    return _session!;
  }

  void setUser(String? identifier) {
    userHash = identifier == null || identifier.isEmpty
        ? null
        : hashText(identifier);
  }

  void reset() {
    userHash = null;
    installHash = null;
    _session = null;
    _lastActivity = null;
  }
}
