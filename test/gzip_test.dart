import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mightys_pulse/src/platform/compression.dart';

void main() {
  test('gzip deterministic bytes and round trips through body limit', () {
    const codec = IoCompression();
    for (final count in [0, 1025, 65536, 1048576]) {
      final input = List.generate(count, (i) => (i * 31) % 256);
      final compressed = codec.encode(input);
      expect(codec.encode(input), compressed);
      expect(codec.decode(compressed), input);
      expect(gzip.decode(compressed), input);
    }
  });
  test('bad, truncated and expansion beyond body cap rejected', () {
    const codec = IoCompression();
    expect(() => codec.decode(utf8.encode('bad')), throwsA(anything));
    final compressed = codec.encode(List.filled(2048, 97));
    expect(
      () => codec.decode(compressed.sublist(0, compressed.length - 1)),
      throwsA(anything),
    );
    expect(
      () => codec.decode(codec.encode(List.filled(1048577, 0))),
      throwsFormatException,
    );
  });
}
