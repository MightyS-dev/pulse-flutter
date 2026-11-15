import 'dart:convert';
import 'model.dart';
import 'ports.dart';
import 'queue.dart';

/// Expensive snapshot/batch work is replaceable by an isolate adapter.
abstract interface class PulseComputation {
  Future<List<int>> encode(QueueSnapshot snapshot);
  Future<QueueSnapshot> decode(List<int> bytes, PulseCompression compression);
  Future<Batch> batch(
    List<Entry> entries,
    bool compress,
    PulseCompression compression,
  );
}

class InlineComputation implements PulseComputation {
  const InlineComputation();
  @override
  Future<List<int>> encode(QueueSnapshot snapshot) async => snapshot.encode();
  @override
  Future<QueueSnapshot> decode(
    List<int> bytes,
    PulseCompression compression,
  ) async => QueueSnapshot.decode(bytes, compression: compression);
  @override
  Future<Batch> batch(
    List<Entry> entries,
    bool compress,
    PulseCompression compression,
  ) async => prepareBatch(entries, compress, compression);
}

Batch prepareBatch(
  List<Entry> entries,
  bool compress,
  PulseCompression compression,
) {
  final json = batchJson(entries), plain = utf8.encode(json);
  List<int>? zipped;
  if (compress && plain.length > 1024) {
    try {
      final candidate = compression.encode(plain);
      if (candidate.length <= Signal.maxBodyBytes) {
        zipped = candidate;
      }
    } catch (_) {
      /* Plain JSON remains valid when compression is unavailable. */
    }
  }
  return Batch(
    entries.map((e) => e.id).toList(),
    json,
    zipped ?? plain,
    zipped != null,
  );
}
