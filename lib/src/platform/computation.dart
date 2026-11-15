import 'dart:isolate';
import '../core/computation.dart';
import '../core/ports.dart';
import '../core/queue.dart';

class IsolateComputation implements PulseComputation {
  const IsolateComputation();
  @override
  Future<List<int>> encode(QueueSnapshot snapshot) =>
      Isolate.run(snapshot.encode);
  @override
  Future<QueueSnapshot> decode(List<int> bytes, PulseCompression compression) =>
      _decode((bytes, compression));
  @override
  Future<Batch> batch(
    List<Entry> entries,
    bool compress,
    PulseCompression compression,
  ) => _batch((entries, compress, compression));
}

// Fresh function scopes keep the runtime, timers and platform objects out of closures.
Future<QueueSnapshot> _decode((List<int>, PulseCompression) input) =>
    Isolate.run(() => QueueSnapshot.decode(input.$1, compression: input.$2));
Future<Batch> _batch((List<Entry>, bool, PulseCompression) input) =>
    Isolate.run(() => prepareBatch(input.$1, input.$2, input.$3));
