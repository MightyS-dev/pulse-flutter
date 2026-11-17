import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import '../core/heatmap.dart';
import '../heatmap_widgets.dart';
import '../sdk_ui.dart';
import 'heatmap_image.dart';

/// Reports taps to the heatmap through one global pointer route and, in debug
/// builds, takes one screenshot per screen.
///
/// The route only watches: a global pointer route cannot consume or delay an
/// event, so the app sees every pointer event exactly as before. A tap is a
/// pointer up of the only pointer with no move beyond `kTouchSlop` since its
/// down. Positions are logical pixels, which is what Flutter reports.
class HeatmapHook {
  HeatmapHook(
    this.sink, {
    bool Function()? debugBuild,
    this.shotDelay = const Duration(seconds: 1),
  }) : _debugBuild = debugBuild ?? (() => false);

  final HeatmapSink sink;
  final bool Function() _debugBuild;

  /// How long a screen is visible before its picture is taken.
  final Duration shotDelay;
  final _tracks = <int, _Track>{};
  Timer? _shotTimer;
  bool _installed = false, _shooting = false;

  /// Starts watching pointers. Calling it twice does nothing.
  void install() {
    if (_installed) return;
    try {
      GestureBinding.instance.pointerRouter.addGlobalRoute(_route);
      sink.onHeatmapScreen = _screenChanged;
      _installed = true;
    } catch (_) {
      /* No binding: nothing to watch. */
    }
  }

  /// Stops watching pointers and drops pending work.
  void dispose() {
    if (!_installed) return;
    _installed = false;
    try {
      GestureBinding.instance.pointerRouter.removeGlobalRoute(_route);
    } catch (_) {
      /* The binding is gone already. */
    }
    if (sink.onHeatmapScreen == _screenChanged) sink.onHeatmapScreen = null;
    _shotTimer?.cancel();
    _shotTimer = null;
    _tracks.clear();
  }

  void _route(PointerEvent event) {
    try {
      if (event is PointerDownEvent) {
        _down(event);
      } else if (_tracks.isEmpty) {
        return;
      } else if (event is PointerMoveEvent) {
        _move(event);
      } else if (event is PointerUpEvent) {
        _up(event);
      } else if (event is PointerCancelEvent) {
        _tracks.remove(event.pointer);
      }
    } catch (_) {
      /* Watching must never break input. */
    }
  }

  static bool _tapKind(PointerEvent e) =>
      e.kind == ui.PointerDeviceKind.touch ||
      e.kind == ui.PointerDeviceKind.mouse ||
      e.kind == ui.PointerDeviceKind.stylus;

  void _down(PointerDownEvent e) {
    // A second finger turns the gesture into a multi-touch one: no taps.
    final others = _tracks.isNotEmpty;
    for (final t in _tracks.values) {
      t.valid = false;
    }
    final track = _Track(e.position);
    _tracks[e.pointer] = track;
    if (others ||
        !_tapKind(e) ||
        (e.buttons & ~kPrimaryButton) != 0 ||
        !sink.heatmapActive) {
      track.valid = false;
      return;
    }
    final found = _inspect(e);
    track.inputTarget = found.input;
    track.ignored = found.ignored;
  }

  void _move(PointerMoveEvent e) {
    final track = _tracks[e.pointer];
    if (track == null || !track.valid) return;
    if ((e.position - track.start).distance > kTouchSlop) track.valid = false;
  }

  void _up(PointerUpEvent e) {
    final track = _tracks.remove(e.pointer);
    if (track == null || !track.valid) return;
    if ((e.position - track.start).distance > kTouchSlop) return;
    final view = _viewOf(e.viewId);
    if (view == null) return;
    final ratio = view.devicePixelRatio;
    final width = view.physicalSize.width / ratio;
    final height = view.physicalSize.height / ratio;
    sink.heatmapTap(
      e.position.dx,
      e.position.dy,
      width,
      height,
      keyboardVisible: view.viewInsets.bottom > 0,
      inputTarget: track.inputTarget,
      ignored: track.ignored,
    );
  }

  static ui.FlutterView? _viewOf(int viewId) {
    final dispatcher = WidgetsBinding.instance.platformDispatcher;
    final view = dispatcher.view(id: viewId);
    if (view != null) return view;
    final all = dispatcher.views;
    return all.isEmpty ? null : all.first;
  }

  static ui.FlutterView? _mainView() {
    final dispatcher = WidgetsBinding.instance.platformDispatcher;
    final views = dispatcher.views;
    return dispatcher.implicitView ?? (views.isEmpty ? null : views.first);
  }

  /// What is under the pointer: a text input (an `EditableText` render
  /// object in the hit test path, or a focused text input) or an ignored area.
  ({bool input, bool ignored}) _inspect(PointerDownEvent e) {
    var input = false, ignored = false;
    final result = HitTestResult();
    WidgetsBinding.instance.hitTestInView(result, e.position, e.viewId);
    for (final entry in result.path) {
      final target = entry.target;
      if (target is RenderEditable) input = true;
      if (target is RenderPulseHeatmapIgnore) ignored = true;
    }
    return (input: input || _editing(), ignored: ignored);
  }

  /// A text input has the focus: the user is typing, so no tap is kept even
  /// when the on-screen keyboard is hidden (hardware keyboard).
  static bool _editing() {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) return false;
    return context.widget is EditableText ||
        context.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  // ---- debug screenshot ----

  void _screenChanged() {
    _shotTimer?.cancel();
    _shotTimer = null;
    try {
      if (!_debugBuild() || !sink.heatmapActive) return;
      final screen = sink.heatmapScreen;
      if (screen == null) return;
      _shotTimer = Timer(shotDelay, () => unawaited(shootNow(screen)));
    } catch (_) {
      /* A picture is optional. */
    }
  }

  /// Takes and uploads the picture of the current screen when the server
  /// wants one. True when it was stored. Never throws. [screen] is the screen
  /// the picture was planned for: nothing is sent when it changed since.
  Future<bool> shootNow([String? screen]) async {
    if (_shooting) return false;
    _shooting = true;
    try {
      if (!_debugBuild() || !sink.heatmapActive) return false;
      final expected = screen ?? sink.heatmapScreen;
      final view = _mainView();
      if (view == null ||
          expected == null ||
          _keyboardUp(view) ||
          PulseSdkUi.visible) {
        return false;
      }
      final ratio = view.devicePixelRatio;
      final ticket = await sink.heatmapShotTicket(
        view.physicalSize.width / ratio,
        view.physicalSize.height / ratio,
      );
      if (ticket == null ||
          sink.heatmapScreen != expected ||
          _keyboardUp(view) ||
          PulseSdkUi.visible) {
        return false;
      }
      final bytes = await captureViewPng(view.viewId);
      if (bytes == null || sink.heatmapScreen != expected) return false;
      return await sink.heatmapScreenshot(ticket, bytes, 'image/png');
    } catch (_) {
      return false;
    } finally {
      _shooting = false;
    }
  }

  static bool _keyboardUp(ui.FlutterView view) => view.viewInsets.bottom > 0;
}

class _Track {
  _Track(this.start);
  final Offset start;
  bool valid = true, inputTarget = false, ignored = false;
}
