import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'model.dart';
import 'options.dart';
import 'ports.dart';

class Entry {
  const Entry(this.id, this.timestamp, this.json);
  final String id;
  final DateTime timestamp;
  final String json;
  Map<String, Object?> toJson() => {
    'id': id,
    'timestamp': timestamp.toIso8601String(),
    'json': json,
  };
  static Entry fromJson(Map<String, Object?> map) => Entry(
    map['id']! as String,
    DateTime.parse(map['timestamp']! as String),
    map['json']! as String,
  );
}

String batchJson(Iterable<Entry> entries) =>
    '[${entries.map((e) => e.json).join(',')}]';

class Batch {
  Batch(
    List<String> ids,
    this.json,
    List<int> wire,
    this.gzip, {
    this.id = '',
    this.failures = 0,
    DateTime? retryAt,
  }) : ids = List.unmodifiable(ids),
       wire = List.unmodifiable(wire),
       retryAt = retryAt ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  final List<String> ids;
  final String json;

  /// Stable id of this exact batch, sent with every attempt. Empty until set.
  String id;
  List<int> wire;
  bool gzip;
  int failures;
  DateTime retryAt;
  Map<String, Object?> toJson() => {
    'ids': ids,
    'batchId': id,
    'json': json,
    'wire': base64Encode(wire),
    'gzip': gzip,
    'failures': failures,
    'retryAt': retryAt.toIso8601String(),
  };
  static Batch fromJson(Map<String, Object?> map) => Batch(
    (map['ids']! as List<Object?>).cast<String>(),
    map['json']! as String,
    base64Decode(map['wire']! as String),
    map['gzip']! as bool,
    id: _validId(map['batchId']),
    failures: map['failures']! as int,
    retryAt: DateTime.parse(map['retryAt']! as String),
  );
  static final _idFormat = RegExp(r'^[0-9a-f]{32}$');
  static String _validId(Object? value) =>
      value is String && _idFormat.hasMatch(value) ? value : '';
  void usePlain(DateTime now) {
    gzip = false;
    wire = List.unmodifiable(utf8.encode(json));
    retryAt = now;
  }
}

class SignalQueue {
  final entries = <Entry>[];
  final pending = <Batch>[];
  void add(Entry entry) {
    entries.add(entry);
  }

  void clear() {
    entries.clear();
    pending.clear();
  }

  void prune(DateTime now, PulseOptions options) {
    final oldest = now.subtract(
      Duration(microseconds: (options.maxQueueAgeDays * 86400000000).round()),
    );
    final future = now.add(const Duration(hours: 1));
    entries.removeWhere(
      (e) => e.timestamp.isBefore(oldest) || e.timestamp.isAfter(future),
    );
    if (entries.length > options.maxQueueSize) {
      entries.removeRange(0, entries.length - options.maxQueueSize);
    }
    final live = entries.map((e) => e.id).toSet();
    pending.removeWhere((b) => !b.ids.every(live.contains));
  }

  List<Entry> select(int maximum, [Iterable<Entry>? source]) {
    final chosen = <Entry>[];
    var bytes = 2;
    for (final entry in (source ?? entries).take(maximum)) {
      final extra = utf8.encode(entry.json).length + (chosen.isEmpty ? 0 : 1);
      if (bytes + extra > Signal.maxBodyBytes) {
        break;
      }
      chosen.add(entry);
      bytes += extra;
    }
    return chosen;
  }
}

class QueueSnapshot {
  QueueSnapshot(
    this.generation,
    this.entries,
    this.pending,
    this.interval,
    this.pauseUntil,
  );
  final String generation;
  final List<Entry> entries;
  final List<Batch> pending;
  final double interval;
  final DateTime pauseUntil;
  List<int> encode() {
    final payload = utf8.encode(
      jsonEncode({
        'version': 1,
        'generation': generation,
        'entries': entries.map((e) => e.toJson()).toList(),
        'pending': pending.map((b) => b.toJson()).toList(),
        'interval': interval,
        'pauseUntil': pauseUntil.toIso8601String(),
      }),
    );
    return [
      ...utf8.encode('MPF1'),
      ...sha256.convert(payload).bytes,
      ...payload,
    ];
  }

  static QueueSnapshot decode(
    List<int> bytes, {
    PulseCompression? compression,
  }) {
    try {
      if (bytes.length < 36 ||
          bytes.length > 256 * 1024 * 1024 ||
          utf8.decode(bytes.take(4).toList()) != 'MPF1') {
        throw const FormatException();
      }
      final payload = bytes.sublist(36);
      if (base64Encode(sha256.convert(payload).bytes) !=
          base64Encode(bytes.sublist(4, 36))) {
        throw const FormatException();
      }
      final map = jsonDecode(utf8.decode(payload)) as Map<String, Object?>;
      if (map['version'] != 1) {
        throw const FormatException();
      }
      final entries = (map['entries']! as List<Object?>)
          .map((e) => Entry.fromJson(e! as Map<String, Object?>))
          .toList();
      final pending = (map['pending']! as List<Object?>)
          .map((e) => Batch.fromJson(e! as Map<String, Object?>))
          .toList();
      final interval = (map['interval']! as num).toDouble();
      if (entries.length > 10000 ||
          pending.length > 1000 ||
          !interval.isFinite ||
          interval <= 0 ||
          interval > 3600) {
        throw const FormatException();
      }
      _validate(entries, pending, compression);
      return QueueSnapshot(
        map['generation']! as String,
        entries,
        pending,
        interval,
        DateTime.parse(map['pauseUntil']! as String),
      );
    } catch (_) {
      throw const FormatException('Damaged queue snapshot.');
    }
  }

  static void _validate(
    List<Entry> entries,
    List<Batch> pending,
    PulseCompression? compression,
  ) {
    final byId = <String, Entry>{};
    for (final entry in entries) {
      final object = jsonDecode(entry.json) as Map<String, Object?>;
      if (entry.id.isEmpty ||
          byId.containsKey(entry.id) ||
          utf8.encode(entry.json).length + 2 > Signal.maxBodyBytes ||
          object['timestamp'] is! String ||
          object['type'] is! String) {
        throw const FormatException();
      }
      byId[entry.id] = entry;
    }
    final seen = <String>{};
    for (final batch in pending) {
      if (batch.ids.isEmpty ||
          batch.ids.length > 1000 ||
          batch.failures < 0 ||
          batch.failures > 1000000 ||
          batch.wire.length > Signal.maxBodyBytes ||
          !batch.ids.every((id) => byId.containsKey(id) && seen.add(id))) {
        throw const FormatException();
      }
      if (batchJson(batch.ids.map((id) => byId[id]!)) != batch.json) {
        throw const FormatException();
      }
      final plain = batch.gzip ? compression?.decode(batch.wire) : batch.wire;
      if (plain == null ||
          utf8.decode(plain) != batch.json ||
          plain.length > Signal.maxBodyBytes) {
        throw const FormatException();
      }
    }
  }
}
