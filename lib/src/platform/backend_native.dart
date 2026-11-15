import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../core/backend.dart';
import '../core/model.dart';
import '../core/options.dart';
import '../core/ports.dart';
import '../core/runtime.dart';
import 'compression.dart';
import 'computation.dart';
import 'environment.dart';
import 'file_storage.dart';
import 'http_transport.dart';
import 'lifecycle.dart';
import 'system_services.dart';

PulseBackend createBackend() {
  WidgetsFlutterBinding.ensureInitialized();
  return NativeBackend(
    PulseRuntime(
      clock: SystemClock(),
      scheduler: SystemScheduler(),
      random: SecureRandom(),
      storage: _ApplicationStorage(),
      transport: IoTransport(),
      compression: const IoCompression(),
      computation: const IsolateComputation(),
      environment: NativeEnvironment(),
      log: debugPrint,
    ),
  );
}

class NativeBackend implements PulseBackend {
  NativeBackend(this.runtime) {
    _lifecycle = PulseLifecycle(runtime.backgroundSave);
  }
  final PulseRuntime runtime;
  late final PulseLifecycle _lifecycle;
  @override
  bool get optOut => runtime.optOut;
  @override
  Future<void> initialize(
    String key, {
    PulseOptions options = const PulseOptions(),
  }) => runtime.initialize(key, options: options);
  @override
  void track(String type, {num? value, Map<String, Object?>? props}) =>
      runtime.track(type, value: value, props: props);
  @override
  void setUser(String? identifier) => runtime.setUser(identifier);
  @override
  Future<void> flush() => runtime.flush();
  @override
  Future<void> setOptOut(bool value) => runtime.setOptOut(value);
  Future<void> dispose() async {
    _lifecycle.dispose();
    await runtime.close();
  }
}

class _ApplicationStorage implements PulseStorage {
  FileStorage? _resolved;
  Future<FileStorage> _storage() async {
    if (_resolved != null) {
      return _resolved!;
    }
    final root = await getApplicationSupportDirectory();
    final info = await PackageInfo.fromPlatform();
    if (info.packageName.isEmpty) {
      throw StateError('Application storage namespace unavailable.');
    }
    final separator = Platform.pathSeparator;
    return _resolved = FileStorage(
      Directory(
        '${root.path}${separator}MightySPulse$separator${hashText(info.packageName)}',
      ),
    );
  }

  @override
  Future<List<int>?> read(String name) async => (await _storage()).read(name);
  @override
  Future<void> replace(String name, List<int> bytes) async =>
      (await _storage()).replace(name, bytes);
  @override
  Future<void> remove(String name) async => (await _storage()).remove(name);
}
