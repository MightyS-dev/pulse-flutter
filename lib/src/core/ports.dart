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

/// Values that change while the app runs (screen, settings, connection). Reads
/// are cheap and synchronous; slow lookups are cached behind [warmUp].
abstract interface class PulseLive {
  Map<String, String> read();
  Future<void> warmUp();
}

class NoLive implements PulseLive {
  const NoLive();
  @override
  Map<String, String> read() => const {};
  @override
  Future<void> warmUp() async {}
}

abstract interface class PulseCompression {
  List<int> encode(List<int> bytes);
  List<int> decode(List<int> bytes);
}

class PulseRequest {
  PulseRequest(this.url, this.appKey, List<int> body, this.gzip, {this.batchId})
    : body = List.unmodifiable(body);
  final Uri url;
  final String appKey;
  final List<int> body;
  final bool gzip;

  /// Sent as `X-Pulse-Batch`; the same value on every retry of one batch.
  final String? batchId;
}

class PulseResponse {
  const PulseResponse(this.status, {this.body = '', this.retryAfter});
  final int status;
  final String body;
  final String? retryAfter;
}

abstract interface class PulseTransport {
  Future<PulseResponse> send(PulseRequest request);

  /// POST of one raw image (heatmap debug screenshot) with the app key.
  Future<PulseResponse> upload(
    Uri url,
    String appKey,
    List<int> bytes,
    String contentType,
  );

  /// GET with the app key and an optional `If-None-Match` value.
  Future<PulseResponse> get(Uri url, String appKey, {String? ifNoneMatch});

  /// GET of the App Control rules. Carries no app key and no identity: only
  /// `Accept` and an optional `If-None-Match`. Gives up after 3 seconds to
  /// connect and 5 seconds in all.
  Future<PulseResponse> fetchControl(Uri url, {String? ifNoneMatch});
  void cancel();
}
