import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'control_host.dart';
import 'control_theme.dart';
import 'core/control_client.dart';
import 'core/control_state.dart';
import 'core/info.dart';

/// App Control: reads the rules you set in the portal (require an update,
/// suggest one, maintenance) and shows the matching screen. Reach it as
/// `Pulse.control`.
///
/// One line in your app is enough:
///
/// ```dart
/// MaterialApp(builder: Pulse.control.builder, home: const Home())
/// ```
///
/// It never blocks start-up, never closes your app and, when anything goes
/// wrong (no network, unreadable answer), keeps the app working normally.
class PulseControl {
  /// Created by the package. Use `Pulse.control`.
  PulseControl();

  final _notifier = ValueNotifier<ControlState>(ControlState.normal);
  final _changes = StreamController<ControlState>.broadcast();
  ControlClient? _client;
  ControlMode _mode = ControlMode.automatic;
  bool _hinted = false, _mounted = false;
  String? _appLanguage;

  /// Called with the store link when the user presses Update. Open it with a
  /// package such as `url_launcher` (`launchUrl(url, mode:
  /// LaunchMode.externalApplication)`): this package has no native code and
  /// opens no links itself. Without it the built-in screens show no Update
  /// button and a required update only suggests.
  void Function(Uri url)? get onOpenStore => _onOpenStore;
  set onOpenStore(void Function(Uri url)? value) {
    _onOpenStore = value;
    refresh();
  }

  void Function(Uri url)? _onOpenStore;

  /// Colors, shape and text styles of the built-in screens. They follow your
  /// app theme when left out.
  PulseControlTheme? theme;

  /// What to show right now. [ControlState.normal] until the rules say
  /// otherwise (and always when `PulseOptions.control` is
  /// [ControlMode.off]).
  ControlState get state => _notifier.value;

  /// Every change of [state]. A broadcast stream: listen from `manual` mode
  /// to draw your own screens.
  Stream<ControlState> get stream => _changes.stream;

  /// For the built-in screens: the same value as [state] as a listenable.
  ValueListenable<ControlState> get listenable => _notifier;

  /// The mode in force (`PulseOptions.control`).
  ControlMode get mode => _mode;

  /// Whether the user has a way to open the store from the screen.
  bool get canOpenStore =>
      _mode != ControlMode.automatic || _onOpenStore != null;

  /// Checks the rules now, without waiting for the next return to the
  /// foreground. Does nothing in `off` mode. Never throws.
  void checkNow() => _safe(() => _client?.checkNow());

  /// Opens the store page of [state] through [onOpenStore]. Returns false when
  /// there is no link or no opener. Never throws.
  bool openStore() {
    try {
      final link = state.url == null ? null : Uri.tryParse(state.url!);
      final open = _onOpenStore;
      if (link == null || open == null) return false;
      final kind = state.kind;
      if (kind == ControlKind.updateRequired ||
          kind == ControlKind.updateSuggested ||
          kind == ControlKind.versionBlocked) {
        _client?.noteUpdatePressed();
      }
      open(link);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Leaves the current state where it allows that: a suggestion stays away for
  /// 24 hours, a card is marked as shown, a screen with
  /// [ControlState.allowContinue] is left until the app restarts. A locking
  /// screen ignores it. Never throws.
  void dismiss() => _safe(() => _client?.dismiss());

  /// The one line that shows the built-in screens:
  /// `MaterialApp(builder: Pulse.control.builder)`. It has the signature of
  /// `TransitionBuilder`, so it also fits `CupertinoApp` and `WidgetsApp`.
  TransitionBuilder get builder => _build;

  Widget _build(BuildContext context, Widget? child) =>
      PulseControlHost(control: this, child: child ?? const SizedBox.shrink());

  /// Connects the running client. Called by `Pulse.initialize`.
  void attach(ControlClient client, ControlMode mode, {required bool debug}) {
    _safe(() {
      _client?.removeListener(_changed);
      _client = client;
      _mode = mode;
      client
        ..languageTags = _languages
        ..canOpenStore = (() => canOpenStore)
        ..addListener(_changed);
      _changed(client.state);
      if (debug && mode == ControlMode.automatic) _hintLater();
    });
  }

  /// Tells the client that the opener appeared or went away.
  void refresh() => _safe(() => _client?.reevaluate());

  /// The language of the app, as the screens see it. Set by the host.
  void setAppLanguage(String? tag) {
    if (tag == _appLanguage) return;
    _appLanguage = tag;
    _safe(() => _client?.reevaluate());
  }

  /// Called by the host widget.
  void hostMounted(bool mounted) => _mounted = mounted;

  List<String> _languages() {
    final system = <String>[];
    try {
      system.add(PlatformDispatcher.instance.locale.toLanguageTag());
    } catch (_) {
      /* Falls back to English. */
    }
    return [?_appLanguage, ...system];
  }

  void _changed(ControlState next) {
    if (next == _notifier.value) return;
    _notifier.value = next;
    if (!_changes.isClosed) _changes.add(next);
  }

  void _hintLater() {
    if (_hinted) return;
    try {
      unawaited(
        WidgetsBinding.instance.endOfFrame.then((_) {
          if (_hinted || _mounted || _mode != ControlMode.automatic) return;
          _hinted = true;
          debugPrint(
            '${PulseInfo.displayName}: add builder: Pulse.control.builder to '
            'MaterialApp to show App Control screens',
          );
        }),
      );
    } catch (_) {
      /* The hint is optional. */
    }
  }

  void _safe(void Function() action) {
    try {
      action();
    } catch (_) {
      /* App Control never throws into the app. */
    }
  }
}
