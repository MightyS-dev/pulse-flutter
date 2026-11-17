import 'package:flutter_test/flutter_test.dart';
import 'package:mightys_pulse/src/core/heatmap.dart';
import 'support.dart';

class _Rig {
  _Rig() {
    capture = HeatmapCapture(
      clock: time,
      enabled: () => enabled,
      sessionAt: (_) => session,
      emit: sent.add,
    );
  }
  final time = FakeTime();
  bool enabled = true;
  String session = 'pending';
  final sent = <Map<String, Object?>>[];
  late final HeatmapCapture capture;

  void tap(
    double x,
    double y, {
    double w = 400,
    double h = 800,
    bool keyboard = false,
    bool input = false,
    bool ignored = false,
  }) => capture.onTap(
    x,
    y,
    w,
    h,
    keyboardVisible: keyboard,
    inputTarget: input,
    ignored: ignored,
  );

  List<Map<String, Object?>> pointsOf(int signal) =>
      (sent[signal]['points']! as List<Object?>).cast<Map<String, Object?>>();
}

void main() {
  group('buckets and orientation', () {
    test('phone below 600, tablet below 1024, else desktop', () {
      expect(HeatmapCapture.bucketOf(599.9), 'phone');
      expect(HeatmapCapture.bucketOf(600), 'tablet');
      expect(HeatmapCapture.bucketOf(1023.9), 'tablet');
      expect(HeatmapCapture.bucketOf(1024), 'desktop');
    });
    test('portrait when height >= width, else landscape', () {
      expect(HeatmapCapture.orientationOf(400, 800), 'portrait');
      expect(HeatmapCapture.orientationOf(400, 400), 'portrait');
      expect(HeatmapCapture.orientationOf(800, 400), 'landscape');
    });
  });

  group('point math', () {
    test('x is a clamped fraction with 3 decimals, y has 1 decimal', () {
      final r = _Rig();
      r.capture.setScreen('Shop');
      r.tap(205.2, 340.04);
      r.tap(-5, 10);
      r.tap(900, 100050);
      r.capture.flush();
      expect(r.pointsOf(0), [
        {'x': 0.513, 'y': 340, 'kind': 'tap'},
        {'x': 0, 'y': 10, 'kind': 'tap'},
        {'x': 1, 'y': 100000, 'kind': 'tap'},
      ]);
    });
    test('y keeps one decimal and is clamped at 0', () {
      final r = _Rig();
      r.capture.setScreen('Shop');
      r.tap(100, 1210.46);
      r.tap(100, -4);
      r.capture.flush();
      expect(r.pointsOf(0).map((p) => p['y']), [1210.5, 0]);
    });
    test('non finite or empty geometry is ignored', () {
      final r = _Rig();
      r.capture.setScreen('Shop');
      r.tap(double.nan, 1);
      r.tap(1, double.infinity);
      r.tap(1, 1, w: 0);
      r.tap(1, 1, h: 0);
      r.capture.flush();
      expect(r.sent, isEmpty);
    });
    test('the signal object has screen, bucket, orientation, points', () {
      final r = _Rig();
      r.capture.setScreen('Shop');
      r.tap(10, 10);
      r.capture.flush();
      expect(r.sent.single.keys, ['screen', 'bucket', 'orientation', 'points']);
      expect(r.sent.single['screen'], 'Shop');
      expect(r.sent.single['bucket'], 'phone');
      expect(r.sent.single['orientation'], 'portrait');
    });
  });

  group('screen', () {
    test('no known screen means no capture', () {
      final r = _Rig();
      r.tap(10, 10);
      r.capture.flush();
      expect(r.sent, isEmpty);
      r.capture.setScreen('A');
      r.capture.setScreen(null);
      r.tap(10, 10);
      r.capture.flush();
      expect(r.sent, isEmpty);
    });
    test('a screen change sends the old buffer first', () {
      final r = _Rig();
      r.capture.setScreen('A');
      r.tap(10, 10);
      r.capture.setScreen('B');
      expect(r.sent.length, 1);
      expect(r.sent.single['screen'], 'A');
      r.tap(20, 20);
      r.capture.flush();
      expect(r.sent[1]['screen'], 'B');
    });
    test('the same screen again changes nothing', () {
      final r = _Rig();
      r.capture.setScreen('A');
      r.tap(10, 10);
      r.capture.setScreen('A');
      expect(r.sent, isEmpty);
    });
  });

  group('buffers', () {
    test('a bucket or orientation change sends the buffer', () {
      final r = _Rig();
      r.capture.setScreen('A');
      r.tap(10, 10);
      r.tap(10, 10, w: 800, h: 400);
      expect(r.sent.length, 1);
      expect(r.sent[0]['bucket'], 'phone');
      expect(r.sent[0]['orientation'], 'portrait');
      r.capture.flush();
      expect(r.sent[1]['bucket'], 'tablet');
      expect(r.sent[1]['orientation'], 'landscape');
    });
    test('empty buffers are never sent', () {
      final r = _Rig();
      r.capture.setScreen('A');
      r.capture.flush();
      r.capture.setScreen('B');
      r.capture.flush();
      expect(r.sent, isEmpty);
    });
    test('200 points split into a new buffer for the same visit', () {
      final r = _Rig();
      r.capture.setScreen('A');
      for (var i = 0; i < 250; i++) {
        r.tap((i * 7) % 400 + 0.0, (i * 50) % 800 + 0.0);
      }
      expect(r.sent.length, 1);
      expect(r.pointsOf(0).length, 200);
      r.capture.flush();
      expect(r.pointsOf(1).length, 50);
    });
    test('at most 1000 points per session, the rest is dropped', () {
      final r = _Rig();
      r.capture.setScreen('A');
      for (var i = 0; i < 1200; i++) {
        r.time.date = r.time.date.add(const Duration(seconds: 2));
        r.tap(10, 10);
      }
      r.capture.flush();
      final total = r.sent.fold<int>(
        0,
        (n, s) => n + (s['points']! as List<Object?>).length,
      );
      expect(total, 1000);
      r.session = 'next';
      r.tap(10, 10);
      r.capture.flush();
      expect((r.sent.last['points']! as List<Object?>).length, 1);
    });
    test('drop forgets the buffer without sending', () {
      final r = _Rig();
      r.capture.setScreen('A');
      r.tap(10, 10);
      r.capture.drop();
      r.capture.flush();
      expect(r.sent, isEmpty);
    });
  });

  group('rage', () {
    test('the 3rd tap within 1 s and 30 px is rage, earlier stay tap', () {
      final r = _Rig();
      r.capture.setScreen('A');
      r.tap(100, 100);
      r.time.date = r.time.date.add(const Duration(milliseconds: 300));
      r.tap(110, 105);
      r.time.date = r.time.date.add(const Duration(milliseconds: 300));
      r.tap(105, 110);
      r.time.date = r.time.date.add(const Duration(milliseconds: 300));
      r.tap(100, 100);
      r.capture.flush();
      expect(r.pointsOf(0).map((p) => p['kind']), [
        'tap',
        'tap',
        'rage',
        'rage',
      ]);
    });
    test('taps too slow or too far apart are plain taps', () {
      final r = _Rig();
      r.capture.setScreen('A');
      for (var i = 0; i < 4; i++) {
        r.tap(100, 100);
        r.time.date = r.time.date.add(const Duration(milliseconds: 600));
      }
      for (var i = 0; i < 4; i++) {
        r.tap(100.0 + i * 40, 300);
      }
      r.capture.flush();
      expect(r.pointsOf(0).where((p) => p['kind'] == 'rage'), isEmpty);
    });
    test('a new screen starts a new cluster', () {
      final r = _Rig();
      r.capture.setScreen('A');
      r.tap(100, 100);
      r.tap(100, 100);
      r.capture.setScreen('B');
      r.tap(100, 100);
      r.capture.flush();
      expect(r.pointsOf(1).single['kind'], 'tap');
    });
  });

  group('never capture and switches', () {
    test('keyboard, input target and ignore flag drop the tap', () {
      final r = _Rig();
      r.capture.setScreen('A');
      r.tap(10, 10, keyboard: true);
      r.tap(10, 10, input: true);
      r.tap(10, 10, ignored: true);
      r.capture.flush();
      expect(r.sent, isEmpty);
      r.tap(10, 10);
      r.capture.flush();
      expect(r.sent.length, 1);
    });
    test('switched off: taps are ignored and the buffer is dropped', () {
      final r = _Rig();
      r.capture.setScreen('A');
      r.tap(10, 10);
      r.enabled = false;
      r.tap(20, 20);
      r.enabled = true;
      r.capture.flush();
      expect(r.sent, isEmpty);
    });
    test('a throwing enabled check is off', () {
      final time = FakeTime();
      final sent = <Map<String, Object?>>[];
      final c = HeatmapCapture(
        clock: time,
        enabled: () => throw StateError('x'),
        sessionAt: (_) => 's',
        emit: sent.add,
      )..setScreen('A');
      c.onTap(
        1,
        1,
        400,
        800,
        keyboardVisible: false,
        inputTarget: false,
        ignored: false,
      );
      c.flush();
      expect(sent, isEmpty);
    });
    test('nothing is sent when the switch is off at send time', () {
      final r = _Rig();
      r.capture.setScreen('A');
      r.tap(10, 10);
      r.enabled = false;
      r.capture.flush();
      expect(r.sent, isEmpty);
    });
  });

  test('adoptSession lets the count follow the session that was created', () {
    final r = _Rig();
    r.capture.setScreen('A');
    r.tap(10, 10);
    r.capture.adoptSession('s1');
    r.session = 's1';
    r.tap(10, 10);
    r.capture.flush();
    expect(r.sent.length, 1);
  });
}
