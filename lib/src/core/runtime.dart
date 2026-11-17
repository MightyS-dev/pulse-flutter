import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'advice.dart';
import 'auto_events.dart';
import 'backend.dart';
import 'capture.dart';
import 'computation.dart';
import 'config.dart';
import 'control_client.dart';
import 'error_payload.dart';
import 'heatmap.dart';
import 'heatmap_shots.dart';
import 'info.dart';
import 'model.dart';
import 'options.dart';
import 'ports.dart';
import 'queue.dart';
import 'screen_views.dart';
import 'usage.dart';
part 'runtime_delivery.dart';
part 'runtime_heatmap.dart';

/// One serialized state owner. Network completion never holds the state lane.
class PulseRuntime implements PulseBackend, ControlBackend, HeatmapSink {
  PulseRuntime({
    required this.clock,
    required this.scheduler,
    required this.random,
    required this.storage,
    required this.transport,
    required this.compression,
    required this.environment,
    required this.log,
    this.computation = const InlineComputation(),
    this.live = const NoLive(),
    this.localTime = _systemLocal,
    this.automaticSignals = true,
    this.heatmapDebugBuild = _never,
  }) : _capture = Capture(random) {
    _enqueue(_readPrivacy);
  }
  final PulseComputation computation;
  final PulseLive live;

  /// App Control: independent of analytics, also runs while opted out.
  @override
  late final ControlClient control = ControlClient(
    clock: clock,
    scheduler: scheduler,
    storage: storage,
    transport: transport,
    localTime: localTime,
  );

  /// Whether the app is a debug build (debug screenshots are sent only then).
  final bool Function() heatmapDebugBuild;
  static bool _never() => false;

  /// Whether session, install and update signals are sent. Always true in the
  /// package; tests that count signals switch it off.
  final bool automaticSignals;

  /// Converts an instant to device local time (replaceable in tests).
  final DateTime Function(DateTime) localTime;
  static DateTime _systemLocal(DateTime value) => value.toLocal();
  final PulseClock clock;
  final PulseScheduler scheduler;
  final PulseRandom random;
  final PulseStorage storage;
  final PulseTransport transport;
  final PulseCompression compression;
  final PulseEnvironment environment;
  final void Function(String) log;
  final Capture _capture;
  final _queue = SignalQueue();
  final _before = <_Input>[];
  final _waiters = <_FlushWaiter>[];
  Future<void> _tail = Future.value();
  PulseOptions _options = const PulseOptions(debug: false);
  static const _installName = 'install-id',
      _usageName = 'usage',
      _configName = 'config';
  PulseConfig _config = PulseConfig.defaults;

  /// The newest settings of this run (a refresh included). Only the heatmap
  /// switches follow it at once; everything else holds for the run.
  PulseConfig _live = PulseConfig.defaults;

  /// Portal settings in force for this run: the cached ones read at initialize.
  @override
  PulseConfig get config => _config;
  UsageStats? _usage;
  bool _installIsNew = false;
  static const _systemWait = Duration(seconds: 3);
  String? _key, _storageName, _processInstall;
  Uri? _endpoint;
  Map<String, String> _system = {};
  bool _optOut = true,
      _loaded = false,
      _pumpQueued = false,
      _forced = false,
      _halted = false,
      _gzipDisabled = false,
      _closed = false;
  bool? _dirty;
  int _revision = 0, _activeEpoch = 0;
  bool _active = false;
  String _generation = '';
  double _interval = 20;
  DateTime _nextFlush = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      _pauseUntil = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      _storageRetryAt = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  Cancellation? _timer;
  @override
  bool get optOut => _optOut;

  // Heatmaps (H1): taps per screen, folded into pulse.heatmap signals.
  late final HeatmapCapture _heatmap = HeatmapCapture(
    clock: clock,
    enabled: _heatmapAllowed,
    sessionAt: _heatmapSession,
    emit: _emitHeatmap,
  );
  HeatmapShots? _shots;
  @override
  void Function()? onHeatmapScreen;
  @override
  bool get heatmapActive {
    try {
      return _heatmapAllowed() && _heatmap.screen != null;
    } catch (_) {
      return false;
    }
  }

  @override
  String? get heatmapScreen => _heatmap.screen;
  @override
  void heatmapTap(
    double x,
    double y,
    double width,
    double height, {
    required bool keyboardVisible,
    required bool inputTarget,
    required bool ignored,
  }) {
    try {
      _heatmap.onTap(
        x,
        y,
        width,
        height,
        keyboardVisible: keyboardVisible,
        inputTarget: inputTarget,
        ignored: ignored,
      );
    } catch (_) {
      _warn('Heatmap capture failed safely.');
    }
  }

  @override
  Future<HeatmapShotTicket?> heatmapShotTicket(
    double width,
    double height,
  ) async {
    try {
      if (!_heatmapAllowed()) return null;
      return await _shots?.ticket(_heatmap.screen, width, height);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> heatmapScreenshot(
    HeatmapShotTicket? ticket,
    List<int> bytes,
    String contentType,
  ) async {
    try {
      if (!_heatmapAllowed()) return false;
      return await _shots?.upload(ticket, bytes, contentType) ?? false;
    } catch (_) {
      return false;
    }
  }

  int get count => _queue.entries.length;
  Future<void> get idle => _tail;
  void _warn(String message) {
    if (_options.debug) {
      try {
        log(message);
      } catch (_) {
        /* A host logger cannot break the SDK. */
      }
    }
  }

  Future<void> _enqueue(FutureOr<void> Function() action) {
    _tail = _tail
        .then((_) async {
          if (!_closed) {
            await action();
          }
        })
        .catchError((Object error, StackTrace stack) {
          _warn('SDK operation failed safely.');
        });
    return _tail;
  }

  /// Loads or creates the anonymous install id. Never throws; falls back to an
  /// in-memory id for this process and does not retry writing.
  Future<void> _ensureInstall() async {
    if (_capture.installHash != null) {
      return;
    }
    String? id;
    try {
      final bytes = await storage.read(_installName);
      _installIsNew = bytes == null;
      if (bytes != null) {
        final decoded = utf8.decode(bytes, allowMalformed: true);
        if (RegExp(r'^[0-9a-f]{32}$').hasMatch(decoded)) {
          id = decoded;
        }
      }
    } catch (_) {
      _warn('Install id unreadable; using a process id.');
    }
    if (id == null) {
      id = _processInstall ??= random.token();
      try {
        await storage.replace(_installName, utf8.encode(id));
      } catch (_) {
        _warn('Install id not saved; using a process id.');
      }
    }
    _processInstall = id;
    _capture.installHash = hashText(id);
  }

  /// Loads the session statistics; an unreadable file starts fresh in memory.
  Future<void> _ensureUsage() async {
    if (_usage != null) {
      return;
    }
    UsageStats? loaded;
    try {
      final bytes = await storage.read(_usageName);
      if (bytes != null) {
        loaded = UsageStats.decode(bytes);
      }
    } catch (_) {
      _warn('Usage statistics unreadable; using this process only.');
    }
    _usage = loaded ?? UsageStats(newInstall: _installIsNew);
  }

  Future<void> _saveUsage({bool force = false}) async {
    final usage = _usage;
    if (usage == null || _optOut || (!usage.dirty && !force)) {
      return;
    }
    try {
      await storage.replace(_usageName, usage.encode());
    } catch (_) {
      _warn('Usage statistics not saved; keeping them in memory.');
    }
    usage.markSaved();
  }

  Future<void> _forgetInstall() async {
    _processInstall = null;
    _capture.installHash = null;
    _usage = null;
    _installIsNew = false;
    try {
      await storage.remove(_usageName);
    } catch (_) {
      _warn('Usage statistics could not be removed.');
    }
    try {
      await storage.remove(_installName);
    } catch (_) {
      _warn('Install id could not be removed.');
    }
    try {
      await storage.remove(_configName);
    } catch (_) {
      _warn('Settings could not be removed.');
    }
    try {
      await storage.remove(HeatmapShots.fileName);
    } catch (_) {
      _warn('Heatmap markers could not be removed.');
    }
  }

  Future<void> _readPrivacy() async {
    try {
      final preference = await storage.read('opt-out');
      final generation = await storage.read('privacy-generation');
      _optOut =
          preference != null &&
          (preference.length != 1 || preference.single != 0);
      if (generation != null) {
        final decoded = utf8.decode(generation);
        if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(decoded)) {
          _optOut = true;
        } else {
          _generation = decoded;
        }
      }
      if (_revision > 0) {
        _optOut = true;
      }
    } catch (_) {
      _optOut = true;
      _warn('Privacy unreadable; collection suspended.');
    }
  }

  @override
  Future<void> initialize(
    String key, {
    PulseOptions options = const PulseOptions(),
  }) => _enqueue(() async {
    if (_key != null ||
        key.trim().isEmpty ||
        key.length > 4096 ||
        RegExp(r'[\x00-\x1f\x7f-\uffff]').hasMatch(key)) {
      return;
    }
    _options = options.normalized();
    _initAt = clock.now;
    final uri = Uri.tryParse(_options.host);
    if (uri == null ||
        !['https', 'http'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      _warn('Invalid host ignored.');
      return;
    }
    final path = uri.path.replaceAll(RegExp(r'^/+|/+$'), '');
    _endpoint = uri.replace(
      path: '/${path.isEmpty ? '' : '$path/'}api/v1/signals',
    );
    _key = key;
    _storageName = 'queue-${hashText(key)}.bin';
    _interval = _options.flushIntervalSeconds;
    // The first batch after initialize is due at once; later batches wait.
    _nextFlush = clock.now;
    _system = await _lookupSystem();
    for (final field in [
      'platform',
      'osName',
      'osVersion',
      'appVersion',
      'appBuildNumber',
      'deviceModel',
      'locale',
    ]) {
      _system.putIfAbsent(field, () => '');
    }
    _system['sdkName'] = PulseInfo.sdkName;
    _system['sdkVersion'] = PulseInfo.version;
    if (!_options.sendAppIdentity) {
      _system.remove('bundleId');
    }
    if (_options.appVersion != null) {
      _system['appVersion'] = _options.appVersion!;
    }
    _system = _system.map((k, v) => MapEntry(k, _bounded(v)));
    final cached = await _readConfig();
    _config = cached ?? PulseConfig.defaults;
    _live = _config;
    _shots = HeatmapShots(
      storage: storage,
      transport: transport,
      clock: clock,
      appKey: key,
      endpoint: _endpoint!,
      appVersion: _system['appVersion'] ?? '',
      debugBuild: heatmapDebugBuild,
      warn: _warn,
    );
    if (!_config.screenViewsAllowed) _heatmap.setScreen(null);
    _heatmapChanged();
    _requestPump();
    if (!_optOut) {
      final revision = _revision;
      unawaited(_fetchConfig(key, cached, revision));
    }
    _startControl(key);
  });

  /// Starts App Control in the background. It has its own cache, sends no
  /// identity and does not follow the analytics opt-out. Never throws.
  void _startControl(String key) {
    try {
      final endpoint = _endpoint;
      if (endpoint == null) return;
      final os = (_system['osName'] ?? '').toLowerCase();
      if (os == 'android' && _system['bundleId'] != null) {
        control.fallbackStoreUrl =
            'https://play.google.com/store/apps/details?id=${Uri.encodeQueryComponent(_system['bundleId']!)}';
      }
      control.start(
        key: key,
        signalsUrl: endpoint,
        mode: _options.control,
        appVersion: _system['appVersion'] ?? '',
        appName: _system['appName'] ?? '',
        sdk: '${PulseInfo.sdkName}@${PulseInfo.version}',
        platform: os,
        debug: _options.debug,
      );
    } catch (_) {
      _warn('App Control not started.');
    }
  }

  /// The cached portal settings, or null when there are none or they are unreadable.
  Future<PulseConfig?> _readConfig() async {
    try {
      final bytes = await storage.read(_configName);
      return bytes == null
          ? null
          : PulseConfig.parse(utf8.decode(bytes, allowMalformed: true));
    } catch (_) {
      _warn('Settings unreadable; everything stays on.');
      return null;
    }
  }

  /// Reads the portal settings once, in the background. The result is stored
  /// for the next launch and never changes this run. Never throws.
  Future<void> _fetchConfig(
    String key,
    PulseConfig? cached,
    int revision,
  ) async {
    try {
      final base = _endpoint;
      if (base == null) return;
      final url = base.replace(
        path: base.path.replaceFirst(RegExp(r'signals$'), 'config'),
      );
      final reply = await transport.get(
        url,
        key,
        ifNoneMatch: cached == null ? null : '"${cached.version}"',
      );
      if (reply.status != 200 || _optOut || revision != _revision || _closed) {
        return;
      }
      final fetched = PulseConfig.parse(reply.body);
      if (fetched == null) {
        _warn('Settings response ignored.');
        return;
      }
      await _enqueue(() async {
        if (_optOut || revision != _revision) return;
        await storage.replace(_configName, fetched.encode());
        _live = fetched;
        _heatmapChanged();
      });
    } catch (_) {
      _warn('Settings not fetched; keeping the cached ones.');
    }
  }

  /// Waits for the device and app details, but never longer than a few
  /// seconds: after that the signals go out with what is known.
  Future<Map<String, String>> _lookupSystem() async {
    final done = Completer<Map<String, String>>();
    final timer = scheduler.schedule(_systemWait, () {
      if (!done.isCompleted) {
        _warn('Environment slow; continuing without it.');
        done.complete({});
      }
    });
    unawaited(
      _gather().then(
        (value) {
          if (!done.isCompleted) {
            done.complete(Map.of(value));
          }
        },
        onError: (Object _) {
          if (!done.isCompleted) {
            _warn('Environment unavailable.');
            done.complete({});
          }
        },
      ),
    );
    final result = await done.future;
    timer.cancel();
    return result;
  }

  Future<Map<String, String>> _gather() async {
    final warm = Future<void>.sync(live.warmUp).catchError((Object _) {});
    final system = await environment.system();
    await warm;
    return system;
  }

  /// Dynamic values at [at]: the host's live state plus the UTC offset.
  Map<String, String> _liveAt(DateTime at) {
    final result = <String, String>{};
    try {
      result.addAll(live.read());
    } catch (_) {
      _warn('Live state unavailable.');
    }
    try {
      result['utcOffsetMinutes'] = '${localTime(at).timeZoneOffset.inMinutes}';
    } catch (_) {
      /* The offset is optional. */
    }
    return result;
  }

  static String _bounded(String value) {
    if (!validUnicode(value)) {
      return '';
    }
    final bytes = utf8.encode(value);
    return bytes.length <= 256
        ? value
        : utf8
              .decode(bytes.take(256).toList(), allowMalformed: true)
              .replaceAll('\uFFFD', '');
  }

  @override
  void track(String type, {num? value, Map<String, Object?>? props}) {
    try {
      final at = clock.now;
      final safe = <String, Object?>{};
      for (final entry in (props ?? <String, Object?>{}).entries) {
        final item = entry.value;
        if (item is String || item is num || item is bool) {
          safe[entry.key] = item;
        } else {
          _warn('Invalid property ignored.');
        }
      }
      if (type == screenViewType) {
        _heatmapScreen(safe);
        if (safe.containsKey('previousScreen')) {
          safe['previousScreenSeconds'] = _screenSeconds(at);
        }
        _screenStart(at);
      }
      final snapshot = _liveAt(at);
      _enqueue(() async {
        if (_optOut) {
          return;
        }
        await _ensureInstall();
        await _ensureUsage();
        if (_optOut) {
          return;
        }
        // A signal that is not valid is dropped before it can start or
        // extend a session.
        if (!Signal.isValid(type, value)) {
          _warn('Invalid signal ignored.');
          return;
        }
        await _admit(at, snapshot, type, safe, value: value);
      });
    } catch (_) {
      _warn('Invalid signal ignored.');
    }
  }

  // Automatic events: foreground, deep links, screen time, quota guards.
  DateTime? _initAt, _firstFrameAt;
  bool _coldPending = true;
  int _dropped = 0;
  String? _capSession;
  final _sessionCaps = <String, int>{};
  bool _screenForeground = true, _screenOpen = false;
  DateTime? _screenShownAt;
  int _screenMillis = 0;

  /// Tells the runtime the first frame was drawn. `launchMs` of the first
  /// session of this process runs from `initialize` to this moment.
  void firstFrameRendered() => _firstFrameAt ??= clock.now;

  void _screenStart(DateTime at) {
    _screenMillis = 0;
    _screenOpen = true;
    _screenShownAt = _screenForeground ? at : null;
  }

  int _screenSeconds(DateTime at) {
    final shown = _screenShownAt;
    final extra = shown == null ? 0 : at.difference(shown).inMilliseconds;
    final total = _screenMillis + (extra < 0 ? 0 : extra);
    return total ~/ 1000;
  }

  void _screenPause(DateTime at) {
    final shown = _screenShownAt;
    if (shown != null) {
      final extra = at.difference(shown).inMilliseconds;
      _screenMillis += extra < 0 ? 0 : extra;
    }
    _screenShownAt = null;
    _screenForeground = false;
  }

  void _screenResume(DateTime at) {
    _screenForeground = true;
    if (_screenOpen) _screenShownAt ??= at;
  }

  /// Whether automatic signal [type] may be sent now: the package switch, the
  /// code option and the cached portal settings all have to agree.
  bool _autoEnabled(String type) =>
      automaticSignals && _options.automaticSignals && _config.allows(type);

  /// The app came to the foreground. [cold] is true for the first one of this
  /// process. Counts it, and sends `pulse.app_opened` when the portal listed
  /// it. Never throws.
  void appForeground({required bool cold}) {
    try {
      control.onForeground();
      final at = clock.now;
      _screenResume(at);
      final snapshot = _liveAt(at);
      _enqueue(() async {
        if (_optOut) return;
        await _ensureInstall();
        await _ensureUsage();
        if (_optOut) return;
        if (!_usage!.foreground(at, localTime)) return;
        if (!_autoEnabled(appOpenedType)) return;
        await _admit(at, snapshot, appOpenedType, {'coldStart': cold});
      });
    } catch (_) {
      _warn('Foreground ignored.');
    }
  }

  /// The app went to the background. Ends the foreground period, and sends
  /// `pulse.app_backgrounded` when the portal listed it and a session is
  /// running (it never starts one). Never throws.
  void appBackground() {
    try {
      final at = clock.now;
      _heatmap.flush();
      _screenPause(at);
      final snapshot = _liveAt(at);
      _enqueue(() async {
        if (_optOut) return;
        await _ensureInstall();
        await _ensureUsage();
        if (_optOut) return;
        final seconds = _usage!.background(at);
        if (seconds == null || !_autoEnabled(appBackgroundedType)) return;
        if (_capture.continuing(at) == null) return;
        await _admit(at, snapshot, appBackgroundedType, {
          'foregroundSeconds': seconds,
        });
      });
    } catch (_) {
      _warn('Background ignored.');
    }
  }

  /// Reports a link that opened the app as `pulse.deep_link`: scheme, host, a
  /// path without ids and the utm_ tags, nothing else. Never throws.
  @override
  void deepLink(Uri uri) {
    try {
      final props = DeepLink.props(uri);
      if (props == null) return;
      final at = clock.now;
      final snapshot = _liveAt(at);
      _enqueue(() async {
        if (_optOut) return;
        await _ensureInstall();
        await _ensureUsage();
        if (_optOut || !_autoEnabled(deepLinkType)) return;
        await _admit(at, snapshot, deepLinkType, props);
      });
    } catch (_) {
      _warn('Deep link ignored.');
    }
  }

  /// Captures a signal inside the state lane (install and usage are loaded).
  Future<void> _admit(
    DateTime at,
    Map<String, String> snapshot,
    String type,
    Map<String, Object?> props, {
    num? value,
    Map<String, Object?>? heatmap,
  }) async {
    final session = _capture.sessionAt(at);
    final input = (
      timestamp: at,
      session: session,
      fresh: _capture.startedSession,
      hash: _capture.userHash,
      type: type,
      value: value,
      props: props,
      error: null,
      heatmap: heatmap,
      live: snapshot,
    );
    if (_key == null) {
      if (_before.length == 100) {
        _before.removeAt(0);
      }
      _before.add(input);
    } else {
      _append(input);
      await _saveUsage();
      _requestPump();
    }
  }

  /// The per session and per day guards. True when the signal may go on;
  /// a signal that is over a cap is counted for `droppedAutomatic`.
  bool _withinQuota(_Input input, String type) {
    if (input.session != _capSession) {
      _sessionCaps.clear();
      _capSession = input.session;
    }
    final cap = AutoQuota.sessionCaps[type];
    final used = _sessionCaps[type] ?? 0;
    final usage = _usage;
    if ((cap != null && used >= cap) ||
        (usage != null &&
            !usage.takeDaily(input.timestamp, localTime, AutoQuota.dayCap))) {
      _dropped++;
      return false;
    }
    _sessionCaps[type] = used + 1;
    return true;
  }

  /// `launchMs` for the first session of this process, or null when unknown
  /// or not believable. Asked once.
  Map<String, String>? _launchExtra(_Input input) {
    if (!_coldPending) return null;
    _coldPending = false;
    final start = _initAt;
    if (start == null) return null;
    final end = _firstFrameAt ?? input.timestamp;
    final ms = end.difference(start).inMilliseconds;
    return ms >= 0 && ms <= AutoQuota.maxLaunchMs ? {'launchMs': '$ms'} : null;
  }

  final _errorCounts = <String, int>{};
  String? _errorCountSession;
  static const _maxErrorsPerType = 10;

  /// Captures a `pulse.error` signal. Never throws. At most ten per error
  /// type and session; the rest are dropped silently.
  @override
  void trackError(
    Object error,
    StackTrace? stack,
    Map<String, Object?>? props, {
    required String kind,
  }) {
    try {
      final at = clock.now;
      final payload = ErrorPayload.from(kind, error, stack, ErrorDetail.full);
      final safe = <String, Object?>{};
      for (final entry in (props ?? <String, Object?>{}).entries) {
        final item = entry.value;
        if (item is String || item is num || item is bool) {
          safe[entry.key] = item;
        }
      }
      final snapshot = _liveAt(at);
      _enqueue(() async {
        if (_optOut) {
          return;
        }
        await _ensureInstall();
        await _ensureUsage();
        if (_optOut) {
          return;
        }
        final type = payload['type']! as String;
        final continuing = _capture.continuing(at);
        if (continuing == null || continuing != _errorCountSession) {
          _errorCounts.clear();
          _errorCountSession = continuing;
        }
        final count = _errorCounts[type] ?? 0;
        if (count >= _maxErrorsPerType) {
          return;
        }
        final session = _capture.sessionAt(at);
        _errorCountSession = session;
        _errorCounts[type] = count + 1;
        final input = (
          timestamp: at,
          session: session,
          fresh: _capture.startedSession,
          hash: _capture.userHash,
          type: errorSignalType,
          value: null,
          props: safe,
          error: payload,
          heatmap: null,
          live: snapshot,
        );
        if (_key == null) {
          if (_before.length == 100) {
            _before.removeAt(0);
          }
          _before.add(input);
        } else {
          _append(input);
          await _saveUsage();
          _requestPump();
        }
      });
    } catch (_) {
      _warn('Invalid error ignored.');
    }
  }

  void _append(_Input input) {
    final usage = _usage;
    if (usage != null) {
      if (input.fresh) {
        final automatic = automaticSignals && _options.automaticSignals;
        final auto = usage.beginSession(
          input.timestamp,
          localTime,
          _system['appVersion'] ?? '',
          _system['appBuildNumber'] ?? '',
          updateQueued: automatic && _config.allows(appUpdatedType),
        );
        final launch = _launchExtra(input);
        for (final signal in automatic ? auto : const <AutoSignal>[]) {
          _appendOne(
            input,
            signal.type,
            null,
            signal.props,
            null,
            signal.type == sessionStartedType ? launch : null,
          );
        }
      }
      usage.touch(input.timestamp);
    }
    _appendOne(
      input,
      input.type,
      input.value,
      input.props,
      input.error,
      null,
      input.heatmap,
    );
  }

  int _lastStamp = -(1 << 52);

  /// Strictly increasing capture timestamps at millisecond resolution: the later of the clock reading and the
  /// previous timestamp plus one millisecond. Signals are stored in capture order, automatic ones first.
  DateTime _nextStamp(DateTime reading) {
    final now = reading.millisecondsSinceEpoch;
    _lastStamp = now > _lastStamp ? now : _lastStamp + 1;
    return DateTime.fromMillisecondsSinceEpoch(_lastStamp, isUtc: true);
  }

  void _appendOne(
    _Input input,
    String type,
    num? value,
    Map<String, Object?> props, [
    Map<String, Object?>? error,
    Map<String, String>? extra,
    Map<String, Object?>? heatmap,
  ]) {
    final isHeatmap = type == heatmapType;
    // Heatmaps were checked against the newest settings before they were
    // queued, and no AE1 cap counts them.
    if (!isHeatmap && !_config.allows(type)) {
      return;
    }
    if (automaticSignalTypes.contains(type) && !_withinQuota(input, type)) {
      return;
    }
    final carried = _dropped > 0 && !isHeatmap
        ? {'droppedAutomatic': '$_dropped'}
        : null;
    final stamp = _nextStamp(input.timestamp);
    final json = Signal.encode(
      timestamp: stamp,
      session: input.session,
      userHash: input.hash ?? _capture.installHash,
      type: type,
      value: value,
      props: props,
      error: error != null && _options.errorDetail == ErrorDetail.typeOnly
          ? ErrorPayload.typeOnly(error)
          : error,
      heatmap: heatmap,
      system: _config.filterSystem({
        ..._system,
        ...input.live,
        ...?_usage?.fields(input.timestamp, localTime),
        ...?extra,
        ...?carried,
      }),
      debug: _options.debug,
      warn: _warn,
    );
    if (json == null) {
      _warn('Invalid signal ignored.');
      return;
    }
    if (carried != null) _dropped = 0;
    _queue.add(Entry(random.token(), stamp, json));
  }

  @override
  void setUser(String? identifier) {
    _enqueue(() {
      if (!_optOut) {
        _capture.setUser(identifier);
      }
    });
  }

  @override
  Future<void> setOptOut(bool desired) {
    _optOut = true;
    _heatmapOptOut();
    final revision = ++_revision;
    _activeEpoch++;
    _active = false;
    try {
      transport.cancel();
    } catch (_) {
      _warn('Request cancellation failed safely.');
    }
    return _enqueue(() async {
      if (revision != _revision) {
        return;
      }
      _queue.clear();
      _before.clear();
      _capture.reset();
      _errorCounts.clear();
      _errorCountSession = null;
      _sessionCaps.clear();
      _capSession = null;
      _dropped = 0;
      _screenOpen = false;
      _screenShownAt = null;
      await _forgetInstall();
      _completeWaiters();
      _generation = random.token();
      _dirty = desired;
      await _persistPreference(revision);
      _requestPump();
    });
  }

  Future<void> _persistPreference(int revision) async {
    final desired = _dirty;
    if (desired == null) {
      return;
    }
    try {
      if (desired) {
        await storage.replace('opt-out', [1]);
      }
      await storage.replace('privacy-generation', utf8.encode(_generation));
      if (_storageName != null) {
        await storage.remove(_storageName!);
      }
      if (!desired) {
        await storage.replace('opt-out', [0]);
      }
      if (revision == _revision) {
        _dirty = null;
        _optOut = desired;
      }
    } catch (_) {
      _optOut = true;
      _storageRetryAt = clock.now.add(const Duration(seconds: 1));
      _warn('Privacy write failed; collection suspended.');
    }
  }

  @override
  Future<void> flush() async {
    _heatmap.flush();
    final done = Completer<void>();
    await _enqueue(() async {
      if (_key == null || _optOut || _halted) {
        done.complete();
        return;
      }
      final loaded = await _load();
      _waiters.add(
        _FlushWaiter(
          loaded ? _queue.entries.map((e) => e.id).toSet() : null,
          done,
        ),
      );
      _forced = true;
      await _pump();
    });
    if (_closed && !done.isCompleted) {
      done.complete();
    }
    await done.future;
  }

  Future<void> backgroundSave() async {
    try {
      _heatmap.flush();
      await _enqueue(() async {
        _forced = true;
        await _saveUsage(force: true);
        await _pump();
      }).timeout(const Duration(seconds: 2));
    } catch (_) {
      _warn('Background save deadline reached.');
    }
  }

  Future<void> close() async {
    _heatmap.flush();
    await _enqueue(() async {
      if (await _load()) {
        await _persist();
      }
      _timer?.cancel();
      control.stop();
      transport.cancel();
      _activeEpoch++;
      _active = false;
      _closed = true;
      for (final waiter in _waiters) {
        waiter.done.complete();
      }
      _waiters.clear();
    });
  }

  Future<bool> _load() async {
    if (_loaded || _storageName == null) {
      return _loaded || _storageName == null;
    }
    try {
      final bytes = await storage.read(_storageName!);
      if (bytes != null) {
        try {
          final snapshot = await computation.decode(bytes, compression);
          if (snapshot.generation == _generation) {
            _queue.entries.insertAll(0, snapshot.entries);
            _queue.pending.addAll(snapshot.pending);
            _interval = snapshot.interval;
            final cap = clock.now.add(const Duration(hours: 1));
            _pauseUntil = snapshot.pauseUntil.isAfter(cap)
                ? cap
                : snapshot.pauseUntil;
            for (final batch in _queue.pending) {
              if (batch.retryAt.isAfter(cap)) {
                batch.retryAt = clock.now;
              }
            }
            if (_queue.entries.isNotEmpty) {
              _nextFlush = clock.now;
            }
          }
        } catch (_) {
          _warn('Damaged queue discarded.');
        }
      }
      _loaded = true;
      if (_optOut) {
        _queue.clear();
        _before.clear();
      } else {
        final current = _liveAt(clock.now);
        for (final input in _before) {
          _append((
            timestamp: input.timestamp,
            session: input.session,
            fresh: input.fresh,
            hash: input.hash,
            type: input.type,
            value: input.value,
            props: input.props,
            error: input.error,
            heatmap: input.heatmap,
            live: {...current, ...input.live},
          ));
        }
        _before.clear();
        await _saveUsage();
      }
      _prune();
      return true;
    } catch (_) {
      _storageRetryAt = clock.now.add(const Duration(seconds: 1));
      _warn('Queue unreadable; sending suspended.');
      return false;
    }
  }

  Future<bool> _persist() async {
    if (_storageName == null || !_loaded) {
      return _storageName == null;
    }
    try {
      if (_optOut) {
        await storage.remove(_storageName!);
      } else {
        await storage.replace(
          _storageName!,
          await computation.encode(
            QueueSnapshot(
              _generation,
              _queue.entries,
              _queue.pending,
              _interval,
              _pauseUntil,
            ),
          ),
        );
      }
      _storageRetryAt = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      return true;
    } catch (_) {
      _storageRetryAt = clock.now.add(const Duration(seconds: 1));
      _warn('Queue save failed; sending suspended.');
      return false;
    }
  }

  void _prune() {
    final first = _queue.pending.firstOrNull;
    _queue.prune(clock.now, _options);
    if (_active && first != _queue.pending.firstOrNull) {
      transport.cancel();
      _activeEpoch++;
      _active = false;
    }
  }

  void _completeWaiters() {
    final live = _queue.entries.map((e) => e.id).toSet();
    _waiters.removeWhere((waiter) {
      waiter.ids ??= live;
      if (_optOut || _halted || waiter.ids!.intersection(live).isEmpty) {
        waiter.done.complete();
        return true;
      }
      return false;
    });
  }

  void _requestPump() {
    if (_pumpQueued || _closed) {
      return;
    }
    _pumpQueued = true;
    scheduleMicrotask(() {
      _enqueue(() async {
        _pumpQueued = false;
        await _pump();
      });
    });
  }

  void _schedule(DateTime at) {
    _timer?.cancel();
    final delay = at.difference(clock.now);
    _timer = scheduler.schedule(
      delay.isNegative ? const Duration(milliseconds: 1) : delay,
      _requestPump,
    );
  }

  static Duration _seconds(double value) =>
      Duration(microseconds: (value * 1000000).round());
}

typedef _Input = ({
  DateTime timestamp,
  String session,
  bool fresh,
  String? hash,
  String type,
  num? value,
  Map<String, Object?> props,
  Map<String, Object?>? error,
  Map<String, Object?>? heatmap,
  Map<String, String> live,
});

class _FlushWaiter {
  _FlushWaiter(this.ids, this.done);
  Set<String>? ids;
  final Completer<void> done;
}
