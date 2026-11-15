import 'dart:async';
import 'dart:convert';
import 'package:mightys_pulse/src/core/options.dart';
import 'package:mightys_pulse/src/core/ports.dart';
import 'package:mightys_pulse/src/core/runtime.dart';
import 'package:mightys_pulse/src/platform/compression.dart';

class FakeStorage implements PulseStorage {
  final files = <String, List<int>>{};
  bool failReads = false, failWrites = false;
  final failing = <String>{};
  Future<void> Function(String)? afterReplace;
  @override
  Future<List<int>?> read(String name) async {
    if (failReads || failing.contains(name)) {
      throw StateError('read');
    }
    return files[name] == null ? null : List.of(files[name]!);
  }

  @override
  Future<void> replace(String name, List<int> bytes) async {
    if (failWrites || failing.contains(name)) {
      throw StateError('write');
    }
    files[name] = List.of(bytes);
    await afterReplace?.call(name);
  }

  @override
  Future<void> remove(String name) async {
    if (failWrites || failing.contains(name)) {
      throw StateError('remove');
    }
    files.remove(name);
  }

  String get queueName => files.keys.firstWhere((s) => s.startsWith('queue-'));
}

class Task implements Cancellation {
  Task(this.at, this.callback);
  final DateTime at;
  final void Function() callback;
  bool cancelled = false;
  @override
  void cancel() {
    cancelled = true;
  }
}

class FakeTime implements PulseClock, PulseScheduler {
  FakeTime([DateTime? date]) : date = date ?? DateTime.utc(2026, 11, 13);
  DateTime date;
  final tasks = <Task>[];
  @override
  DateTime get now => date;
  @override
  Cancellation schedule(Duration delay, void Function() callback) {
    final task = Task(now.add(delay), callback);
    tasks.add(task);
    return task;
  }

  void advance(double seconds) {
    date = date.add(Duration(microseconds: (seconds * 1000000).round()));
    final ready = tasks
        .where((t) => !t.cancelled && !t.at.isAfter(now))
        .toList();
    tasks.removeWhere((t) => t.cancelled || ready.contains(t));
    for (final task in ready) {
      task.callback();
    }
  }
}

class FakeRandom implements PulseRandom {
  static int global = 0;
  double value = 0.5;
  @override
  String token() => (++global).toRadixString(16).padLeft(32, '0');
  @override
  double sample() => value;
}

class FakeEnvironment implements PulseEnvironment {
  FakeEnvironment({this.gate});

  /// When set, the lookup finishes only after this future completes.
  final Future<void>? gate;
  @override
  Future<Map<String, String>> system() async {
    await gate;
    return Map.of(_values);
  }

  static const _values = {
    'platform': 'mobile',
    'osName': 'iOS',
    'osVersion': '18.0',
    'appVersion': '1.2.3',
    'appBuildNumber': '42',
    'deviceModel': 'Apple mobile device',
    'locale': 'sr-RS',
    'bundleId': 'test.local',
  };
}

class FakeTransport implements PulseTransport {
  final requests = <PulseRequest>[];
  final replies = <PulseResponse>[];
  Future<PulseResponse> Function(PulseRequest)? handler;
  int cancellations = 0;
  @override
  Future<PulseResponse> send(PulseRequest request) async {
    requests.add(request);
    return await (handler?.call(request) ??
        Future.value(
          replies.isEmpty ? const PulseResponse(202) : replies.removeAt(0),
        ));
  }

  @override
  void cancel() {
    cancellations++;
  }
}

class Harness {
  Harness({
    FakeStorage? storage,
    FakeTime? time,
    PulseOptions options = const PulseOptions(debug: false),
    bool initialize = true,
    PulseEnvironment? environment,
  }) : storage = storage ?? FakeStorage(),
       time = time ?? FakeTime() {
    runtime = PulseRuntime(
      clock: this.time,
      scheduler: this.time,
      random: random,
      storage: this.storage,
      transport: transport,
      compression: const IoCompression(),
      environment: environment ?? FakeEnvironment(),
      log: (_) {},
    );
    if (initialize) {
      unawaited(runtime.initialize('synthetic-key', options: options));
    }
  }
  final FakeStorage storage;
  final FakeTime time;
  final random = FakeRandom();
  final transport = FakeTransport();
  late final PulseRuntime runtime;
  Future<void> settle() async {
    for (var i = 0; i < 60; i++) {
      await runtime.idle;
      await Future<void>.value();
    }
  }

  Future<void> advance(double seconds) async {
    time.advance(seconds);
    await settle();
  }

  Future<void> send([
    String type = 'event',
    Map<String, Object?>? props,
  ]) async {
    runtime.track(type, props: props);
    unawaited(runtime.flush());
    await settle();
  }

  Future<void> flush() async {
    unawaited(runtime.flush());
    await settle();
  }

  List<Map<String, Object?>> get events =>
      transport.requests.expand(eventsOf).toList();
}

String plain(PulseRequest r) =>
    utf8.decode(r.gzip ? const IoCompression().decode(r.body) : r.body);
List<Map<String, Object?>> eventsOf(PulseRequest r) =>
    (jsonDecode(plain(r)) as List<Object?>).cast<Map<String, Object?>>();
