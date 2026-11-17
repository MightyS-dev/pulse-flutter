import 'config.dart';
import 'options.dart';

abstract interface class PulseBackend {
  Future<void> initialize(
    String key, {
    PulseOptions options = const PulseOptions(),
  });
  void track(String type, {num? value, Map<String, Object?>? props});
  void trackError(
    Object error,
    StackTrace? stack,
    Map<String, Object?>? props, {
    required String kind,
  });
  void deepLink(Uri uri);
  void setUser(String? identifier);
  Future<void> flush();
  Future<void> setOptOut(bool value);
  bool get optOut;

  /// Portal settings in force for this run (everything on until read).
  PulseConfig get config;
}
