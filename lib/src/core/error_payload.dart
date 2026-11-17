import 'dart:convert';
import 'error_filter.dart';
import 'model.dart';
import 'options.dart';

/// Builds the `error` object of a `pulse.error` signal: type, filtered
/// message and readable frames, within fixed limits.
abstract final class ErrorPayload {
  static const maxFrames = 30;
  static const maxFrameChars = 300;
  static const maxMessageChars = 500;
  static const maxTypeChars = 200;
  static const maxBytes = 16384;
  static const _rawLimit = 4000;
  static const _scanLines = 400;

  static final _dartFrame = RegExp(r'^#\d+\s+(.*?)\s+\(([^()]*)\)$');
  static final _bareFrame = RegExp(r'^#\d+\s+(\S.*)$');
  static final _rawFrame = RegExp(
    r'^#\d+\s+abs\s+[0-9a-fA-F]+(?:\s+virt\s+[0-9a-fA-F]+)?(?:\s+\S+)?$',
  );
  static final _location = RegExp(r'^(.*?)(?::(\d+))?(?::(\d+))?$');
  static final _traceFrame = RegExp(r'^(\S+)\s+(\d+)(?::\d+)?\s+(\S.*)$');

  /// The error object for [error] and [stack], ready to encode. [stack] may be
  /// null (no frames). Frames of this package at the top are left out.
  static Map<String, Object?> from(
    String kind,
    Object error,
    StackTrace? stack,
    ErrorDetail detail,
  ) {
    String type, message;
    try {
      type = error.runtimeType.toString();
    } catch (_) {
      type = 'unknown';
    }
    try {
      message = error.toString();
    } catch (_) {
      message = '';
    }
    var text = '';
    try {
      text = stack?.toString() ?? '';
    } catch (_) {
      /* No frames. */
    }
    final parsed = frames(text, skipOwn: true);
    return build(
      kind: kind,
      type: type,
      message: message,
      frames: parsed.frames,
      symbolicated: parsed.symbolicated,
      detail: detail,
    );
  }

  /// Frames of a Dart stack trace text, top first: `Function file.dart:42`.
  /// Addresses from a build with split debug info are kept raw and make
  /// `symbolicated` false.
  static ({List<String> frames, bool symbolicated}) frames(
    String stack, {
    bool skipOwn = false,
  }) {
    final lines = stack.split('\n');
    final out = <String>[];
    var symbolicated = true;
    var leading = skipOwn;
    for (final raw in lines.take(_scanLines)) {
      if (out.length >= maxFrames) break;
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (leading && line.contains('package:mightys_pulse/')) continue;
      final frame = _frame(line);
      if (frame == null) continue;
      leading = false;
      if (frame.raw) symbolicated = false;
      out.add(frame.text);
    }
    return (frames: out, symbolicated: symbolicated);
  }

  static ({String text, bool raw})? _frame(String line) {
    if (_rawFrame.hasMatch(line)) {
      return (text: _cut(line, maxFrameChars), raw: true);
    }
    final dart = _dartFrame.firstMatch(line);
    if (dart != null) {
      return (text: _format(dart[1]!, dart[2]!), raw: false);
    }
    final trace = _traceFrame.firstMatch(line);
    if (trace != null && !line.startsWith('#')) {
      return (text: _format(trace[3]!, '${trace[1]}:${trace[2]}'), raw: false);
    }
    final bare = _bareFrame.firstMatch(line);
    if (bare != null) {
      return (text: _format(bare[1]!, ''), raw: false);
    }
    return null;
  }

  static String _format(String function, String location) {
    var file = '';
    var number = '';
    final match = _location.firstMatch(location);
    if (match != null) {
      final path = match[1] ?? '';
      file = path.substring(path.lastIndexOf(RegExp(r'[/\\]')) + 1);
      number = match[2] ?? '';
    }
    final parts = [
      function,
      if (file.isNotEmpty) number.isEmpty ? file : '$file:$number',
    ];
    return parts.join(' ');
  }

  /// Only the kind and type of [error].
  static Map<String, Object?> typeOnly(Map<String, Object?> error) => {
    'kind': error['kind'],
    'type': error['type'],
  };

  /// Applies filter and limits to values from any source.
  static Map<String, Object?> build({
    required String kind,
    required String type,
    required String? message,
    required List<String> frames,
    required bool symbolicated,
    ErrorDetail detail = ErrorDetail.full,
  }) {
    final cleanType = _clean(type, maxTypeChars, false);
    final result = <String, Object?>{
      'kind': kind,
      'type': cleanType.isEmpty ? 'unknown' : cleanType,
    };
    if (detail == ErrorDetail.typeOnly) return result;
    final text = message == null ? '' : _clean(message, maxMessageChars, true);
    if (text.isNotEmpty) result['message'] = text;
    result['frames'] = [
      for (final f in frames.take(maxFrames))
        if (_cleanFrame(f).isNotEmpty) _cleanFrame(f),
    ];
    result['symbolicated'] = symbolicated;
    return fit(result);
  }

  static String _cleanFrame(String frame) => _rawFrame.hasMatch(frame)
      ? _cut(frame, maxFrameChars)
      : _clean(frame, maxFrameChars, true, frame: true);

  /// Drops frames from the bottom, then shortens the message, until the
  /// object serializes within [maxBytes].
  static Map<String, Object?> fit(Map<String, Object?> error) {
    var frames = List<String>.of(
      (error['frames'] as List<Object?>?)?.cast<String>() ?? const [],
    );
    var message = error['message'] as String?;
    Map<String, Object?> assemble() {
      final copy = Map<String, Object?>.of(error);
      if (message != null) {
        copy['message'] = message;
      } else {
        copy.remove('message');
      }
      if (error.containsKey('frames')) copy['frames'] = frames;
      return copy;
    }

    int size() => utf8.encode(encodeJson(assemble())).length;
    while (size() > maxBytes && frames.isNotEmpty) {
      frames = frames.sublist(0, frames.length - 1);
    }
    while (size() > maxBytes && message != null) {
      final current = message;
      message = current.length <= 1 ? null : _cut(current, current.length ~/ 2);
    }
    return assemble();
  }

  static String _clean(
    String raw,
    int limit,
    bool filter, {
    bool frame = false,
  }) {
    var safe = _cut(raw, _rawLimit);
    if (!validUnicode(safe)) safe = _replaceBroken(safe);
    return _cut(filter ? ErrorFilter.apply(safe, frame: frame) : safe, limit);
  }

  static String _cut(String text, int limit) {
    if (text.length <= limit) return text;
    final unit = text.codeUnitAt(limit - 1);
    final end = unit >= 0xd800 && unit <= 0xdbff ? limit - 1 : limit;
    return text.substring(0, end);
  }

  static String _replaceBroken(String text) {
    final units = text.codeUnits;
    final out = StringBuffer();
    for (var i = 0; i < units.length; i++) {
      final c = units[i];
      if (c >= 0xd800 && c <= 0xdbff) {
        if (i + 1 < units.length &&
            units[i + 1] >= 0xdc00 &&
            units[i + 1] <= 0xdfff) {
          out
            ..writeCharCode(c)
            ..writeCharCode(units[i + 1]);
          i++;
        } else {
          out.write('�');
        }
      } else if (c >= 0xdc00 && c <= 0xdfff) {
        out.write('�');
      } else {
        out.writeCharCode(c);
      }
    }
    return out.toString();
  }
}
