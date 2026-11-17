import 'dart:convert';
import 'control_texts_data.dart';
import 'control_unpack.dart' if (dart.library.io) 'control_unpack_io.dart';

/// The built-in screen texts in 12 languages (the same strings as the shared
/// texts table), stored packed and unpacked on first use.
abstract final class ControlTexts {
  static const languages = controlTextLanguages;
  static const _keys = controlTextKeys;
  static List<String>? _texts;

  static List<String>? _values(String language) {
    final index = languages.indexOf(language);
    if (index < 0) return null;
    var all = _texts;
    if (all == null) {
      try {
        all = utf8
            .decode(controlGunzip(controlTextsPacked.codeUnits))
            .split('\n');
      } catch (_) {
        all = const [];
      }
      _texts = all;
    }
    final start = index * _keys.length;
    return all.length < start + _keys.length
        ? null
        : all.sublist(start, start + _keys.length);
  }

  /// Every text of [language] by key (empty for an unknown language).
  static Map<String, String> table(String language) {
    final list = _values(language);
    if (list == null) return const {};
    return {for (var i = 0; i < _keys.length; i++) _keys[i]: list[i]};
  }

  /// One text, or null when the language or the key is unknown.
  static String? text(String language, String key) {
    final index = _keys.indexOf(key);
    final list = index < 0 ? null : _values(language);
    return list == null || index < 0 ? null : list[index];
  }

  /// The language of the first tag that has texts, else English.
  static String pick(Iterable<String> tags) {
    for (final raw in tags) {
      final tag = raw.replaceAll('_', '-').trim();
      if (tag.isEmpty) continue;
      final lower = tag.toLowerCase();
      for (final language in languages) {
        if (language.toLowerCase() == lower) return language;
      }
      final primary = lower.split('-').first;
      switch (primary) {
        case 'pt':
          return 'pt-BR';
        case 'zh':
          return 'zh-Hans';
        case 'sr':
          return 'sr-Latn';
      }
      for (final language in languages) {
        if (language.toLowerCase() == primary) return language;
      }
    }
    return 'en';
  }
}
