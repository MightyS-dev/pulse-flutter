import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mightys_pulse/src/core/queue.dart';
import 'package:mightys_pulse/src/platform/file_storage.dart';
import 'package:mightys_pulse/src/core/options.dart';

void main() {
  final now = DateTime.utc(2026, 11, 13);
  test(
    'queue drops oldest and stale or future entries; batches honor byte/count caps',
    () {
      final queue = SignalQueue();
      for (var i = 0; i < 5; i++) {
        queue.add(Entry('$i', now, '{"type":"$i"}'));
      }
      queue.prune(now, const PulseOptions(maxQueueSize: 3));
      expect(queue.entries.map((e) => e.id), ['2', '3', '4']);
      expect(queue.select(2).length, 2);
      queue.add(Entry('future', now.add(const Duration(hours: 2)), '{}'));
      queue.add(Entry('old', now.subtract(const Duration(days: 8)), '{}'));
      queue.prune(now, const PulseOptions());
      expect(queue.entries.length, 3);
      queue.entries.clear();
      for (var i = 0; i < 300; i++) {
        queue.add(Entry('$i', now, '{"data":"${'x' * 8000}"}'));
      }
      expect(
        utf8.encode(batchJson(queue.select(1000))).length,
        lessThanOrEqualTo(1048576),
      );
      expect(queue.select(1000).length, lessThan(300));
    },
  );
  test('snapshot round trip, exact pending wire and corruption rejection', () {
    final entry = Entry(
      'a',
      now,
      '{"timestamp":"${now.toIso8601String()}","type":"event"}',
    );
    final batch = Batch(
      [entry.id],
      batchJson([entry]),
      utf8.encode(batchJson([entry])),
      false,
    );
    final snapshot = QueueSnapshot('generation', [entry], [batch], 20, now);
    final bytes = snapshot.encode();
    final decoded = QueueSnapshot.decode(bytes);
    expect(decoded.pending.single.wire, batch.wire);
    expect(decoded.entries.single.json, entry.json);
    for (final damaged in [
      <int>[],
      bytes.sublist(0, 35),
      bytes.sublist(0, bytes.length - 1),
      [...bytes]..[40] ^= 1,
    ]) {
      expect(() => QueueSnapshot.decode(damaged), throwsFormatException);
    }
  });
  test(
    'real atomic file storage: missing, replace, torn temp and remove',
    () async {
      final directory = await Directory.systemTemp.createTemp('pulse-files-');
      addTearDown(() => directory.delete(recursive: true));
      final storage = FileStorage(directory);
      expect(await storage.read('queue'), isNull);
      await storage.replace('queue', [1, 2, 3]);
      await File('${directory.path}/queue.tmp').writeAsBytes([99]);
      expect(await FileStorage(directory).read('queue'), [1, 2, 3]);
      await storage.replace('queue', [4]);
      expect(await storage.read('queue'), [4]);
      await storage.remove('queue');
      await storage.remove('queue');
      expect(await storage.read('queue'), isNull);
    },
  );
  test('real file snapshot survives storage recreation', () async {
    final directory = await Directory.systemTemp.createTemp('pulse-snapshot-');
    addTearDown(() => directory.delete(recursive: true));
    final entry = Entry(
      'one',
      now,
      '{"timestamp":"${now.toIso8601String()}","type":"saved"}',
    );
    await FileStorage(
      directory,
    ).replace('queue', QueueSnapshot('', [entry], [], 20, now).encode());
    expect(
      QueueSnapshot.decode(
        (await FileStorage(directory).read('queue'))!,
      ).entries.single.json,
      entry.json,
    );
  });
}
