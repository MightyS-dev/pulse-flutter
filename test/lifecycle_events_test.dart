import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mightys_pulse/src/platform/lifecycle.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ({PulseLifecycle life, List<String> calls}) make({
    AppLifecycleState? initial = AppLifecycleState.resumed,
  }) {
    final calls = <String>[];
    final life = PulseLifecycle(
      () async => calls.add('save'),
      onForeground: (cold) => calls.add(cold ? 'fg-cold' : 'fg'),
      onBackground: () => calls.add('bg'),
      initialState: initial,
    );
    addTearDown(life.dispose);
    return (life: life, calls: calls);
  }

  test('starting in the foreground is the cold start, reported by start()', () {
    final t = make();
    t.life.start();
    expect(t.calls, ['fg-cold']);
    t.life.start();
    expect(t.calls, ['fg-cold']);
  });

  test('resumed after a background is a warm foreground', () async {
    final t = make()..life.start();
    t.life.didChangeAppLifecycleState(AppLifecycleState.inactive);
    t.life.didChangeAppLifecycleState(AppLifecycleState.paused);
    t.life.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await Future<void>.value();
    expect(t.calls, ['fg-cold', 'bg', 'save', 'fg']);
  });

  test('repeated and transient states are not transitions', () async {
    final t = make()..life.start();
    t.life.didChangeAppLifecycleState(AppLifecycleState.resumed);
    t.life.didChangeAppLifecycleState(AppLifecycleState.inactive);
    t.life.didChangeAppLifecycleState(AppLifecycleState.paused);
    t.life.didChangeAppLifecycleState(AppLifecycleState.hidden);
    t.life.didChangeAppLifecycleState(AppLifecycleState.detached);
    await Future<void>.value();
    expect(t.calls.where((c) => c == 'bg'), hasLength(1));
    expect(t.calls.where((c) => c.startsWith('fg')), hasLength(1));
  });

  test(
    'an app that starts in the background gets its cold start on resume',
    () {
      final t = make(initial: AppLifecycleState.paused)..life.start();
      expect(t.calls, isEmpty);
      t.life.didChangeAppLifecycleState(AppLifecycleState.resumed);
      t.life.didChangeAppLifecycleState(AppLifecycleState.paused);
      t.life.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(t.calls.where((c) => c.startsWith('fg')), ['fg-cold', 'fg']);
    },
  );

  test('a failing callback never reaches the host', () {
    final life = PulseLifecycle(
      () async {},
      onForeground: (_) => throw StateError('x'),
      onBackground: () => throw StateError('y'),
      initialState: AppLifecycleState.resumed,
    );
    addTearDown(life.dispose);
    life.start();
    life.didChangeAppLifecycleState(AppLifecycleState.paused);
    life.didChangeAppLifecycleState(AppLifecycleState.resumed);
  });
}
