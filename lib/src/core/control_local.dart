import 'dart:convert';

/// What App Control remembers on the device between launches. Small, local,
/// never sent.
class ControlLocal {
  const ControlLocal({
    this.appVersion,
    this.updatedTo,
    this.updateReturns = 0,
    this.pressPending,
    this.dismissedVersion,
    this.dismissedAt = 0,
    this.shownAnnouncements = const [],
    this.whatsNewShown,
  });
  static const maxIds = 20;

  /// The app version of the last launch.
  final String? appVersion;

  /// The version the app was updated to, until a later update replaces it.
  final String? updatedTo;

  /// How many times the user pressed Update and came back on the same version.
  final int updateReturns;

  /// The app version when Update was pressed and the user has not come back.
  final String? pressPending;
  final String? dismissedVersion;

  /// Milliseconds since the epoch.
  final int dismissedAt;
  final List<String> shownAnnouncements;
  final String? whatsNewShown;

  ControlLocal copyWith({
    String? appVersion,
    String? updatedTo,
    int? updateReturns,
    Object? pressPending = _keep,
    String? dismissedVersion,
    int? dismissedAt,
    List<String>? shownAnnouncements,
    String? whatsNewShown,
  }) => ControlLocal(
    appVersion: appVersion ?? this.appVersion,
    updatedTo: updatedTo ?? this.updatedTo,
    updateReturns: updateReturns ?? this.updateReturns,
    pressPending: identical(pressPending, _keep)
        ? this.pressPending
        : pressPending as String?,
    dismissedVersion: dismissedVersion ?? this.dismissedVersion,
    dismissedAt: dismissedAt ?? this.dismissedAt,
    shownAnnouncements: shownAnnouncements ?? this.shownAnnouncements,
    whatsNewShown: whatsNewShown ?? this.whatsNewShown,
  );
  static const _keep = Object();

  List<int> encode() => utf8.encode(
    jsonEncode({
      'appVersion': appVersion,
      'updatedTo': updatedTo,
      'updateReturns': updateReturns,
      'pressPending': pressPending,
      'dismissedVersion': dismissedVersion,
      'dismissedAt': dismissedAt,
      'shownAnnouncements': shownAnnouncements.length > maxIds
          ? shownAnnouncements.sublist(shownAnnouncements.length - maxIds)
          : shownAnnouncements,
      'whatsNewShown': whatsNewShown,
    }),
  );

  static String? _text(Object? v) => v is String ? v : null;
  static int _number(Object? v) => v is num && v.isFinite ? v.toInt() : 0;

  /// The saved state, or an empty one when the bytes are missing or damaged.
  static ControlLocal decode(List<int>? bytes) {
    if (bytes == null) return const ControlLocal();
    try {
      final root = jsonDecode(utf8.decode(bytes));
      if (root is! Map<String, Object?>) return const ControlLocal();
      final ids = root['shownAnnouncements'];
      final list = ids is List ? ids.whereType<String>().toList() : <String>[];
      return ControlLocal(
        appVersion: _text(root['appVersion']),
        updatedTo: _text(root['updatedTo']),
        updateReturns: _number(root['updateReturns']).clamp(0, 1000),
        pressPending: _text(root['pressPending']),
        dismissedVersion: _text(root['dismissedVersion']),
        dismissedAt: _number(root['dismissedAt']),
        shownAnnouncements: list.length > maxIds
            ? list.sublist(list.length - maxIds)
            : list,
        whatsNewShown: _text(root['whatsNewShown']),
      );
    } catch (_) {
      return const ControlLocal();
    }
  }
}
