import 'dart:convert';

/// One automatic signal produced when a session begins.
class AutoSignal {
  const AutoSignal(this.type, [this.props = const {}]);
  final String type;
  final Map<String, Object?> props;
}

/// Session statistics kept for this install. Pure state: the runtime owns
/// reading and writing the small `usage` file.
class UsageStats {
  UsageStats({this.newInstall = false});

  /// True from the first session after install until the second one starts.
  bool newInstall;
  String? firstDate;
  int total = 0;
  int lifetimeDays = 0;
  List<String> days = [];

  /// Completed sessions as [end in ms since epoch, seconds], newest last.
  List<List<int>> durations = [];
  int? previous;
  DateTime? openStart, openLast;
  String? lastVersion, lastBuild;
  DateTime? _savedLast;
  bool dirty = false;

  static const _keepDays = 90, _windowDays = 30, _maxDurations = 2000;

  /// Local calendar date as YYYY-MM-DD.
  static String dateOf(DateTime local) =>
      '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';

  /// Starts a session at [now] and returns the automatic signals it causes.
  List<AutoSignal> beginSession(
    DateTime now,
    DateTime Function(DateTime) local,
    String version,
    String build,
  ) {
    final signals = <AutoSignal>[];
    _closeOpen();
    final fresh = total == 0;
    if (fresh && newInstall) {
      signals.add(const AutoSignal('pulse.new_install'));
    } else if (!fresh) {
      newInstall = false;
    }
    final changed =
        lastVersion != null &&
        lastBuild != null &&
        (lastVersion != version || lastBuild != build);
    if (changed) {
      signals.add(
        AutoSignal('pulse.app_updated', {
          'previousVersion': lastVersion,
          'previousBuild': lastBuild,
        }),
      );
    }
    signals.add(const AutoSignal('pulse.session_started'));
    lastVersion = version;
    lastBuild = build;
    total++;
    final date = dateOf(local(now));
    firstDate ??= date;
    if (!days.contains(date)) {
      days.add(date);
      lifetimeDays++;
    }
    _pruneDays(date);
    _pruneDurations(now);
    openStart = now;
    openLast = now;
    _savedLast = now;
    dirty = true;
    return signals;
  }

  void _closeOpen() {
    final start = openStart, last = openLast;
    if (start == null || last == null) {
      return;
    }
    final seconds = last.difference(start).inSeconds;
    final safe = seconds < 0 ? 0 : seconds;
    durations.add([last.millisecondsSinceEpoch, safe]);
    previous = safe;
    openStart = null;
    openLast = null;
  }

  void _pruneDays(String today) {
    final cutoff = _cutoffDate(today);
    days = days.where((d) => d.compareTo(cutoff) > 0).toList();
  }

  static String _cutoffDate(String today) {
    final y = int.parse(today.substring(0, 4));
    final m = int.parse(today.substring(5, 7));
    final d = int.parse(today.substring(8, 10));
    return dateOf(
      DateTime.utc(y, m, d).subtract(const Duration(days: _windowDays)),
    );
  }

  void _pruneDurations(DateTime now) {
    final cutoff = now
        .subtract(const Duration(days: _keepDays))
        .millisecondsSinceEpoch;
    durations = durations.where((e) => e[0] >= cutoff).toList();
    if (durations.length > _maxDurations) {
      durations = durations.sublist(durations.length - _maxDurations);
    }
  }

  /// Records activity; marks the state for saving at most every 30 seconds.
  void touch(DateTime now) {
    openLast = now;
    final saved = _savedLast;
    if (saved == null || now.difference(saved).inSeconds >= 30) {
      dirty = true;
    }
  }

  void markSaved() {
    dirty = false;
    _savedLast = openLast;
  }

  /// The wire fields for a signal at [now].
  Map<String, String> fields(DateTime now, DateTime Function(DateTime) local) {
    final result = <String, String>{};
    if (firstDate != null) {
      result['firstSessionDate'] = firstDate!;
    }
    if (total > 0) {
      result['totalSessionsCount'] = '$total';
      result['distinctDaysUsed'] = '$lifetimeDays';
      final cutoff = _cutoffDate(dateOf(local(now)));
      result['distinctDaysUsedLastMonth'] =
          '${days.where((d) => d.compareTo(cutoff) > 0).length}';
    }
    if (newInstall && total == 1) {
      result['isNewInstall'] = 'true';
    }
    if (previous != null) {
      result['previousSessionSeconds'] = '$previous';
    }
    if (durations.isNotEmpty) {
      final sum = durations.fold<int>(0, (a, e) => a + e[1]);
      result['averageSessionSeconds'] = '${(sum / durations.length).round()}';
    }
    final start = openStart;
    if (start != null) {
      final seconds = now.difference(start).inSeconds;
      result['sessionSeconds'] = '${seconds < 0 ? 0 : seconds}';
    }
    return result;
  }

  List<int> encode() => utf8.encode(
    jsonEncode({
      'v': 1,
      'newInstall': newInstall,
      'first': firstDate,
      'total': total,
      'lifetimeDays': lifetimeDays,
      'days': days,
      'durations': durations,
      'previous': previous,
      'open': openStart == null || openLast == null
          ? null
          : [
              openStart!.millisecondsSinceEpoch,
              openLast!.millisecondsSinceEpoch,
            ],
      'version': lastVersion,
      'build': lastBuild,
    }),
  );

  /// Parses stored state; null when the bytes are not valid state.
  static UsageStats? decode(List<int> bytes) {
    try {
      final map = jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
      final stats = UsageStats(newInstall: map['newInstall'] == true)
        ..firstDate = _date(map['first'])
        ..total = (map['total'] as num).toInt()
        ..lifetimeDays = (map['lifetimeDays'] as num).toInt()
        ..days = [
          for (final d in map['days'] as List<Object?>)
            if (_date(d) != null) d as String,
        ]
        ..durations = [
          for (final e in map['durations'] as List<Object?>)
            [((e as List<Object?>)[0] as num).toInt(), (e[1] as num).toInt()],
        ]
        ..previous = (map['previous'] as num?)?.toInt()
        ..lastVersion = map['version'] as String?
        ..lastBuild = map['build'] as String?;
      final open = map['open'] as List<Object?>?;
      if (open != null) {
        stats.openStart = DateTime.fromMillisecondsSinceEpoch(
          (open[0] as num).toInt(),
          isUtc: true,
        );
        stats.openLast = DateTime.fromMillisecondsSinceEpoch(
          (open[1] as num).toInt(),
          isUtc: true,
        );
      }
      return stats;
    } catch (_) {
      return null;
    }
  }

  static String? _date(Object? value) =>
      value is String && RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)
      ? value
      : null;
}
