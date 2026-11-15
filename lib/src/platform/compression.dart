import 'dart:io';
import '../core/ports.dart';

class IoCompression implements PulseCompression {
  const IoCompression();
  @override
  List<int> encode(List<int> bytes) => gzip.encode(bytes);
  @override
  List<int> decode(List<int> bytes) {
    if (bytes.length < 18 ||
        bytes[0] != 31 ||
        bytes[1] != 139 ||
        bytes[2] != 8 ||
        bytes[3] != 0) {
      throw const FormatException('Invalid gzip header.');
    }
    final output = <int>[];
    final sink = gzip.decoder.startChunkedConversion(_LimitedSink(output));
    sink.add(bytes);
    sink.close();
    final footer = bytes.length - 8;
    int little(int offset) =>
        bytes[offset] |
        bytes[offset + 1] << 8 |
        bytes[offset + 2] << 16 |
        bytes[offset + 3] << 24;
    var crc = 0xffffffff;
    for (final byte in output) {
      crc ^= byte;
      for (var bit = 0; bit < 8; bit++) {
        crc = (crc >> 1) ^ ((crc & 1) == 1 ? 0xedb88320 : 0);
      }
    }
    if (((crc ^ 0xffffffff) & 0xffffffff) != little(footer) ||
        output.length != little(footer + 4)) {
      throw const FormatException('Invalid gzip footer.');
    }
    return output;
  }
}

class _LimitedSink implements Sink<List<int>> {
  _LimitedSink(this.output);
  final List<int> output;
  @override
  void add(List<int> data) {
    if (output.length + data.length > 1048576) {
      throw const FormatException('Gzip exceeds body limit.');
    }
    output.addAll(data);
  }

  @override
  void close() {}
}
