import 'dart:async';
import 'dart:convert';
import 'control_decision.dart';
import 'control_local.dart';
import 'control_rules.dart';
import 'control_state.dart';
import 'control_state_builder.dart';
import 'control_version.dart';
import 'model.dart';
import 'ports.dart';

/// Implemented by a backend that has App Control.
abstract interface class ControlBackend {
  ControlClient get control;
}

/// App Control: reads the rules the app owner set in the portal and keeps the
/// current [ControlState]. It never blocks `initialize`, never retries in a
/// loop and treats every failure as "keep the last known state, or normal".
class ControlClient {
  ControlClient({
    required this.clock,
    required this.scheduler,
    required this.storage,
    required this.transport,
    this.localTime = _systemLocal,
  });
  final PulseClock clock;
  final PulseScheduler scheduler;
  final PulseStorage storage;
  final PulseTransport transport;
  final DateTime Function(DateTime) localTime;
  static DateTime _systemLocal(DateTime value) => value.toLocal();

  static const _minInterval = Duration(seconds: 60);
  static const _deadline = Duration(seconds: 5);
  static const _maxTimer = Duration(hours: 1);
  static const _hour = Duration(hours: 1);

  /// The state to show right now. [ControlState.normal] until the rules say
  /// otherwise.
  ControlState get state => _state;
  ControlState _state = ControlState.normal;

  /// Languages in order of preference (the app's first, then the system's).
  List<String> Function() languageTags = () => const ['en'];

  /// The store page the platform can build when the rules carry none.
  String? fallbackStoreUrl;

  /// Whether the app can open a store link. Without a way to open it a
  /// required update is only a suggestion.
  bool Function() canOpenStore = () => true;

  final _listeners = <void Function(ControlState)>[];
  _Config? _config;
  ControlRules? _rules;
  List<int>? _body;
  String? _etag;
  int _savedAt = 0;
  bool _freshThisRun = false, _booted = false;
  var _local = const ControlLocal();
  DateTime? _lastCheckAt;
  Object? _requestToken;
  bool _askAgain = false;
  Cancellation? _watchdog, _timer;
  final _continued = <String>{};

  /// Called for every change of [state].
  void addListener(void Function(ControlState) listener) {
    if (!_listeners.contains(listener)) _listeners.add(listener);
  }

  /// Stops calling [listener].
  void removeListener(void Function(ControlState) listener) =>
      _listeners.remove(listener);

  /// Checks the rules now, without waiting for the next return to the
  /// foreground. Does nothing when App Control is off.
  void checkNow() {
    _guard(() {
      if (_config != null && _booted) _fetch(askAgain: true);
    });
  }

  /// Lets the user leave the current state, where the state allows it: a
  /// suggestion is not shown again for 24 hours, a card is marked as shown, a
  /// screen with [ControlState.allowContinue] is left until the app restarts.
  /// Locking screens without it ignore the call.
  void dismiss() {
    _guard(() {
      final c = _config;
      if (c == null || !_booted) return;
      final current = _state;
      if (!current.isActive ||
          (!current.allowContinue &&
              current.kind != ControlKind.updateSuggested)) {
        return;
      }
      switch (current.kind) {
        case ControlKind.updateSuggested:
          _saveLocal(
            _local.copyWith(
              dismissedVersion: c.appVersion,
              dismissedAt: clock.now.millisecondsSinceEpoch,
            ),
          );
        case ControlKind.announcement:
          final id = _rules?.announcement?.id;
          if (id != null) {
            final next = [..._local.shownAnnouncements, id];
            _saveLocal(
              _local.copyWith(
                shownAnnouncements: next.length > ControlLocal.maxIds
                    ? next.sublist(next.length - ControlLocal.maxIds)
                    : next,
              ),
            );
          }
        case ControlKind.whatsNew:
          _saveLocal(_local.copyWith(whatsNewShown: current.version));
        default:
          _continued.add(current.kind.name);
      }
      _evaluate();
    });
  }

  /// Remembers that the user pressed Update, so a return on the same version
  /// can be counted (the loop guard).
  void noteUpdatePressed() {
    _guard(() {
      final c = _config;
      if (c == null || !_booted) return;
      _saveLocal(_local.copyWith(pressPending: c.appVersion));
    });
  }

  /// Decides again with the latest outside facts (for example a store opener
  /// that was set after start).
  void reevaluate() => _guard(() {
    if (_config != null && _booted) _evaluate();
  });

  /// The app came to the foreground: counts a return from the store, re-reads
  /// the clock rules and checks at most once a minute.
  void onForeground() {
    _guard(() {
      if (_config == null || !_booted) return;
      _settlePress();
      _evaluate();
      final last = _lastCheckAt;
      final now = clock.now;
      if (last == null ||
          now.difference(last) >= _minInterval ||
          last.isAfter(now)) {
        _fetch();
      }
    });
  }

  /// Starts the checks and returns at once; the cache is read and the first
  /// request is made in the background. A mode of [ControlMode.off] does
  /// nothing at all.
  void start({
    required String key,
    required Uri signalsUrl,
    required ControlMode mode,
    required String appVersion,
    required String appName,
    required String sdk,
    required String platform,
    required bool debug,
  }) {
    try {
      if (mode == ControlMode.off || _config != null) return;
      final url = signalsUrl.replace(
        path:
            signalsUrl.path.replaceFirst(RegExp(r'signals$'), 'control/') +
            ControlIds.forKey(key),
      );
      final hash = hashText(key).substring(0, 16);
      final c = _Config(
        url,
        'control-$hash',
        'control-local-$hash',
        appVersion,
        appName,
        sdk,
        platform,
        debug,
      );
      _config = c;
      unawaited(_boot(c));
    } catch (_) {
      _config = null;
    }
  }

  /// Cancels the timers and forgets the app.
  void stop() {
    _watchdog?.cancel();
    _watchdog = null;
    _timer?.cancel();
    _timer = null;
    _requestToken = null;
    _config = null;
  }

  Future<void> _boot(_Config c) async {
    try {
      List<int>? saved;
      try {
        saved = await storage.read(c.localName);
      } catch (_) {
        saved = null;
      }
      _local = _settleVersion(ControlLocal.decode(saved), c.appVersion);
      _saveLocal(_local);
      await _loadCache(c);
      if (_config != c) return;
      _booted = true;
      _evaluate();
      _lastCheckAt = clock.now;
      _fetch();
    } catch (_) {
      /* Never reaches the app. */
    }
  }

  ControlLocal _settleVersion(ControlLocal saved, String appVersion) {
    if (saved.appVersion == null) return saved.copyWith(appVersion: appVersion);
    if (saved.appVersion != appVersion) {
      return saved.copyWith(
        appVersion: appVersion,
        updatedTo: appVersion,
        updateReturns: 0,
        pressPending: null,
      );
    }
    return saved;
  }

  void _settlePress() {
    final c = _config;
    final pending = _local.pressPending;
    if (c == null || pending == null) return;
    _saveLocal(
      _local.copyWith(
        pressPending: null,
        updateReturns: pending == c.appVersion ? _local.updateReturns + 1 : 0,
      ),
    );
  }

  Future<void> _loadCache(_Config c) async {
    List<int>? bytes;
    try {
      bytes = await storage.read(c.cacheName);
    } catch (_) {
      return;
    }
    if (bytes == null) return;
    final first = bytes.indexOf(10);
    if (first < 0) return;
    final second = bytes.indexOf(10, first + 1);
    if (second < 0) return;
    final saved = int.tryParse(
      String.fromCharCodes(bytes.sublist(first + 1, second)),
    );
    if (saved == null) return;
    final content = bytes.sublist(second + 1);
    final parsed = ControlRules.parse(content);
    if (parsed == null) return;
    _rules = parsed;
    _body = content;
    final etag = String.fromCharCodes(bytes.sublist(0, first));
    _etag = etag.isEmpty ? null : etag;
    _savedAt = saved;
  }

  void _saveCache() {
    final c = _config, content = _body;
    if (c == null || content == null) return;
    final head = '${_etag ?? ''}\n$_savedAt\n'.codeUnits;
    unawaited(_write(c.cacheName, [...head, ...content]));
  }

  void _saveLocal(ControlLocal next) {
    _local = next;
    final c = _config;
    if (c == null) return;
    unawaited(_write(c.localName, next.encode()));
  }

  Future<void> _write(String name, List<int> bytes) async {
    try {
      await storage.replace(name, bytes);
    } catch (_) {
      /* Kept in memory for this run. */
    }
  }

  void _fetch({bool askAgain = false}) {
    final c = _config;
    if (c == null) return;
    if (_requestToken != null) {
      if (askAgain) _askAgain = true;
      return;
    }
    final token = Object();
    _requestToken = token;
    _lastCheckAt = clock.now;
    _watchdog?.cancel();
    _watchdog = scheduler.schedule(_deadline, () {
      if (_requestToken == token) _requestToken = null;
    });
    unawaited(_request(c, token));
  }

  Future<void> _request(_Config c, Object token) async {
    PulseResponse? response;
    try {
      response = await transport.fetchControl(c.url, ifNoneMatch: _etag);
    } catch (_) {
      response = null;
    }
    _guard(() {
      if (_requestToken != token) return;
      _requestToken = null;
      _watchdog?.cancel();
      _watchdog = null;
      final again = _askAgain;
      _askAgain = false;
      try {
        if (response != null) _handle(response);
      } finally {
        if (again) _fetch();
      }
    });
  }

  void _handle(PulseResponse response) {
    switch (response.status) {
      case 200:
        final bytes = utf8.encode(response.body);
        final parsed = ControlRules.parse(bytes);
        if (parsed == null) return;
        _rules = parsed;
        _body = bytes;
        _etag = '"${parsed.version}"';
        _savedAt = clock.now.millisecondsSinceEpoch;
        _freshThisRun = true;
        _saveCache();
        _evaluate();
      case 304:
        if (_rules != null) {
          _savedAt = clock.now.millisecondsSinceEpoch;
          _freshThisRun = true;
          _saveCache();
          _evaluate();
        }
    }
  }

  void _evaluate() {
    final c = _config;
    if (c == null) return;
    final current = _rules;
    final now = clock.now;
    if (current == null) {
      _publish(ControlState.normal);
      return;
    }
    final nowMs = now.millisecondsSinceEpoch;
    final ageHours =
        (nowMs - _savedAt).clamp(0, 1 << 62) / _hour.inMilliseconds;
    final dismissedAgo = _local.dismissedVersion == c.appVersion
        ? (nowMs - _local.dismissedAt).clamp(0, 1 << 62) / _hour.inMilliseconds
        : null;
    final whatsNewVersion = current.whatsNew?.version;
    final input = ControlInput(
      rules: current,
      now: now,
      platform: c.platform,
      appVersion: c.appVersion,
      debug: c.debug,
      sdk: c.sdk,
      fromCache: !_freshThisRun || ageHours > 1.0,
      cacheAgeHours: ageHours,
      updateReturns: _local.updateReturns,
      canBuildStoreLink: fallbackStoreUrl != null,
      canOpenStore: canOpenStore(),
      suggestDismissedHoursAgo: dismissedAgo,
      shownAnnouncements: _local.shownAnnouncements.toSet(),
      justUpdated: _local.updatedTo == c.appVersion,
      whatsNewShown:
          whatsNewVersion != null && _local.whatsNewShown == whatsNewVersion,
    );
    var outcome = ControlDecision.decide(input);
    if (_continued.contains(outcome.state)) {
      outcome = outcome.copyWith(
        state: 'normal',
        banners: [
          for (final b in outcome.banners)
            if (b != 'testBuild') b,
        ],
      );
    }
    if (_continued.contains('maintenanceUpcoming')) {
      outcome = outcome.copyWith(
        banners: [
          for (final b in outcome.banners)
            if (b != 'maintenanceUpcoming') b,
        ],
      );
    }
    final context = ControlContext(
      appName: c.appName,
      appVersion: c.appVersion,
      languageTags: languageTags(),
      fallbackStoreUrl: fallbackStoreUrl,
      now: now,
      localTime: localTime,
      canOpenStore: input.canOpenStore,
    );
    _publish(ControlStateBuilder.build(outcome, current, context, c.platform));
    _scheduleBoundary(current, input, now);
  }

  void _publish(ControlState next) {
    if (next == _state) return;
    _state = next;
    for (final listener in List.of(_listeners)) {
      try {
        listener(next);
      } catch (_) {
        /* A listener never breaks the SDK. */
      }
    }
  }

  /// The clock rules (maintenance window, heads-up, announcement end, cache
  /// limits) apply on time, also offline.
  void _scheduleBoundary(
    ControlRules current,
    ControlInput input,
    DateTime now,
  ) {
    _timer?.cancel();
    _timer = null;
    final times = <DateTime>[];
    final m = current.maintenance;
    if (m != null) {
      times
        ..add(m.startsAt.subtract(Duration(minutes: m.headsUpMinutes)))
        ..add(m.startsAt)
        ..add(m.endsAt)
        ..add(
          m.startsAt.add(
            const Duration(hours: ControlDecision.cacheMaintenanceHours),
          ),
        );
    }
    final a = current.announcement;
    if (a != null) times.add(a.until);
    final saved = DateTime.fromMillisecondsSinceEpoch(_savedAt, isUtc: true);
    times
      ..add(saved.add(_hour))
      ..add(saved.add(Duration(hours: ControlDecision.cacheLockHours.toInt())));
    if (_local.dismissedVersion == input.appVersion) {
      times.add(
        DateTime.fromMillisecondsSinceEpoch(
          _local.dismissedAt,
          isUtc: true,
        ).add(Duration(hours: ControlDecision.suggestQuietHours.toInt())),
      );
    }
    DateTime? next;
    for (final t in times) {
      if (t.isAfter(now) && (next == null || t.isBefore(next))) next = t;
    }
    if (next == null) return;
    var delay = next.difference(now) + const Duration(milliseconds: 1);
    if (delay > _maxTimer) delay = _maxTimer;
    _timer = scheduler.schedule(delay, () => _guard(_evaluate));
  }

  void _guard(void Function() action) {
    try {
      action();
    } catch (_) {
      /* Never reaches the app. */
    }
  }
}

class _Config {
  const _Config(
    this.url,
    this.cacheName,
    this.localName,
    this.appVersion,
    this.appName,
    this.sdk,
    this.platform,
    this.debug,
  );
  final Uri url;
  final String cacheName, localName, appVersion, appName, sdk, platform;
  final bool debug;
}
