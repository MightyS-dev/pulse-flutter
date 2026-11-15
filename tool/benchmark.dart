import 'dart:convert';
import 'package:mightys_pulse/src/core/queue.dart';

void main() {
  final now = DateTime.now().toUtc();
  final json = jsonEncode({
    'timestamp': now.toIso8601String(),
    'type': 'benchmark',
    'props': {for (var i = 0; i < 7; i++) 'p$i': 'x' * 1024},
  });
  final entries = List.generate(1000, (i) => Entry('$i', now, json));
  final snapshot = QueueSnapshot('', entries, [], 20, now);
  final watch = Stopwatch()..start();
  final bytes = snapshot.encode();
  watch.stop();
  // A developer benchmark, outside the application build path.
  // ignore: avoid_print
  print(
    'Default full queue: ${bytes.length} bytes, encode ${watch.elapsedMicroseconds / 1000} ms',
  );
}
