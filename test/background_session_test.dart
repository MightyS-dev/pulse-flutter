import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mightys_pulse/src/core/config.dart';
import 'package:mightys_pulse/src/core/options.dart';
import 'package:mightys_pulse/src/core/ports.dart';
import 'package:mightys_pulse/src/core/usage.dart';
import 'package:mightys_pulse/src/platform/lifecycle.dart';

import 'support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Harness launch({
    PulseConfig config = PulseConfig.defaults,
    PulseOptions options = const PulseOptions(debug: false),
    bool automatic = true,
  }) {
    final storage = FakeStorage()..files['config'] = config.encode();
    final h = Harness(storage: storage, options: options, automatic: automatic);
    addTearDown(h.runtime.close);
    return h;
  }

  PulseLifecycle observe(Harness h) {
    final life = PulseLifecycle(
      h.runtime.backgroundSave,
      onForeground: (cold) => h.runtime.appForeground(cold: cold),
      onBackground: h.runtime.appBackground,
      initialState: AppLifecycleState.resumed,
    )..start();
    addTearDown(life.dispose);
    return life;
  }

  List<Map<String, Object?>> backgrounds(Harness h) =>
      h.allEvents.where((e) => e['type'] == appBackgroundedType).toList();

  Map<String, Object?> system(Map<String, Object?> e) =>
      e['system']! as Map<String, Object?>;

  Harness restart(Harness h) {
    // A fresh process gets only the bytes already saved, without a clean close.
    final storage = FakeStorage();
    for (final entry in h.storage.files.entries) {
      storage.files[entry.key] = List.of(entry.value);
    }
    final next = Harness(
      storage: storage,
      time: FakeTime(h.time.now.add(const Duration(minutes: 5))),
      automatic: true,
    );
    addTearDown(next.runtime.close);
    return next;
  }

  for (final states in [
    [AppLifecycleState.hidden, AppLifecycleState.paused],
    [AppLifecycleState.paused, AppLifecycleState.hidden],
  ]) {
    test('background $states sends once and flushes immediately', () async {
      final h = launch();
      final life = observe(h);
      await h.send('start');
      await h.advance(5);
      await h.send('activity');
      // Still before the regular 20 second flush interval after activity.
      await h.advance(7);
      final before = h.transport.requests.length;
      for (final state in states) {
        life.didChangeAppLifecycleState(state);
      }
      await h.settle();
      expect(h.transport.requests, hasLength(before + 1));
      final event = backgrounds(h).single;
      expect(event['props'], {'foregroundSeconds': 12});
      expect(system(event)['sessionSeconds'], '12');
      expect(event['sessionId'], h.events.first['sessionId']);
      expect(h.runtime.count, 0);
      expect(h.allEvents.where((e) => e['type'] == appOpenedType), isEmpty);
      expect(
        UsageStats.decode(h.storage.files['usage']!)!.openLast,
        h.time.now,
      );

      final next = restart(h);
      await next.send('next');
      final first = next.allEvents.first;
      expect(first['type'], sessionStartedType);
      expect(system(first)['previousSessionSeconds'], '12');
      expect(system(first)['averageSessionSeconds'], '12');
    });
  }

  test('a real resume allows the next background exactly once', () async {
    final h = launch();
    final life = observe(h);
    await h.send('start');
    await h.advance(10);
    life.didChangeAppLifecycleState(AppLifecycleState.hidden);
    life.didChangeAppLifecycleState(AppLifecycleState.paused);
    await h.settle();
    await h.advance(5);
    life.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await h.advance(3);
    life.didChangeAppLifecycleState(AppLifecycleState.hidden);
    life.didChangeAppLifecycleState(AppLifecycleState.paused);
    await h.settle();
    expect(backgrounds(h).map((e) => e['props']), [
      {'foregroundSeconds': 10},
      {'foregroundSeconds': 3},
    ]);
    expect(backgrounds(h).map((e) => system(e)['sessionSeconds']), [
      '10',
      '18',
    ]);
  });

  final switches =
      <String, ({PulseConfig config, PulseOptions options, bool automatic})>{
        'disabledSignals wins over enabledSignals': (
          config: const PulseConfig(
            enabledSignals: {appBackgroundedType},
            disabledSignals: {appBackgroundedType},
          ),
          options: const PulseOptions(debug: false),
          automatic: true,
        ),
        'pausedSignals': (
          config: const PulseConfig(pausedSignals: {appBackgroundedType}),
          options: const PulseOptions(debug: false),
          automatic: true,
        ),
        'portal automaticSignals': (
          config: const PulseConfig(automaticSignals: false),
          options: const PulseOptions(debug: false),
          automatic: true,
        ),
        'code automaticSignals': (
          config: PulseConfig.defaults,
          options: const PulseOptions(debug: false, automaticSignals: false),
          automatic: true,
        ),
        'runtime automaticSignals': (
          config: PulseConfig.defaults,
          options: const PulseOptions(debug: false),
          automatic: false,
        ),
      };
  for (final entry in switches.entries) {
    test('${entry.key} stops the signal but saves the session end', () async {
      final h = launch(
        config: entry.value.config,
        options: entry.value.options,
        automatic: entry.value.automatic,
      );
      observe(h);
      await h.send('start');
      await h.advance(12);
      // Check persistence without the lifecycle save or any signal admission.
      h.runtime.appBackground();
      await h.settle();
      expect(backgrounds(h), isEmpty);
      expect(
        UsageStats.decode(h.storage.files['usage']!)!.openLast,
        h.time.now,
      );
      final next = restart(h);
      await next.send('next');
      expect(system(next.allEvents.first)['previousSessionSeconds'], '12');
    });
  }

  for (final seconds in [1799, 1800, 1801, 3600]) {
    test(
      'background after $seconds seconds preserves the quiet rule',
      () async {
        final h = launch();
        final life = observe(h);
        await h.send('start');
        await h.advance(seconds.toDouble());
        life.didChangeAppLifecycleState(AppLifecycleState.hidden);
        await h.settle();
        expect(backgrounds(h), hasLength(seconds < 1800 ? 1 : 0));
        expect(
          h.allEvents.where((e) => e['type'] == sessionStartedType),
          hasLength(1),
        );
        expect(
          UsageStats.decode(h.storage.files['usage']!)!.openLast,
          h.time.now,
        );
        if (seconds >= 1800) {
          await h.send('later');
          expect(
            h.events.last['sessionId'],
            isNot(h.events.first['sessionId']),
          );
          expect(system(h.events.last)['previousSessionSeconds'], '$seconds');
        }
      },
    );
  }

  test(
    'background without a session saves counters and never creates one',
    () async {
      final h = launch();
      final life = observe(h);
      await h.settle();
      await h.advance(12);
      life.didChangeAppLifecycleState(AppLifecycleState.hidden);
      await h.settle();
      expect(h.allEvents, isEmpty);
      final usage = UsageStats.decode(h.storage.files['usage']!)!;
      expect(usage.openStart, isNull);
      expect(usage.total, 0);
      expect(usage.previousForeground, 12);
    },
  );

  test(
    'a launch with no signals does not extend the previous session',
    () async {
      final h = launch();
      final life = observe(h);
      await h.send('start');
      await h.advance(12);
      life.didChangeAppLifecycleState(AppLifecycleState.hidden);
      await h.settle();
      final next = restart(h);
      final nextLife = observe(next);
      await next.advance(12);
      nextLife.didChangeAppLifecycleState(AppLifecycleState.hidden);
      await next.settle();
      expect(next.allEvents, isEmpty);
      final last = restart(next);
      await last.send('next');
      expect(system(last.allEvents.first)['previousSessionSeconds'], '12');
    },
  );

  test(
    'default background cap is 20 and later backgrounds still save the end',
    () async {
      final h = launch();
      final life = observe(h);
      await h.send('start');
      for (var i = 0; i < 22; i++) {
        await h.advance(5);
        life.didChangeAppLifecycleState(AppLifecycleState.hidden);
        life.didChangeAppLifecycleState(AppLifecycleState.paused);
        await h.settle();
        life.didChangeAppLifecycleState(AppLifecycleState.resumed);
      }
      expect(backgrounds(h), hasLength(20));
      expect(
        UsageStats.decode(h.storage.files['usage']!)!.openLast,
        h.time.now,
      );
      final next = restart(h);
      await next.send('next');
      expect(system(next.allEvents.first)['previousSessionSeconds'], '110');
    },
  );

  for (final stalled in [false, true]) {
    test(
      'background survives ${stalled ? 'unfinished' : 'failed'} flush with original timestamp',
      () async {
        final h = launch();
        final life = observe(h);
        await h.send('start');
        await h.advance(12);
        final response = Completer<PulseResponse>();
        h.transport.handler = (_) => stalled
            ? response.future
            : Future<PulseResponse>.error(StateError('offline'));
        final before = h.transport.requests.length;
        life.didChangeAppLifecycleState(AppLifecycleState.hidden);
        life.didChangeAppLifecycleState(AppLifecycleState.paused);
        await h.settle();
        expect(h.transport.requests, hasLength(before + 1));
        expect(h.runtime.count, 1);
        final original = backgrounds(h).single;
        expect(DateTime.parse(original['timestamp']! as String), h.time.now);
        expect(system(original)['sessionSeconds'], '12');
        final next = restart(h);
        await next.send('next');
        expect(backgrounds(next).single, original);
        expect(
          next.transport.requests.first.body,
          h.transport.requests.last.body,
        );
        expect(
          next.transport.requests.first.batchId,
          h.transport.requests.last.batchId,
        );
        final started = next.allEvents.firstWhere(
          (e) => e['type'] == sessionStartedType,
        );
        expect(system(started)['previousSessionSeconds'], '12');
        expect(next.runtime.count, 0);
        if (stalled) response.complete(const PulseResponse(202));
      },
    );
  }
}
