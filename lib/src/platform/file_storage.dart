import 'dart:io';
import '../core/ports.dart';

/// Atomic replacement on a single-process application support directory.
class FileStorage implements PulseStorage {
  FileStorage(this.directory);
  final Directory directory;
  int _sequence = 0;
  File _file(String name) {
    if (!RegExp(r'^[a-zA-Z0-9.-]+$').hasMatch(name)) {
      throw const FormatException('Invalid storage name.');
    }
    return File('${directory.path}${Platform.pathSeparator}$name');
  }

  @override
  Future<List<int>?> read(String name) async {
    final file = _file(name);
    RandomAccessFile? handle;
    try {
      handle = await file.open();
      final maximum = name == 'opt-out'
          ? 2
          : name == 'privacy-generation'
          ? 129
          : name == 'install-id'
          ? 65
          : name == 'config'
          ? 65536
          : name == 'usage'
          ? 262144
          : 256 * 1024 * 1024 + 1;
      final length = await handle.length();
      if (length > maximum) {
        throw const FormatException('Storage limit exceeded.');
      }
      return await handle.read(length);
    } on FileSystemException catch (error) {
      // Only ENOENT / ERROR_FILE_NOT_FOUND mean missing; unreadable privacy fails closed.
      if (error.osError?.errorCode == 2 ||
          error.osError?.errorCode == 3 && Platform.isWindows) {
        return null;
      }
      rethrow;
    } finally {
      await handle?.close();
    }
  }

  @override
  Future<void> replace(String name, List<int> bytes) async {
    await directory.create(recursive: true);
    final target = _file(name);
    final temporary = File('${target.path}.$pid.${_sequence++}.tmp');
    try {
      await temporary.writeAsBytes(bytes, flush: true);
      await temporary.rename(target.path);
    } finally {
      if (await temporary.exists()) {
        await temporary.delete();
      }
    }
  }

  @override
  Future<void> remove(String name) async {
    try {
      await _file(name).delete();
    } on FileSystemException catch (error) {
      if (error.osError?.errorCode != 2 &&
          !(Platform.isWindows && error.osError?.errorCode == 3)) {
        rethrow;
      }
    }
  }
}
