import 'package:flutter_test/flutter_test.dart';
import 'support.dart';

/// Flush with nothing to deliver completes at once.
Future<void> completes(Harness h) async {
  await h.settle();
  await h.runtime.flush().timeout(const Duration(milliseconds: 100));
}

void main() {
  test('flush on an empty queue completes at once', () async {
    await completes(Harness());
  });
  test('flush after everything was delivered completes at once', () async {
    final h = Harness();
    await h.send('a');
    expect(h.transport.requests, isNotEmpty);
    await completes(h);
  });
  test('flush before initialize completes at once', () async {
    await completes(Harness(initialize: false));
  });
  test(
    'flush on an empty queue completes at once when storage fails',
    () async {
      final storage = FakeStorage()
        ..failReads = true
        ..failWrites = true;
      await completes(Harness(storage: storage));
    },
  );
}
