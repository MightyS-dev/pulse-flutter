import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:mightys_pulse/src/core/error_payload.dart';
import 'package:mightys_pulse/src/core/options.dart';

const dartTrace = '''
#0      Cart.checkout (package:shop/cart/cart.dart:42:7)
#1      main.<anonymous closure> (file:///srv/work/shop/main.dart:10:3)
#2      _rootRunUnary (dart:async/zone.dart:1407:47)
<asynchronous suspension>
#3      Item.load (package:shop/item.dart)
''';

const splitTrace = '''
*** *** *** *** *** *** *** *** *** *** *** *** *** *** *** ***
pid: 4242, tid: 4243, name 1.ui
build_id: 'abcdef0123456789'
isolate_dso_base: 723f000000, vm_dso_base: 723f000000
#00 abs 000000723f3b4abb virt 00000000003b4abb _kDartIsolateSnapshotInstructions+0x1a2
#01 abs 000000723f3b5000 virt 00000000003b5000 _kDartIsolateSnapshotInstructions+0x300
''';

void main() {
  test('Dart frames become Function file.dart:42', () {
    final r = ErrorPayload.frames(dartTrace);
    expect(r.frames, [
      'Cart.checkout cart.dart:42',
      'main.<anonymous closure> main.dart:10',
      '_rootRunUnary zone.dart:1407',
      'Item.load item.dart',
    ]);
    expect(r.symbolicated, true);
  });

  test('split debug info frames stay raw and are not symbolicated', () {
    final r = ErrorPayload.frames(splitTrace);
    expect(r.symbolicated, false);
    expect(r.frames, hasLength(2));
    expect(
      r.frames.first,
      '#00 abs 000000723f3b4abb virt 00000000003b4abb _kDartIsolateSnapshotInstructions+0x1a2',
    );
  });

  test('from(): type, filtered message, frames, kind', () {
    final e = ErrorPayload.from(
      'handled',
      StateError('bad mail jane@example.com'),
      StackTrace.fromString(dartTrace),
      ErrorDetail.full,
    );
    expect(e['kind'], 'handled');
    expect(e['type'], 'StateError');
    expect(e['message'], 'Bad state: bad mail <filtered>');
    expect((e['frames']! as List).first, 'Cart.checkout cart.dart:42');
    expect(e['symbolicated'], true);
  });

  test('no stack gives an empty frame list', () {
    final e = ErrorPayload.from('error', 'boom', null, ErrorDetail.full);
    expect(e['type'], 'String');
    expect(e['frames'], isEmpty);
  });

  test('frames of this package at the top are dropped', () {
    final stack = StackTrace.fromString(
      '#0 PulseClient.trackError (package:mightys_pulse/src/client.dart:1:1)\n'
      '#1 Pulse.trackError (package:mightys_pulse/mightys_pulse.dart:2:2)\n'
      '#2 Cart.checkout (package:shop/cart.dart:5:1)\n',
    );
    final e = ErrorPayload.from('handled', 'x', stack, ErrorDetail.full);
    expect(e['frames'], ['Cart.checkout cart.dart:5']);
  });

  test(
    'limits: 30 frames, 300 chars each, 500 char message, 200 char type',
    () {
      final trace = List.generate(
        60,
        (i) => '#$i      f$i (package:a/${'x' * 400}.dart:$i:1)',
      ).join('\n');
      final e = ErrorPayload.build(
        kind: 'error',
        type: 'T' * 300,
        message: 'm' * 900,
        frames: ErrorPayload.frames(trace).frames,
        symbolicated: true,
      );
      final frames = e['frames']! as List;
      expect(frames, hasLength(30));
      expect(frames.every((f) => (f as String).length <= 300), true);
      expect((e['message']! as String).length, 500);
      expect((e['type']! as String).length, 200);
    },
  );

  test('16384 bytes: frames are trimmed from the bottom, then the message', () {
    final big = List.generate(30, (i) => '${'é' * 295}$i');
    final e = ErrorPayload.build(
      kind: 'error',
      type: 'T',
      message: 'm' * 500,
      frames: big,
      symbolicated: true,
    );
    expect(utf8.encode(jsonEncode(e)).length, lessThanOrEqualTo(16384));
    final frames = e['frames']! as List;
    expect(frames.length, lessThan(30));
    expect(frames.first, big.first);
    expect(e['message'], 'm' * 500);
    final huge = ErrorPayload.fit({
      'kind': 'error',
      'type': 'T',
      'message': 'é' * 9000,
      'frames': <String>[],
      'symbolicated': true,
    });
    expect(utf8.encode(jsonEncode(huge)).length, lessThanOrEqualTo(16384));
    expect((huge['message']! as String).isNotEmpty, true);
  });

  test('typeOnly keeps kind and type only', () {
    final e = ErrorPayload.from(
      'error',
      StateError('secret'),
      StackTrace.fromString(dartTrace),
      ErrorDetail.typeOnly,
    );
    expect(e, {'kind': 'error', 'type': 'StateError'});
  });

  test('a frame with a path keeps the file name and line only', () {
    final e = ErrorPayload.build(
      kind: 'error',
      type: 'T',
      message: null,
      frames: ['go /srv/app/lib/go.dart:7'],
      symbolicated: true,
    );
    expect(e['frames'], ['go go.dart:7']);
  });
}
