import 'dart:io';

/// Unpacks the built-in texts.
List<int> controlGunzip(List<int> bytes) => gzip.decode(bytes);
