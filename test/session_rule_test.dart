import 'package:flutter_test/flutter_test.dart';
import 'support.dart';

/// A new session id starts when the next signal arrives 30 minutes or more after the previous signal.
List<Object?> ids(Harness h, String type) => [
  for (final e in h.allEvents)
    if (e['type'] == type) e['sessionId'],
];
int started(Harness h) =>
    h.allEvents.where((e) => e['type'] == 'pulse.session_started').length;
Harness auto([FakeStorage? storage, FakeTime? time]) =>
    Harness(storage: storage, time: time, automatic: true);

void main() {
  test('same id within 29 minutes and a new id at thirty', () async {
    final h = auto();
    await h.send('a');
    await h.advance(29 * 60 + 59);
    await h.send('b');
    expect({...ids(h, 'a'), ...ids(h, 'b')}.length, 1);
    await h.advance(30 * 60);
    await h.send('c');
    expect(ids(h, 'c').single, isNot(ids(h, 'b').single));
    expect(started(h), 2);
  });
  test('exactly thirty minutes rotates', () async {
    final h = auto();
    await h.send('a');
    await h.advance(30 * 60);
    await h.send('b');
    expect(ids(h, 'b').single, isNot(ids(h, 'a').single));
    expect(started(h), 2);
  });
  test('a 14 hour gap inside one running process rotates once', () async {
    final h = auto();
    await h.send('a');
    await h.advance(14 * 3600);
    await h.send('b');
    await h.send('c');
    expect(ids(h, 'b').single, isNot(ids(h, 'a').single));
    expect(ids(h, 'b'), ids(h, 'c'));
    expect(started(h), 2);
  });
  test(
    'restart after 31 minutes gives a new id and one session start',
    () async {
      final first = auto();
      await first.send('a');
      final second = auto(
        first.storage,
        FakeTime(first.time.now.add(const Duration(minutes: 31))),
      );
      await second.send('b');
      expect(ids(second, 'b').single, isNot(ids(first, 'a').single));
      expect(started(second), 1);
    },
  );
  test('flush and timers alone do not extend a session', () async {
    final h = auto();
    await h.send('a');
    for (var i = 0; i < 40; i++) {
      await h.advance(60);
      await h.flush();
      await h.runtime.backgroundSave();
    }
    await h.send('b');
    expect(ids(h, 'b').single, isNot(ids(h, 'a').single));
    expect(started(h), 2);
  });
  test(
    'idle is measured from the last signal, not the session start',
    () async {
      final h = auto();
      await h.send('a');
      await h.advance(20 * 60);
      await h.send('b');
      await h.advance(20 * 60);
      await h.send('c');
      expect({...ids(h, 'a'), ...ids(h, 'b'), ...ids(h, 'c')}.length, 1);
      await h.advance(40 * 60);
      await h.flush();
      await h.advance(5 * 60);
      await h.send('d');
      expect(ids(h, 'd').single, isNot(ids(h, 'c').single));
      expect(started(h), 2);
    },
  );
  test(
    'signals tracked before initialize use their own capture time',
    () async {
      final h = Harness(initialize: false, automatic: true);
      h.runtime.track('early1');
      await h.settle();
      h.time.advance(14 * 3600);
      h.runtime.track('early2');
      await h.settle();
      await h.runtime.initialize('synthetic-key');
      await h.flush();
      expect(ids(h, 'early2').single, isNot(ids(h, 'early1').single));
      expect(started(h), 2);
    },
  );
  test('dropped invalid signals neither start nor extend a session', () async {
    final h = auto();
    await h.send('a');
    for (var i = 0; i < 5; i++) {
      await h.advance(10 * 60);
      h.runtime.track('   ');
      h.runtime.track('bad', value: double.nan);
      await h.flush();
    }
    await h.send('b');
    expect(ids(h, 'b').single, isNot(ids(h, 'a').single));
    expect(started(h), 2);
    expect(h.events.length, 2);
  });
}
