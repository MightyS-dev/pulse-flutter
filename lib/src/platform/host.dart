import 'dart:io';

/// The operating system this process runs on, as far as Pulse cares.
enum HostOs {
  android,
  ios,
  macos,
  windows,
  linux,
  other;

  static HostOs get current {
    if (Platform.isAndroid) {
      return android;
    }
    if (Platform.isIOS) {
      return ios;
    }
    if (Platform.isMacOS) {
      return macos;
    }
    if (Platform.isWindows) {
      return windows;
    }
    if (Platform.isLinux) {
      return linux;
    }
    return other;
  }

  bool get isMobile => this == android || this == ios;
}

/// Formats a number with at most three decimals and no trailing zeros.
String shortNumber(double value) {
  if (!value.isFinite) {
    return '';
  }
  var text = value.toStringAsFixed(3);
  if (text.contains('.')) {
    text = text
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }
  return text == '-0' ? '0' : text;
}
