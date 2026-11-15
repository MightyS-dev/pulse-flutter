import 'dart:async';
import 'dart:math';
import '../core/ports.dart';

class SystemClock implements PulseClock {
  @override
  DateTime get now => DateTime.now().toUtc();
}

class SystemScheduler implements PulseScheduler {
  @override
  Cancellation schedule(Duration delay, void Function() callback) =>
      _TimerCancellation(Timer(delay, callback));
}

class _TimerCancellation implements Cancellation {
  _TimerCancellation(this.timer);
  final Timer timer;
  @override
  void cancel() => timer.cancel();
}

class SecureRandom implements PulseRandom {
  final _random = Random.secure();
  @override
  String token() => List.generate(
    16,
    (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  @override
  double sample() => _random.nextDouble();
}
