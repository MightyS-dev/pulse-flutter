import 'package:flutter/material.dart';

/// Colors, shape and text styles of the built-in App Control screens. Every
/// field is optional: what is left out comes from `Theme.of(context)` of your
/// app, so the screens follow its light and dark theme.
///
/// ```dart
/// Pulse.control.theme = const PulseControlTheme(accentColor: Color(0xFF0B6E4F));
/// ```
class PulseControlTheme {
  /// Creates a theme. Omit any argument to take it from the app theme.
  const PulseControlTheme({
    this.backgroundColor,
    this.foregroundColor,
    this.accentColor,
    this.onAccentColor,
    this.scrimColor,
    this.bannerColor,
    this.onBannerColor,
    this.borderRadius,
    this.titleStyle,
    this.bodyStyle,
    this.buttonStyle,
  });

  /// Background of full screens, dialogs and cards.
  final Color? backgroundColor;

  /// Color of the title and the text.
  final Color? foregroundColor;

  /// Color of the main button.
  final Color? accentColor;

  /// Text color on the main button.
  final Color? onAccentColor;

  /// Color of the dim layer behind a dialog or a card.
  final Color? scrimColor;

  /// Background of the maintenance bar and of the test build bar.
  final Color? bannerColor;

  /// Text color on [bannerColor].
  final Color? onBannerColor;

  /// Corner radius of dialogs, cards and buttons.
  final BorderRadius? borderRadius;
  final TextStyle? titleStyle, bodyStyle, buttonStyle;
}

/// The theme the screens really use: [PulseControlTheme] on top of the app
/// theme, and the look that matches the platform.
class ControlLook {
  const ControlLook({
    required this.cupertino,
    required this.background,
    required this.foreground,
    required this.muted,
    required this.accent,
    required this.onAccent,
    required this.scrim,
    required this.banner,
    required this.onBanner,
    required this.radius,
    required this.title,
    required this.body,
    required this.button,
  });

  /// iOS and macOS get the Cupertino look, every other platform Material.
  final bool cupertino;
  final Color background,
      foreground,
      muted,
      accent,
      onAccent,
      scrim,
      banner,
      onBanner;
  final BorderRadius radius;
  final TextStyle title, body, button;

  static ControlLook resolve(BuildContext context, PulseControlTheme? theme) {
    final app = Theme.of(context);
    final scheme = app.colorScheme;
    final cupertino =
        app.platform == TargetPlatform.iOS ||
        app.platform == TargetPlatform.macOS;
    final dark = app.brightness == Brightness.dark;
    final foreground = theme?.foregroundColor ?? scheme.onSurface;
    final text = app.textTheme;
    final radius =
        theme?.borderRadius ?? BorderRadius.circular(cupertino ? 14 : 28);
    return ControlLook(
      cupertino: cupertino,
      background: theme?.backgroundColor ?? scheme.surface,
      foreground: foreground,
      muted: foreground.withValues(alpha: 0.78),
      accent: theme?.accentColor ?? scheme.primary,
      onAccent: theme?.onAccentColor ?? scheme.onPrimary,
      scrim: theme?.scrimColor ?? const Color(0x99000000),
      banner:
          theme?.bannerColor ??
          (dark ? const Color(0xFFFFD60A) : const Color(0xFFFFE066)),
      onBanner: theme?.onBannerColor ?? const Color(0xFF1C1C1E),
      radius: radius,
      title: (theme?.titleStyle ?? text.headlineSmall ?? const TextStyle())
          .copyWith(
            color: theme?.titleStyle?.color ?? foreground,
            fontWeight: theme?.titleStyle?.fontWeight ?? FontWeight.w700,
          ),
      body: (theme?.bodyStyle ?? text.bodyLarge ?? const TextStyle()).copyWith(
        color: theme?.bodyStyle?.color ?? foreground.withValues(alpha: 0.86),
        height: theme?.bodyStyle?.height ?? 1.35,
      ),
      button: (theme?.buttonStyle ?? text.labelLarge ?? const TextStyle())
          .copyWith(
            fontWeight: theme?.buttonStyle?.fontWeight ?? FontWeight.w600,
            fontSize: theme?.buttonStyle?.fontSize ?? 16,
          ),
    );
  }
}
