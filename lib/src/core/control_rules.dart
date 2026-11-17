import 'dart:convert';

/// ISO 8601 times with a `Z` or an offset.
abstract final class ControlTime {
  static final _pattern = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})[Tt ](\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,9}))?(Z|z|[+-]\d{2}:?\d{2})?$',
  );

  /// The instant, or null when [text] is not a valid time.
  static DateTime? parse(String text) {
    final m = _pattern.firstMatch(text.trim());
    if (m == null) return null;
    final year = int.parse(m[1]!), month = int.parse(m[2]!);
    final day = int.parse(m[3]!);
    final hour = int.parse(m[4]!), minute = int.parse(m[5]!);
    final second = int.parse(m[6]!);
    if (month < 1 ||
        month > 12 ||
        day < 1 ||
        day > _daysIn(year, month) ||
        hour > 23 ||
        minute > 59 ||
        second > 59) {
      return null;
    }
    final fraction = m[7];
    final millis = fraction == null
        ? 0
        : int.parse(fraction.padRight(3, '0').substring(0, 3));
    var offset = 0;
    final zone = m[8];
    if (zone != null && zone[0] != 'Z' && zone[0] != 'z') {
      final digits = zone.substring(1).replaceAll(':', '');
      final h = int.parse(digits.substring(0, 2));
      final mm = int.parse(digits.substring(2));
      if (h > 23 || mm > 59) return null;
      offset = (h * 60 + mm) * (zone[0] == '-' ? -1 : 1);
    }
    return DateTime.utc(
      year,
      month,
      day,
      hour,
      minute,
      second,
      millis,
    ).subtract(Duration(minutes: offset));
  }

  static int _daysIn(int year, int month) => switch (month) {
    2 => (year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)) ? 29 : 28,
    4 || 6 || 9 || 11 => 30,
    _ => 31,
  };
}

class ControlUpdateRule {
  const ControlUpdateRule({
    this.min,
    this.latest,
    this.mode,
    this.storeVersion,
    this.storeUrl,
  });
  final String? min, latest, mode, storeVersion, storeUrl;
}

class ControlBlocked {
  const ControlBlocked(this.version, this.platforms, this.allowContinue);
  final String? version;
  final Set<String>? platforms;
  final bool allowContinue;
}

class ControlMaintenance {
  const ControlMaintenance({
    required this.startsAt,
    required this.endsAt,
    required this.headsUpMinutes,
    required this.exemptAboveStore,
    required this.platforms,
  });
  final DateTime startsAt, endsAt;
  final int headsUpMinutes;
  final bool exemptAboveStore;
  final Set<String>? platforms;
}

class ControlAnnouncement {
  const ControlAnnouncement({
    required this.id,
    required this.until,
    this.title,
    this.body,
    this.url,
    this.buttonText,
    this.platforms,
  });
  final String id;
  final String? title, body, url, buttonText;
  final DateTime until;
  final Set<String>? platforms;
}

class ControlWhatsNew {
  const ControlWhatsNew(this.version, this.body);
  final String? version, body;
}

class ControlCustom {
  const ControlCustom(this.title, this.body, this.buttonText);
  final String? title, body, buttonText;
}

/// The rules of format 1. A field of the wrong type counts as missing and
/// unknown fields are ignored, so a surprise in the answer never turns into a
/// lock.
class ControlRules {
  const ControlRules({
    required this.format,
    required this.version,
    required this.off,
    required this.update,
    required this.blocked,
    required this.maintenance,
    required this.announcement,
    required this.whatsNew,
    required this.custom,
    required this.disabledSdkVersions,
  });

  /// Largest body that is read.
  static const maxBytes = 65536;

  final int? format;
  final int version;
  final bool off;
  final Map<String, ControlUpdateRule> update;
  final List<ControlBlocked> blocked;
  final ControlMaintenance? maintenance;
  final ControlAnnouncement? announcement;
  final ControlWhatsNew? whatsNew;
  final Map<String, ControlCustom> custom;
  final List<String> disabledSdkVersions;

  /// The rules of a good answer, or null when the bytes are not a JSON object
  /// of format 1 within the size limit. Never throws.
  static ControlRules? parse(List<int> bytes) {
    if (bytes.isEmpty || bytes.length > maxBytes) return null;
    try {
      final root = jsonDecode(utf8.decode(bytes));
      if (root is! Map<String, Object?>) return null;
      final rules = fromMap(root);
      return rules.format == 1 ? rules : null;
    } catch (_) {
      return null;
    }
  }

  static String? _text(Object? v) => v is String ? v : null;

  static int? _integer(Object? v) => v is int
      ? v
      : v is num && v.isFinite && v == v.truncate()
      ? v.toInt()
      : null;

  static Map<String, Object?>? _object(Object? v) =>
      v is Map<String, Object?> ? v : null;

  static Set<String>? _platforms(Map<String, Object?> m) {
    final raw = m['platforms'];
    return raw is List ? raw.whereType<String>().toSet() : null;
  }

  static DateTime? _time(Object? v) =>
      v is String ? ControlTime.parse(v) : null;

  static ControlRules fromMap(Map<String, Object?> root) {
    final update = <String, ControlUpdateRule>{};
    _object(root['update'])?.forEach((key, value) {
      final rule = _object(value);
      if (rule == null) return;
      update[key] = ControlUpdateRule(
        min: _text(rule['min']),
        latest: _text(rule['latest']),
        mode: _text(rule['mode']),
        storeVersion: _text(rule['storeVersion']),
        storeUrl: _text(rule['storeUrl']),
      );
    });
    final blocked = <ControlBlocked>[];
    final rawBlocked = root['blocked'];
    if (rawBlocked is List) {
      for (final item in rawBlocked) {
        final m = _object(item);
        if (m == null) continue;
        blocked.add(
          ControlBlocked(
            _text(m['version']),
            _platforms(m),
            m['allowContinue'] == true,
          ),
        );
      }
    }
    ControlMaintenance? maintenance;
    final m = _object(root['maintenance']);
    if (m != null) {
      final starts = _time(m['startsAt']), ends = _time(m['endsAt']);
      if (starts != null && ends != null) {
        maintenance = ControlMaintenance(
          startsAt: starts,
          endsAt: ends,
          headsUpMinutes: _integer(m['headsUpMinutes']) ?? 0,
          exemptAboveStore: m['exemptAboveStore'] == true,
          platforms: _platforms(m),
        );
      }
    }
    ControlAnnouncement? announcement;
    final a = _object(root['announcement']);
    if (a != null) {
      final until = _time(a['until']);
      final id = _text(a['id']);
      if (until != null && id != null) {
        announcement = ControlAnnouncement(
          id: id,
          until: until,
          title: _text(a['title']),
          body: _text(a['body']),
          url: _text(a['url']),
          buttonText: _text(a['buttonText']),
          platforms: _platforms(a),
        );
      }
    }
    final w = _object(root['whatsNew']);
    final custom = <String, ControlCustom>{};
    _object(_object(root['texts'])?['custom'])?.forEach((key, value) {
      final entry = _object(value);
      if (entry == null) return;
      custom[key] = ControlCustom(
        _text(entry['title']),
        _text(entry['body']),
        _text(entry['buttonText']),
      );
    });
    final rawDisabled = root['disabledSdkVersions'];
    return ControlRules(
      format: _integer(root['format']),
      version: _integer(root['version']) ?? 0,
      off: root['off'] == true,
      update: update,
      blocked: blocked,
      maintenance: maintenance,
      announcement: announcement,
      whatsNew: w == null
          ? null
          : ControlWhatsNew(_text(w['version']), _text(w['body'])),
      custom: custom,
      disabledSdkVersions: rawDisabled is List
          ? rawDisabled.whereType<String>().toList()
          : const [],
    );
  }
}
