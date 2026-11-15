import 'model.dart';
import 'ports.dart';

/// Process-local sessions and pseudonymous user state. Raw users are never retained.
class Capture {
  Capture(this.random);
  final PulseRandom random;
  String? _session;
  DateTime? _lastActivity;
  String? userHash;
  String sessionAt(DateTime now) {
    if (_lastActivity == null ||
        now.difference(_lastActivity!).inSeconds >= 1800) {
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
    _session = null;
    _lastActivity = null;
  }
}
