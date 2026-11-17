import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'control_theme.dart';

/// The main button: filled, full width, Material or Cupertino by platform.
class ControlPrimaryButton extends StatelessWidget {
  const ControlPrimaryButton({
    super.key,
    required this.look,
    required this.label,
    required this.onPressed,
  });
  final ControlLook look;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      label,
      textAlign: TextAlign.center,
      style: look.button.copyWith(color: look.onAccent),
    );
    if (look.cupertino) {
      return CupertinoButton(
        color: look.accent,
        borderRadius: look.radius,
        minimumSize: const Size.fromHeight(50),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        onPressed: onPressed,
        child: text,
      );
    }
    return FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: look.accent,
        foregroundColor: look.onAccent,
        minimumSize: const Size.fromHeight(52),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(
            look.radius.topLeft.x.clamp(0, 28),
          ),
        ),
      ),
      onPressed: onPressed,
      child: text,
    );
  }
}

/// The second button: text only, full width.
class ControlTextButton extends StatelessWidget {
  const ControlTextButton({
    super.key,
    required this.look,
    required this.label,
    required this.onPressed,
    this.bold = false,
  });
  final ControlLook look;
  final String label;
  final VoidCallback onPressed;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      label,
      textAlign: TextAlign.center,
      style: look.button.copyWith(
        color: look.accent,
        fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
      ),
    );
    if (look.cupertino) {
      return CupertinoButton(
        minimumSize: const Size.fromHeight(44),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        onPressed: onPressed,
        child: text,
      );
    }
    // Drawn as a text button by a FilledButton with no fill and no elevation
    // (the same look, ink and states as TextButton, which would add its own
    // code to every app).
    return FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0x00000000),
        foregroundColor: look.accent,
        elevation: 0,
        minimumSize: const Size.fromHeight(48),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      ),
      onPressed: onPressed,
      child: text,
    );
  }
}
