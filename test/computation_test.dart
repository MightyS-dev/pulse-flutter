import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:mightys_pulse/src/core/queue.dart';
import 'package:mightys_pulse/src/platform/computation.dart';
import 'package:mightys_pulse/src/platform/compression.dart';

void main() {
  test(
    'isolate codec encodes, validates restart bytes and compresses without runtime capture',
    () async {
      const computation = IsolateComputation();
      const compression = IoCompression();
      final now = DateTime.utc(2026);
      final entry = Entry(
        'one',
        now,
        jsonEncode({
          'timestamp': now.toIso8601String(),
          'type': 'large',
          'props': {'large': 'x' * 1000},
        }),
      );
      final batch = await computation.batch([entry], true, compression);
      expect(batch.gzip, true);
      final bytes = await computation.encode(
        QueueSnapshot('', [entry], [batch], 20, now),
      );
      final decoded = await computation.decode(bytes, compression);
      expect(decoded.pending.single.wire, batch.wire);
      expect(compression.decode(batch.wire), utf8.encode(batch.json));
    },
  );
}
