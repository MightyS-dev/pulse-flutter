import 'dart:convert';

class Advice {
  const Advice(this.interval, this.pause);
  final double? interval;
  final bool? pause;
  static Advice? parse(String body) {
    try {
      if (body.isEmpty ||
          utf8.encode(body).length > 65536 ||
          !_Shape(body).accepts()) {
        return null;
      }
      final map = jsonDecode(body);
      if (map is! Map<String, Object?>) {
        return null;
      }
      final seconds = map['recommendedSendIntervalSeconds'];
      return Advice(
        seconds is num && seconds.isFinite && seconds > 0
            ? seconds.toDouble().clamp(5, 3600)
            : null,
        map['pause'] is bool ? map['pause']! as bool : null,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Reject ambiguous duplicate decoded keys and excessive nesting before decoding.
class _Shape {
  _Shape(this.text);
  final String text;
  int position = 0;
  bool accepts() {
    final ok = value(0);
    space();
    return ok && position == text.length;
  }

  void space() {
    while (position < text.length && ' \r\n\t'.contains(text[position])) {
      position++;
    }
  }

  bool take(String character) {
    space();
    if (position >= text.length || text[position] != character) {
      return false;
    }
    position++;
    return true;
  }

  String? string() {
    space();
    final start = position;
    if (!take('"')) {
      return null;
    }
    while (position < text.length) {
      final char = text[position++];
      if (char == '\\') {
        position++;
      } else if (char == '"') {
        return jsonDecode(text.substring(start, position)) as String;
      }
    }
    return null;
  }

  bool value(int depth) {
    if (depth > 32) {
      return false;
    }
    space();
    if (position >= text.length) {
      return false;
    }
    if (text[position] == '"') {
      return string() != null;
    }
    if (take('{')) {
      final keys = <String>{};
      if (take('}')) {
        return true;
      }
      do {
        final key = string();
        if (key == null || !keys.add(key) || !take(':') || !value(depth + 1)) {
          return false;
        }
        if (take('}')) {
          return true;
        }
      } while (take(','));
      return false;
    }
    if (take('[')) {
      if (take(']')) {
        return true;
      }
      do {
        if (!value(depth + 1)) {
          return false;
        }
        if (take(']')) {
          return true;
        }
      } while (take(','));
      return false;
    }
    final start = position;
    while (position < text.length && !' \t\r\n,]}'.contains(text[position])) {
      position++;
    }
    return position > start;
  }
}

DateTime? retryAfter(String? text, DateTime now) {
  if (text == null) {
    return null;
  }
  final seconds = double.tryParse(text);
  if (seconds != null) {
    return seconds.isFinite && seconds >= 0
        ? now.add(
            Duration(microseconds: (seconds.clamp(0, 3600) * 1000000).round()),
          )
        : null;
  }
  final match = RegExp(
    r'^[A-Za-z]{3}, (\d{2}) ([A-Za-z]{3}) (\d{4}) (\d{2}):(\d{2}):(\d{2}) GMT$',
  ).firstMatch(text);
  if (match == null) {
    return null;
  }
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final month = months.indexOf(match[2]!) + 1;
  if (month == 0) {
    return null;
  }
  final date = DateTime.utc(
    int.parse(match[3]!),
    month,
    int.parse(match[1]!),
    int.parse(match[4]!),
    int.parse(match[5]!),
    int.parse(match[6]!),
  );
  final cap = now.add(const Duration(hours: 1));
  return date.isAfter(cap) ? cap : date;
}
