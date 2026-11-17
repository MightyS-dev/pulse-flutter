import 'package:flutter/material.dart';
import 'control.dart';
import 'control_buttons.dart';
import 'control_theme.dart';
import 'control_views.dart';
import 'core/control_state.dart';

/// "Update available": a dialog with Update and Not now.
class ControlDialog extends StatelessWidget {
  const ControlDialog({
    super.key,
    required this.state,
    required this.control,
    required this.look,
  });
  final ControlState state;
  final PulseControl control;
  final ControlLook look;

  void _update() {
    if (control.openStore()) control.dismiss();
  }

  @override
  Widget build(BuildContext context) {
    final canUpdate =
        state.buttonText != null && controlCanUpdate(state, control);
    final secondary = state.secondaryButtonText;
    final cupertino = look.cupertino;
    final textAlign = cupertino ? TextAlign.center : TextAlign.start;
    final actions = <Widget>[
      if (canUpdate)
        ControlTextButton(
          look: look,
          label: state.buttonText!,
          onPressed: _update,
          bold: true,
        ),
      if (secondary != null)
        ControlTextButton(
          look: look,
          label: secondary,
          onPressed: control.dismiss,
        ),
    ];
    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: state.title,
      child: Stack(
        children: [
          ModalBarrier(color: look.scrim, dismissible: false),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: cupertino ? 300 : 360),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Material(
                    color: look.background,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: look.radius),
                    clipBehavior: Clip.antiAlias,
                    child: ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
                      children: [
                        if (state.title != null)
                          Semantics(
                            header: true,
                            child: Text(
                              state.title!,
                              textAlign: textAlign,
                              style: look.title.copyWith(
                                fontSize: cupertino ? 18 : 22,
                              ),
                            ),
                          ),
                        if (state.body != null) ...[
                          const SizedBox(height: 10),
                          Text(
                            state.body!,
                            textAlign: textAlign,
                            style: look.body.copyWith(fontSize: 15),
                          ),
                        ],
                        const SizedBox(height: 16),
                        ...actions,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// An announcement or what is new: a card at the bottom over a dim layer.
class ControlCard extends StatelessWidget {
  const ControlCard({
    super.key,
    required this.state,
    required this.control,
    required this.look,
  });
  final ControlState state;
  final PulseControl control;
  final ControlLook look;

  void _primary() {
    if (state.kind == ControlKind.announcement &&
        state.url != null &&
        control.canOpenStore) {
      control.openStore();
    }
    control.dismiss();
  }

  @override
  Widget build(BuildContext context) {
    final cupertino = look.cupertino;
    final textAlign = cupertino ? TextAlign.center : TextAlign.start;
    final radius = BorderRadius.circular(cupertino ? 20 : 28);
    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: state.title,
      child: Stack(
        children: [
          ModalBarrier(
            color: look.scrim,
            dismissible: true,
            onDismiss: control.dismiss,
            semanticsLabel: state.secondaryButtonText,
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Material(
                    color: look.background,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: radius),
                    clipBehavior: Clip.antiAlias,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
                      child: ListView(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        children: [
                          if (state.title != null)
                            Semantics(
                              header: true,
                              child: Text(
                                state.title!,
                                textAlign: textAlign,
                                style: look.title.copyWith(fontSize: 20),
                              ),
                            ),
                          if (state.body != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              state.body!,
                              textAlign: textAlign,
                              style: look.body,
                            ),
                          ],
                          const SizedBox(height: 18),
                          if (state.buttonText != null)
                            ControlPrimaryButton(
                              look: look,
                              label: state.buttonText!,
                              onPressed: _primary,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
