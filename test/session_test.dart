import 'package:flutter_test/flutter_test.dart';
import 'package:mightys_pulse/src/core/capture.dart';
import 'package:mightys_pulse/src/core/ports.dart';

class Tokens implements PulseRandom {
  int counter = 0;
  @override
  String token() => 'token-${counter++}';
  @override
  double sample() => 0.5;
}

void main() {
  test('session rotates after 30 minutes and on new process', () {
    final random = Tokens();
    final capture = Capture(random);
    final now = DateTime.utc(2026);
    final first = capture.sessionAt(now);
    expect(capture.sessionAt(now.add(const Duration(minutes: 29))), first);
    expect(
      capture.sessionAt(now.add(const Duration(minutes: 59))),
      isNot(first),
    );
    expect(Capture(random).sessionAt(now), isNot(first));
  });
  test('setUser hashes once, empty and null clear', () {
    final capture = Capture(Tokens());
    capture.setUser('abc');
    expect(
      capture.userHash,
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    );
    capture.setUser('');
    expect(capture.userHash, isNull);
    capture.setUser('abc');
    capture.reset();
    expect(capture.userHash, isNull);
  });
}
