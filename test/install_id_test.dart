import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:mightys_pulse/src/core/model.dart';
import 'support.dart';

String storedId(FakeStorage storage) =>
    utf8.decode(storage.files['install-id']!);

void main() {
  contextTests();
  test(
    'install id is created once and reused after re-initialization',
    () async {
      final first = Harness();
      await first.send();
      final id = storedId(first.storage);
      expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(id), true);
      final second = Harness(storage: first.storage);
      await second.send();
      expect(storedId(second.storage), id);
      expect(second.events.single['userHash'], hashText(id));
    },
  );
  test(
    'userHash is present without setUser and hashes the install id',
    () async {
      final h = Harness();
      await h.send('one');
      await h.send('two');
      final id = storedId(h.storage);
      expect(h.events.map((e) => e['userHash']), [hashText(id), hashText(id)]);
    },
  );
  test('signals tracked before initialize carry the install id hash', () async {
    final h = Harness(initialize: false);
    h.runtime.track('early');
    await h.runtime.initialize('synthetic-key');
    await h.flush();
    expect(h.events.single['userHash'], hashText(storedId(h.storage)));
  });
  test('setUser overrides and setUser(null) restores the install id', () async {
    final h = Harness();
    await h.send('anonymous');
    h.runtime.setUser('own-user');
    await h.send('named');
    h.runtime.setUser(null);
    await h.send('again');
    final id = storedId(h.storage);
    expect(h.events.map((e) => e['userHash']), [
      hashText(id),
      hashText('own-user'),
      hashText(id),
    ]);
  });
  test(
    'opt-out deletes the id and opt-out off creates a different one',
    () async {
      final h = Harness();
      await h.send();
      final id = storedId(h.storage);
      await h.runtime.setOptOut(true);
      expect(h.storage.files.containsKey('install-id'), false);
      await h.runtime.setOptOut(false);
      expect(h.storage.files.containsKey('install-id'), false);
      await h.send('later');
      final next = storedId(h.storage);
      expect(next, isNot(id));
      expect(h.events.last['userHash'], hashText(next));
    },
  );
  test('unreadable storage still gives a userHash from a process id', () async {
    final storage = FakeStorage()..failing.add('install-id');
    final h = Harness(storage: storage);
    await h.send('a');
    await h.send('b');
    final hashes = h.events.map((e) => e['userHash']).toSet();
    expect(storage.files.containsKey('install-id'), false);
    expect(hashes.length, 1);
    expect(hashes.single, isNotNull);
  });
  test('system fields are non-empty with the test environment', () async {
    final h = Harness();
    await h.send();
    final system = h.events.single['system']! as Map<String, Object?>;
    for (final field in [
      'platform',
      'osName',
      'osVersion',
      'appVersion',
      'deviceModel',
      'locale',
    ]) {
      expect(system[field], isNotEmpty, reason: field);
    }
  });
}

Future<void> pump() async {
  for (var i = 0; i < 60; i++) {
    await Future<void>.value();
  }
}

void contextTests() {
  Map<String, Object?> systemOf(Harness h) =>
      h.events.first['system']! as Map<String, Object?>;
  test(
    'first signals wait for a slow environment and carry full context',
    () async {
      final gate = Completer<void>();
      final h = Harness(environment: FakeEnvironment(gate: gate.future));
      h.runtime.track('app.open');
      unawaited(h.runtime.flush());
      await pump();
      expect(h.transport.requests, isEmpty);
      gate.complete();
      await h.settle();
      final system = systemOf(h);
      expect(system['osVersion'], '18.0');
      expect(system['deviceModel'], 'Apple mobile device');
      expect(system['appVersion'], '1.2.3');
    },
  );
  test('a stuck environment is abandoned after a bounded wait', () async {
    final h = Harness(
      environment: FakeEnvironment(gate: Completer<void>().future),
    );
    h.runtime.track('app.open');
    unawaited(h.runtime.flush());
    await pump();
    expect(h.transport.requests, isEmpty);
    h.time.advance(3);
    await h.settle();
    expect(h.events.map((e) => e['type']), ['app.open']);
    expect(systemOf(h)['osVersion'], '');
  });
}
