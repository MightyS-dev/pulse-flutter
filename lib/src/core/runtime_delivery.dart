part of 'runtime.dart';

extension _Delivery on PulseRuntime {
  Future<Batch> _makeBatch(Iterable<Entry> source, {bool plain = false}) =>
      computation.batch(
        _queue.select(_options.maxBatchSize, source),
        !plain && _options.gzip && !_gzipDisabled,
        compression,
      );

  Future<void> _pump() async {
    _timer?.cancel();
    _timer = null;
    if (_closed) {
      return;
    }
    if (clock.now.isBefore(_storageRetryAt)) {
      _schedule(_storageRetryAt);
      return;
    }
    await _persistPreference(_revision);
    if (_dirty != null || !await _load()) {
      _schedule(_storageRetryAt);
      return;
    }
    _prune();
    if (!await _persist()) {
      _schedule(_storageRetryAt);
      return;
    }
    _completeWaiters();
    if (_optOut ||
        _halted ||
        _key == null ||
        _queue.entries.isEmpty ||
        _active) {
      return;
    }
    if (clock.now.isBefore(_pauseUntil)) {
      _schedule(_pauseUntil);
      return;
    }
    if (_queue.pending.isEmpty) {
      if (!_forced &&
          _waiters.isEmpty &&
          _queue.entries.length < _options.maxBatchSize &&
          clock.now.isBefore(_nextFlush)) {
        _schedule(_nextFlush);
        return;
      }
      _queue.pending.add(await _makeBatch(_queue.entries));
    }
    final batch = _queue.pending.first;
    if (clock.now.isBefore(batch.retryAt)) {
      _schedule(batch.retryAt);
      return;
    }
    if (!await _persist()) {
      _schedule(_storageRetryAt);
      return;
    }
    // A privacy change may have arrived during the asynchronous save.
    if (_optOut || _closed) {
      return;
    }
    final epoch = ++_activeEpoch;
    _active = true;
    final request = PulseRequest(_endpoint!, _key!, batch.wire, batch.gzip);
    try {
      unawaited(
        transport
            .send(request)
            .then(
              (response) {
                _enqueue(() => _received(response, epoch));
              },
              onError: (Object error, StackTrace stack) {
                _enqueue(() => _received(const PulseResponse(0), epoch));
              },
            ),
      );
    } catch (_) {
      _active = false;
      await _received(const PulseResponse(0), epoch);
    }
  }

  Future<void> _received(PulseResponse response, int epoch) async {
    if (epoch != _activeEpoch || _queue.pending.isEmpty || _closed) {
      return;
    }
    _active = false;
    if (_optOut) {
      await _pump();
      return;
    }
    final batch = _queue.pending.first, status = response.status;
    if (status >= 200 && status < 300) {
      final ids = batch.ids.toSet();
      _queue.entries.removeWhere((e) => ids.contains(e.id));
      _queue.pending.removeAt(0);
      _applyAdvice(response.body);
      _nextFlush = clock.now.add(PulseRuntime._seconds(_interval));
    } else if ((status == 415 || status == 413) && batch.gzip) {
      if (status == 415) {
        _gzipDisabled = true;
      }
      batch.usePlain(clock.now);
    } else if (status == 401) {
      _halted = true;
      _warn('Application key rejected; sending stopped until restart.');
    } else if (status == 400 || status == 413) {
      await _isolate(batch);
    } else {
      _backoff(batch, response);
    }
    if (_queue.entries.isEmpty) {
      _forced = false;
    }
    await _pump();
  }

  Future<void> _isolate(Batch batch) async {
    _queue.pending.removeAt(0);
    final ids = batch.ids.toSet();
    final members = _queue.entries.where((e) => ids.contains(e.id)).toList();
    if (members.length > 1) {
      final half = members.length ~/ 2;
      _queue.pending.insertAll(0, [
        await _makeBatch(members.take(half), plain: true),
        await _makeBatch(members.skip(half), plain: true),
      ]);
    } else {
      _queue.entries.removeWhere((e) => ids.contains(e.id));
      _warn('Invalid signal dropped after isolation.');
    }
  }

  void _backoff(Batch batch, PulseResponse response) {
    final exponential = math.min(
      300.0,
      math.pow(2, math.min(9, batch.failures)).toDouble(),
    );
    batch.failures = math.min(1000000, batch.failures + 1);
    final sample = random.sample();
    final jitter = sample.isFinite ? sample.clamp(0.0, 1.0) : 0.5;
    final seconds = (exponential * (0.5 + jitter)).clamp(1.0, 300.0);
    var deadline = clock.now.add(PulseRuntime._seconds(seconds));
    final after = retryAfter(response.retryAfter, clock.now);
    if (after != null && after.isAfter(deadline)) {
      deadline = after;
    }
    if ((response.status == 429 || response.status == 503) &&
        _applyAdvice(response.body)) {
      final advised = clock.now.add(PulseRuntime._seconds(_interval));
      if (advised.isAfter(deadline)) {
        deadline = advised;
      }
    }
    batch.retryAt = deadline;
  }

  bool _applyAdvice(String body) {
    final advice = Advice.parse(body);
    if (advice == null) {
      return false;
    }
    if (advice.interval != null) {
      _interval = advice.interval!;
    }
    if (advice.pause != null) {
      _pauseUntil = advice.pause!
          ? clock.now.add(PulseRuntime._seconds(_interval))
          : DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    }
    return advice.interval != null;
  }
}
