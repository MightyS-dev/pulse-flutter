import 'package:flutter/material.dart';
import 'control.dart';
import 'control_theme.dart';
import 'control_views.dart';
import 'core/control_state.dart';
import 'sdk_ui.dart';

/// Puts the App Control screens above the app. Created by
/// `Pulse.control.builder`; the app itself stays where it is in the tree, so
/// switching a screen on or off never rebuilds it.
class PulseControlHost extends StatefulWidget {
  const PulseControlHost({
    super.key,
    required this.control,
    required this.child,
  });
  final PulseControl control;
  final Widget child;

  @override
  State<PulseControlHost> createState() => _PulseControlHostState();
}

class _PulseControlHostState extends State<PulseControlHost>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    widget.control.hostMounted(true);
    PulseSdkUi.visible = _active;
    widget.control.listenable.addListener(_changed);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(PulseControlHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.control != widget.control) {
      oldWidget.control.listenable.removeListener(_changed);
      widget.control.listenable.addListener(_changed);
    }
  }

  /// The state changed: only this widget builds again, the app below keeps its
  /// element (the same child widget instance).
  void _changed() {
    PulseSdkUi.visible = _active;
    setState(() {});
  }

  @override
  void dispose() {
    widget.control.listenable.removeListener(_changed);
    WidgetsBinding.instance.removeObserver(this);
    PulseSdkUi.visible = false;
    widget.control.hostMounted(false);
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final locale = Localizations.maybeLocaleOf(context);
    widget.control.setAppLanguage(locale?.toLanguageTag());
  }

  bool get _active =>
      widget.control.mode == ControlMode.automatic &&
      widget.control.state.isActive;

  /// The system Back button never closes the app from an App Control screen:
  /// a locking screen swallows it, a screen the user may leave treats it as
  /// "Not now" or "Continue", the bar lets it through.
  @override
  Future<bool> didPopRoute() async {
    if (!_active) return false;
    final state = widget.control.state;
    if (state.kind == ControlKind.maintenanceUpcoming) return false;
    if (state.allowContinue) widget.control.dismiss();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final control = widget.control;
    final state = control.state;
    final show = control.mode == ControlMode.automatic && state.isActive;
    final locks = show && controlLocksApp(state);
    return Stack(
      fit: StackFit.passthrough,
      children: [
        ExcludeSemantics(
          excluding: locks,
          child: ExcludeFocus(
            excluding: locks,
            child: IgnorePointer(ignoring: locks, child: widget.child),
          ),
        ),
        if (show)
          Positioned.fill(
            child: ControlOverlay(
              state: state,
              control: control,
              look: ControlLook.resolve(context, control.theme),
            ),
          ),
      ],
    );
  }
}
