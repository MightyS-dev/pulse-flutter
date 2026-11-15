/// External effects are injected. Core logic has no Flutter or IO dependencies.
abstract interface class PulseStorage {
  Future<List<int>?> read(String name);
  Future<void> replace(String name, List<int> bytes);
  Future<void> remove(String name);
}

abstract interface class PulseClock {
  DateTime get now;
}

abstract interface class Cancellation {
  void cancel();
}

abstract interface class PulseScheduler {
  Cancellation schedule(Duration delay, void Function() callback);
}

abstract interface class PulseRandom {
  String token();
  double sample();
}

abstract interface class PulseEnvironment {
  Future<Map<String, String>> system();
}

abstract interface class PulseCompression {
  List<int> encode(List<int> bytes);
  List<int> decode(List<int> bytes);
}

class PulseRequest {
  PulseRequest(this.url, this.appKey, List<int> body, this.gzip)
    : body = List.unmodifiable(body);
  final Uri url;
  final String appKey;
  final List<int> body;
  final bool gzip;
}

class PulseResponse {
  const PulseResponse(this.status, {this.body = '', this.retryAfter});
  final int status;
  final String body;
  final String? retryAfter;
}

abstract interface class PulseTransport {
  Future<PulseResponse> send(PulseRequest request);
  void cancel();
}
