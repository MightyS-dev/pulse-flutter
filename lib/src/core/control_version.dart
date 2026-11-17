import 'model.dart';

/// App Control version comparison. Spaces and a `v` or `V` prefix are removed,
/// everything after the first `+` is dropped, the part after the first `-` is a
/// pre-release, the main part is dot separated numbers of any length (leading
/// zeros are ignored, a missing part is 0) and any part that is not a number
/// makes the version not comparable.
abstract final class ControlVersion {
  /// -1, 0 or 1, or null when either version cannot be compared.
  static int? compare(String? a, String? b) {
    final left = _parse(a), right = _parse(b);
    if (left == null || right == null) return null;
    final length = left.main.length > right.main.length
        ? left.main.length
        : right.main.length;
    for (var i = 0; i < length; i++) {
      final order = _number(
        i < left.main.length ? left.main[i] : '',
        i < right.main.length ? right.main[i] : '',
      );
      if (order != 0) return order;
    }
    final x = left.pre, y = right.pre;
    if (x == null || y == null) {
      return x == null && y == null
          ? 0
          : x == null
          ? 1
          : -1;
    }
    final count = x.length > y.length ? x.length : y.length;
    for (var i = 0; i < count; i++) {
      if (i >= x.length) return -1;
      if (i >= y.length) return 1;
      final p = x[i], q = y[i];
      final pNumber = _digits(p), qNumber = _digits(q);
      final order = pNumber && qNumber
          ? _number(_trim(p), _trim(q))
          : pNumber
          ? -1
          : qNumber
          ? 1
          : p.compareTo(q);
      if (order != 0) return order.sign;
    }
    return 0;
  }

  /// Whether [version] can be compared at all.
  static bool isComparable(String? version) => _parse(version) != null;

  static bool _digits(String part) =>
      part.isNotEmpty && RegExp(r'^[0-9]+$').hasMatch(part);

  /// Leading zeros removed, so "007" and "7" are the same number ("" is 0).
  static String _trim(String digits) {
    var i = 0;
    while (i < digits.length && digits.codeUnitAt(i) == 48) {
      i++;
    }
    return digits.substring(i);
  }

  /// Compares two digit strings without leading zeros as numbers of any
  /// length: the longer one is larger, else the text order is the number order.
  static int _number(String a, String b) {
    if (a.length != b.length) return a.length < b.length ? -1 : 1;
    return a.compareTo(b).sign;
  }

  static ({List<String> main, List<String>? pre})? _parse(String? text) {
    if (text == null) return null;
    var value = text.replaceAll(RegExp(r'^[ \t\n\r]+|[ \t\n\r]+$'), '');
    if (value.isNotEmpty && (value[0] == 'v' || value[0] == 'V')) {
      value = value.substring(1);
    }
    final plus = value.indexOf('+');
    if (plus >= 0) value = value.substring(0, plus);
    List<String>? pre;
    final dash = value.indexOf('-');
    if (dash >= 0) {
      final preText = value.substring(dash + 1);
      value = value.substring(0, dash);
      pre = preText.split('.');
      final allowed = RegExp(r'^[0-9A-Za-z-]+$');
      if (pre.any((part) => !allowed.hasMatch(part))) return null;
    }
    if (value.isEmpty) return null;
    final parts = value.split('.');
    if (parts.any((part) => !_digits(part))) return null;
    return (main: [for (final part in parts) _trim(part)], pre: pre);
  }
}

/// The public id of an app's rules: the first 32 hex characters of SHA-256
/// over the key exactly as it was given.
abstract final class ControlIds {
  static String forKey(String key) => hashText(key).substring(0, 32);
}
