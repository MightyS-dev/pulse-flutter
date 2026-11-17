import 'dart:convert';
import 'package:crypto/crypto.dart';

String hashText(String text) => sha256.convert(utf8.encode(text)).toString();

bool validUnicode(String text) {
  final units = text.codeUnits;
  for (var i = 0; i < units.length; i++) {
    final c = units[i];
    if (c >= 0xd800 && c <= 0xdbff) {
      if (++i >= units.length || units[i] < 0xdc00 || units[i] > 0xdfff) {
        return false;
      }
    } else if (c >= 0xdc00 && c <= 0xdfff) {
      return false;
    }
  }
  return true;
}

/// JSON numbers without exponent notation; no locale-sensitive formatting.
String decimalNumber(num value) {
  final text = value.toString();
  if (!text.contains(RegExp('[eE]'))) {
    return text;
  }
  final parts = text.toLowerCase().split('e');
  final negative = parts[0].startsWith('-');
  final mantissa = negative ? parts[0].substring(1) : parts[0];
  final dot = mantissa.indexOf('.');
  final digits = mantissa.replaceAll('.', '');
  final position = (dot < 0 ? digits.length : dot) + int.parse(parts[1]);
  final String expanded;
  if (position <= 0) {
    expanded = '0.${'0' * -position}$digits';
  } else if (position >= digits.length) {
    expanded = digits + '0' * (position - digits.length);
  } else {
    expanded = '${digits.substring(0, position)}.${digits.substring(position)}';
  }
  return '${negative ? '-' : ''}$expanded';
}

String encodeJson(Object? value) {
  if (value is num) {
    return decimalNumber(value);
  }
  if (value is Map<String, Object?>) {
    return '{${value.entries.map((e) => '${jsonEncode(e.key)}:${encodeJson(e.value)}').join(',')}}';
  }
  if (value is List<Object?>) {
    return '[${value.map(encodeJson).join(',')}]';
  }
  return jsonEncode(value);
}

abstract final class Signal {
  static const maxBodyBytes = 1048576;

  static Map<String, Object?> sanitizeProps(
    Map<String, Object?>? source,
    void Function(String)? warn,
  ) {
    final result = <String, Object?>{};
    for (final entry in (source ?? <String, Object?>{}).entries) {
      final key = entry.key;
      Object? value = entry.value;
      if (value is bool) {
        value = value ? 'true' : 'false';
      }
      final scalar = value is String
          ? value.length <= 1024 && validUnicode(value)
          : value is num && value.isFinite;
      if (!scalar ||
          key.length > 128 ||
          !validUnicode(key) ||
          result.length >= 32) {
        warn?.call('Invalid property ignored.');
        continue;
      }
      final candidate = {...result, key: value};
      if (utf8.encode(encodeJson(candidate)).length > 8192) {
        warn?.call('Property byte limit reached.');
        continue;
      }
      result[key] = value;
    }
    return result;
  }

  /// A signal needs a type with some text in it (at most 200 characters) and
  /// a finite value, if it has one.
  static bool isValid(String type, num? value) =>
      type.trim().isNotEmpty &&
      type.length <= 200 &&
      validUnicode(type) &&
      value?.isFinite != false;

  static String? encode({
    required DateTime timestamp,
    required String session,
    String? userHash,
    required String type,
    num? value,
    Map<String, Object?>? props,
    Map<String, Object?>? error,
    Map<String, Object?>? heatmap,
    required Map<String, String> system,
    required bool debug,
    void Function(String)? warn,
  }) {
    if (!isValid(type, value)) {
      return null;
    }
    final time = DateTime.fromMillisecondsSinceEpoch(
      timestamp.millisecondsSinceEpoch,
      isUtc: true,
    ).toIso8601String();
    final object = <String, Object?>{
      'timestamp': time,
      'sessionId': session,
      'userHash': ?userHash,
      'type': type,
      'value': ?value,
      'debug': debug,
      'system': system,
      'props': sanitizeProps(props, warn),
      'error': ?error,
      'heatmap': ?heatmap,
    };
    final json = encodeJson(object);
    return utf8.encode(json).length + 2 <= maxBodyBytes ? json : null;
  }
}
