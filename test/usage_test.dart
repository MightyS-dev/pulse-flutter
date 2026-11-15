import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:mightys_pulse/src/core/options.dart';
import 'package:mightys_pulse/src/core/ports.dart';
import 'package:mightys_pulse/src/core/usage.dart';
import 'support.dart';

Map<String, Object?> systemOf(Map<String, Object?> event) =>
    event['system']! as Map<String, Object?>;

/// A harness that sends the automatic signals, on a given day and hour.
Harness session(
  FakeStorage storage, {
  DateTime? at,
  PulseEnvironment? environment,
  PulseOptions options = const PulseOptions(debug: false),
}) => Harness(
  storage: storage,
  time: FakeTime(at ?? DateTime.utc(2026, 11, 13, 12)),
  automatic: true,
  environment: environment,
  options: options,
);

class VersionEnvironment implements PulseEnvironment {
  VersionEnvironment(this.version, this.build);
  final String version, build;
  @override
  Future<Map<String, String>> system() async => {
    'platform': 'mobile',
    'osName': 'iOS',
    'osVersion': '18.0',
    'appVersion': version,
    'appBuildNumber': build,
    'deviceModel': 'Apple mobile device',
    'locale': 'en-US',
  };
}

void main() {
  test('new install: three automatic signals once, then the signal', () async {
    final h = session(FakeStorage());
    await h.send('first');
    await h.send('second');
    expect(h.allEvents.map((e) => e['type']), [
      'pulse.new_install',
      'pulse.session_started',
      'first',
      'second',
    ]);
    final system = systemOf(h.allEvents[2]);
    expect(system['isNewInstall'], 'true');
    expect(system['firstSessionDate'], '2026-11-13');
    expect(system['totalSessionsCount'], '1');
    expect(system['distinctDaysUsed'], '1');
    expect(system['distinctDaysUsedLastMonth'], '1');
    expect(system['sessionSeconds'], '0');
    expect(system.containsKey('previousSessionSeconds'), false);
    expect(system.containsKey('averageSessionSeconds'), false);
    expect(
      systemOf(h.allEvents[0]).containsKey('isNewInstall'),
      true,
      reason: 'the signal itself carries the statistics of its session',
    );
  });
  test('second session: previous and average, no install signals', () async {
    final storage = FakeStorage();
    final first = session(storage);
    await first.send('a');
    await first.advance(100);
    await first.send('b');
    final second = session(storage, at: DateTime.utc(2026, 11, 13, 14));
    await second.send('c');
    expect(second.allEvents.map((e) => e['type']), [
      'pulse.session_started',
      'c',
    ]);
    final system = systemOf(second.allEvents.last);
    expect(system['totalSessionsCount'], '2');
    expect(system['previousSessionSeconds'], '100');
    expect(system['averageSessionSeconds'], '100');
    expect(system['distinctDaysUsed'], '1');
    expect(system.containsKey('isNewInstall'), false);
    final third = session(storage, at: DateTime.utc(2026, 11, 13, 16));
    await third.send('d');
    final stats = systemOf(third.allEvents.last);
    expect(stats['totalSessionsCount'], '3');
    expect(stats['previousSessionSeconds'], '0');
    expect(stats['averageSessionSeconds'], '50');
  });
  test(
    'thirty minutes idle starts a new session in the same process',
    () async {
      final h = session(FakeStorage());
      await h.send('a');
      await h.advance(1800);
      await h.send('b');
      expect(
        h.allEvents.where((e) => e['type'] == 'pulse.session_started').length,
        2,
      );
      expect(systemOf(h.events.last)['totalSessionsCount'], '2');
      expect(systemOf(h.events.last)['previousSessionSeconds'], '0');
    },
  );
  test('a new day adds a distinct day, the same day does not', () async {
    final storage = FakeStorage();
    await session(storage).send('a');
    await session(storage, at: DateTime.utc(2026, 11, 13, 20)).send('b');
    final next = session(storage, at: DateTime.utc(2026, 11, 14, 9));
    await next.send('c');
    final system = systemOf(next.events.single);
    expect(system['distinctDaysUsed'], '2');
    expect(system['distinctDaysUsedLastMonth'], '2');
    expect(system['firstSessionDate'], '2026-11-13');
  });
  test(
    'the thirty day window drops old days, the lifetime counter keeps them',
    () async {
      final storage = FakeStorage();
      await session(storage).send('a');
      final later = session(storage, at: DateTime.utc(2026, 12, 23, 12));
      await later.send('b');
      final system = systemOf(later.events.single);
      expect(system['distinctDaysUsed'], '2');
      expect(system['distinctDaysUsedLastMonth'], '1');
      expect(system['totalSessionsCount'], '2');
      final edge = session(storage, at: DateTime.utc(2026, 12, 12, 12));
      await edge.send('c');
      expect(systemOf(edge.events.single)['distinctDaysUsedLastMonth'], '2');
    },
  );
  test('an app update is detected once with the previous version', () async {
    final storage = FakeStorage();
    await session(
      storage,
      environment: VersionEnvironment('1.0.0', '1'),
    ).send('a');
    final same = session(
      storage,
      at: DateTime.utc(2026, 11, 14),
      environment: VersionEnvironment('1.0.0', '1'),
    );
    await same.send('b');
    expect(same.allEvents.map((e) => e['type']), [
      'pulse.session_started',
      'b',
    ]);
    final updated = session(
      storage,
      at: DateTime.utc(2026, 11, 15),
      environment: VersionEnvironment('1.1.0', '2'),
    );
    await updated.send('c');
    final update = updated.allEvents.firstWhere(
      (e) => e['type'] == 'pulse.app_updated',
    );
    expect(update['props'], {'previousVersion': '1.0.0', 'previousBuild': '1'});
    expect(updated.allEvents.map((e) => e['type']), [
      'pulse.app_updated',
      'pulse.session_started',
      'c',
    ]);
    final after = session(
      storage,
      at: DateTime.utc(2026, 11, 16),
      environment: VersionEnvironment('1.1.0', '2'),
    );
    await after.send('d');
    expect(after.allEvents.any((e) => e['type'] == 'pulse.app_updated'), false);
  });
  test('a build number change alone counts as an update', () async {
    final storage = FakeStorage();
    await session(
      storage,
      environment: VersionEnvironment('1.0.0', '1'),
    ).send('a');
    final next = session(
      storage,
      at: DateTime.utc(2026, 11, 14),
      environment: VersionEnvironment('1.0.0', '2'),
    );
    await next.send('b');
    expect(next.allEvents.any((e) => e['type'] == 'pulse.app_updated'), true);
  });
  test('an install id without usage data is not a new install', () async {
    final storage = FakeStorage()..files['install-id'] = utf8.encode('a' * 32);
    final h = session(storage);
    await h.send('a');
    expect(h.allEvents.map((e) => e['type']), ['pulse.session_started', 'a']);
    final system = systemOf(h.events.single);
    expect(system.containsKey('isNewInstall'), false);
    expect(system['totalSessionsCount'], '1');
  });
  test('opt-out suppresses the signals and removes the usage file', () async {
    final storage = FakeStorage();
    final h = session(storage);
    await h.send('a');
    expect(storage.files.containsKey('usage'), true);
    await h.runtime.setOptOut(true);
    expect(storage.files.containsKey('usage'), false);
    expect(storage.files.containsKey('install-id'), false);
    final count = h.allEvents.length;
    h.runtime.track('blocked');
    await h.flush();
    expect(h.allEvents.length, count);
    expect(storage.files.containsKey('usage'), false);
  });
  test('opt-out then opt-in starts counting again as a new install', () async {
    final h = session(FakeStorage());
    await h.send('a');
    await h.runtime.setOptOut(true);
    await h.runtime.setOptOut(false);
    await h.send('b');
    final types = h.allEvents.map((e) => e['type']).toList();
    expect(types.where((t) => t == 'pulse.new_install').length, 2);
    expect(systemOf(h.events.last)['totalSessionsCount'], '1');
  });
  test('automatic signals carry the debug flag and respect it', () async {
    final h = session(FakeStorage(), options: const PulseOptions(debug: true));
    await h.send('a');
    expect(h.allEvents.map((e) => e['debug']), [true, true, true]);
  });
  test('unreadable and unwritable storage keeps counting in memory', () async {
    final storage = FakeStorage()..failing.addAll({'usage', 'install-id'});
    final h = session(storage);
    await h.send('a');
    await h.advance(1800);
    await h.send('b');
    expect(h.events.map((e) => e['type']), ['a', 'b']);
    expect(systemOf(h.events.last)['totalSessionsCount'], '2');
    expect(storage.files.containsKey('usage'), false);
  });
  test('a damaged usage file starts fresh and does not throw', () async {
    final storage = FakeStorage()
      ..files['install-id'] = utf8.encode('b' * 32)
      ..files['usage'] = utf8.encode('{not json');
    final h = session(storage);
    await h.send('a');
    expect(systemOf(h.events.single)['totalSessionsCount'], '1');
    expect(UsageStats.decode(storage.files['usage']!), isNotNull);
  });
  test('sessions started before initialize are counted once', () async {
    final h = Harness(initialize: false, automatic: true);
    h.runtime.track('early');
    h.runtime.track('early2');
    await h.runtime.initialize('synthetic-key');
    await h.flush();
    expect(h.allEvents.map((e) => e['type']), [
      'pulse.new_install',
      'pulse.session_started',
      'early',
      'early2',
    ]);
    expect(systemOf(h.events.first)['appVersion'], '1.2.3');
  });
  group('UsageStats', () {
    DateTime same(DateTime d) => d;
    test('round trips through the stored form', () {
      final stats = UsageStats(newInstall: true);
      stats.beginSession(DateTime.utc(2026, 11, 13, 12), same, '1', '2');
      stats.touch(DateTime.utc(2026, 11, 13, 12, 5));
      final copy = UsageStats.decode(stats.encode())!;
      expect(copy.total, 1);
      expect(copy.firstDate, '2026-11-13');
      expect(copy.openLast, DateTime.utc(2026, 11, 13, 12, 5));
      expect(copy.lastVersion, '1');
      expect(UsageStats.decode([1, 2, 3]), isNull);
    });
    test('durations older than 90 days leave the average', () {
      final stats = UsageStats();
      stats.beginSession(DateTime.utc(2026, 1, 1, 12), same, '1', '1');
      stats.touch(DateTime.utc(2026, 1, 1, 12, 10));
      stats.beginSession(DateTime.utc(2026, 1, 2, 12), same, '1', '1');
      expect(
        stats.fields(
          DateTime.utc(2026, 1, 2, 12),
          same,
        )['averageSessionSeconds'],
        '600',
      );
      stats.touch(DateTime.utc(2026, 1, 2, 12, 1));
      stats.beginSession(DateTime.utc(2026, 6, 1, 12), same, '1', '1');
      final fields = stats.fields(DateTime.utc(2026, 6, 1, 12), same);
      expect(fields['previousSessionSeconds'], '60');
      expect(fields.containsKey('averageSessionSeconds'), false);
    });
    test('saving is requested at most every 30 seconds of activity', () {
      final stats = UsageStats();
      final start = DateTime.utc(2026, 11, 13, 12);
      stats.beginSession(start, same, '1', '1');
      stats.markSaved();
      stats.touch(start.add(const Duration(seconds: 10)));
      expect(stats.dirty, false);
      stats.touch(start.add(const Duration(seconds: 31)));
      expect(stats.dirty, true);
    });
  });
}
