import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:mightys_pulse/src/core/config.dart';
import 'package:mightys_pulse/src/core/options.dart';
import 'support.dart';

Map<String, Object?> errorOf(Map<String, Object?> event) =>
    event['error']! as Map<String, Object?>;

List<Map<String, Object?>> errorsOf(Harness h) =>
    h.allEvents.where((e) => e['type'] == 'pulse.error').toList();

final trace = StackTrace.fromString(
  '#0      Cart.checkout (package:shop/cart.dart:42:7)\n'
  '#1      main (package:shop/main.dart:3:1)\n',
);

void main() {
  test(
    'a handled error is one pulse.error signal with the error object',
    () async {
      final h = Harness();
      h.runtime.trackError(StateError('no mail jane@example.com'), trace, {
        'screen': 'cart',
      }, kind: 'handled');
      await h.flush();
      final events = errorsOf(h);
      expect(events, hasLength(1));
      final e = events.single;
      expect(e['props'], {'screen': 'cart'});
      expect(errorOf(e), {
        'kind': 'handled',
        'type': 'StateError',
        'message': 'Bad state: no mail <filtered>',
        'frames': ['Cart.checkout cart.dart:42', 'main main.dart:3'],
        'symbolicated': true,
      });
      expect(e.containsKey('value'), false);
      expect((e['system']! as Map).containsKey('platform'), true);
    },
  );

  test('typeOnly sends kind and type only', () async {
    final h = Harness(
      options: const PulseOptions(
        debug: false,
        errorDetail: ErrorDetail.typeOnly,
      ),
    );
    h.runtime.trackError(StateError('secret'), trace, null, kind: 'error');
    await h.flush();
    expect(errorOf(errorsOf(h).single), {
      'kind': 'error',
      'type': 'StateError',
    });
  });

  test('at most 10 per type per session, other types unaffected', () async {
    final h = Harness();
    for (var i = 0; i < 15; i++) {
      h.runtime.trackError(StateError('a$i'), trace, null, kind: 'error');
    }
    h.runtime.trackError(ArgumentError('b'), trace, null, kind: 'error');
    await h.flush();
    final types = errorsOf(h).map((e) => errorOf(e)['type']).toList();
    expect(types.where((t) => t == 'StateError'), hasLength(10));
    expect(types.where((t) => t == 'ArgumentError'), hasLength(1));
  });

  test('the count starts again in a new session', () async {
    final h = Harness();
    for (var i = 0; i < 12; i++) {
      h.runtime.trackError(StateError('a'), trace, null, kind: 'error');
    }
    await h.flush();
    expect(errorsOf(h), hasLength(10));
    await h.advance(3600);
    for (var i = 0; i < 12; i++) {
      h.runtime.trackError(StateError('a'), trace, null, kind: 'error');
    }
    await h.flush();
    expect(errorsOf(h), hasLength(20));
  });

  test('opt-out sends nothing and clears the queue', () async {
    final h = Harness();
    h.runtime.trackError(StateError('a'), trace, null, kind: 'error');
    unawaited(h.runtime.setOptOut(true));
    h.runtime.trackError(StateError('b'), trace, null, kind: 'error');
    await h.flush();
    expect(h.allEvents, isEmpty);
    expect(h.runtime.count, 0);
  });

  test('errors before initialize are kept and sent', () async {
    final h = Harness(initialize: false);
    h.runtime.trackError(StateError('early'), trace, null, kind: 'error');
    await h.settle();
    h.runtime.initialize('synthetic-key');
    await h.flush();
    expect(errorsOf(h), hasLength(1));
  });

  test(
    'automatic signal switches do not suppress it, field groups apply',
    () async {
      final storage = FakeStorage();
      storage.files['config'] = utf8.encode(
        jsonEncode({
          'version': 3,
          'screenViews': false,
          'automaticSignals': false,
          'groups': {for (final n in fieldGroups.keys) n: n != 'device'},
          'disabledSignals': ['pulse.session_started'],
        }),
      );
      final h = Harness(
        storage: storage,
        options: const PulseOptions(debug: false, automaticSignals: false),
      );
      h.runtime.trackError(StateError('a'), trace, null, kind: 'error');
      await h.flush();
      final e = errorsOf(h).single;
      expect((e['system']! as Map).containsKey('deviceType'), false);
      expect((e['system']! as Map)['platform'], isNotEmpty);
    },
  );

  test(
    'a failing storage never throws and the signal still goes out',
    () async {
      final storage = FakeStorage()..failing.addAll(['install-id', 'usage']);
      final h = Harness(storage: storage);
      h.runtime.trackError(StateError('a'), trace, null, kind: 'error');
      await h.flush();
      expect(errorsOf(h), hasLength(1));
    },
  );

  test('props that are not primitive are dropped, never thrown', () async {
    final h = Harness();
    h.runtime.trackError(StateError('a'), trace, {
      'ok': 'yes',
      'bad': [1],
    }, kind: 'handled');
    await h.flush();
    expect(errorsOf(h).single['props'], {'ok': 'yes'});
  });
}
