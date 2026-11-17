import 'control_rules.dart';
import 'control_version.dart';

/// What the SDK knows when it decides.
class ControlInput {
  const ControlInput({
    required this.rules,
    required this.now,
    required this.platform,
    required this.appVersion,
    this.debug = false,
    this.sdk = '',
    this.fromCache = false,
    this.cacheAgeHours = 0,
    this.updateReturns = 0,
    this.playUpdateNotAvailable = false,
    this.canBuildStoreLink = true,
    this.canOpenStore = true,
    this.suggestDismissedHoursAgo,
    this.shownAnnouncements = const {},
    this.justUpdated = false,
    this.whatsNewShown = false,
  });
  final ControlRules? rules;
  final DateTime now;
  final String platform, appVersion;
  final bool debug;

  /// `sdkName@sdkVersion` exactly as the SDK sends `system.sdkName` and
  /// `system.sdkVersion`.
  final String sdk;
  final bool fromCache;
  final double cacheAgeHours;

  /// How many times the user pressed Update and came back on the same version.
  final int updateReturns;
  final bool playUpdateNotAvailable;

  /// The SDK can build a store link itself when `storeUrl` is missing.
  final bool canBuildStoreLink;

  /// The app has a way to open a store link at all. False in the built-in
  /// screens when the app gave no opener: then there is no way out of a
  /// required update and it becomes a suggestion.
  final bool canOpenStore;
  final double? suggestDismissedHoursAgo;
  final Set<String> shownAnnouncements;
  final bool justUpdated, whatsNewShown;
}

/// One main state, whether the user may continue, banners (`testBuild`,
/// `maintenanceUpcoming`) and at most one card.
class ControlOutcome {
  const ControlOutcome(this.state, this.allowContinue, this.banners, this.card);
  static const normal = ControlOutcome('normal', true, [], null);
  final String state;
  final bool allowContinue;
  final List<String> banners;
  final String? card;

  ControlOutcome copyWith({String? state, List<String>? banners}) =>
      ControlOutcome(
        state ?? this.state,
        allowContinue,
        banners ?? this.banners,
        card,
      );
}

/// The App Control decision, the same in every SDK. Doubt always means no
/// lock: an incomparable version is never below a minimum and never blocked,
/// locking rules from a cache older than 30 days are ignored, and the loop
/// guard turns a required update into a suggestion whenever there is no way
/// out.
abstract final class ControlDecision {
  static const cacheLockHours = 30.0 * 24;
  static const cacheMaintenanceHours = 72;
  static const suggestQuietHours = 24.0;
  static const updateReturnsLimit = 3;

  static ControlOutcome decide(ControlInput input) {
    final rules = input.rules;
    if (rules == null ||
        rules.format != 1 ||
        rules.off ||
        rules.disabledSdkVersions.contains(input.sdk)) {
      return ControlOutcome.normal;
    }
    final staleLocks = input.fromCache && input.cacheAgeHours > cacheLockHours;
    final platformRule = rules.update[input.platform];
    final storeVersion = platformRule?.storeVersion;
    final aboveStore =
        storeVersion != null &&
        ControlVersion.compare(input.appVersion, storeVersion) == 1;
    final banners = <String>[];
    var main = 'normal';
    var allowContinue = true;

    // 2. Maintenance inside its window (from the cache never past 72 hours
    // after the start), unless exempt.
    final maintenance = rules.maintenance;
    if (maintenance != null && _covers(maintenance.platforms, input.platform)) {
      final inWindow =
          !maintenance.startsAt.isAfter(input.now) &&
          input.now.isBefore(maintenance.endsAt) &&
          (!input.fromCache ||
              input.now.isBefore(
                maintenance.startsAt.add(
                  const Duration(hours: cacheMaintenanceHours),
                ),
              ));
      final exempt = maintenance.exemptAboveStore && aboveStore;
      if (inWindow && !exempt) {
        main = 'maintenance';
        allowContinue = false;
      }
      if (input.now.isBefore(maintenance.startsAt) &&
          !maintenance.startsAt
              .subtract(Duration(minutes: maintenance.headsUpMinutes))
              .isAfter(input.now)) {
        banners.add('maintenanceUpcoming');
      }
    }
    // 3. A blocked version.
    if (main == 'normal' && !staleLocks) {
      for (final entry in rules.blocked) {
        if (ControlVersion.compare(input.appVersion, entry.version) == 0 &&
            _covers(entry.platforms, input.platform)) {
          main = 'versionBlocked';
          allowContinue = entry.allowContinue;
          break;
        }
      }
    }
    // 4. Below the minimum (review safe: a version above the store version
    // never is), then the loop guard.
    final min = platformRule?.min;
    if (main == 'normal' &&
        platformRule != null &&
        min != null &&
        ControlVersion.compare(input.appVersion, min) == -1 &&
        !aboveStore) {
      switch (platformRule.mode) {
        case 'required':
          if (!staleLocks) {
            final noWayOut =
                (storeVersion != null &&
                    (ControlVersion.compare(storeVersion, input.appVersion) ??
                            1) <=
                        0) ||
                input.updateReturns >= updateReturnsLimit ||
                input.playUpdateNotAvailable ||
                !input.canOpenStore ||
                (platformRule.storeUrl == null && !input.canBuildStoreLink);
            if (noWayOut) {
              main = 'updateSuggested';
            } else {
              main = 'updateRequired';
              allowContinue = false;
            }
          }
        case 'suggested':
          main = 'updateSuggested';
      }
    }
    // 5. Suggested by latest.
    final latest = platformRule?.latest;
    if (main == 'normal' &&
        platformRule != null &&
        platformRule.mode == 'suggested' &&
        latest != null &&
        ControlVersion.compare(input.appVersion, latest) == -1) {
      main = 'updateSuggested';
    }
    final dismissed = input.suggestDismissedHoursAgo;
    if (main == 'updateSuggested' &&
        dismissed != null &&
        dismissed < suggestQuietHours) {
      main = 'normal';
    }
    if (main == 'updateSuggested') allowContinue = true;
    // Debug builds: every locking screen shows the test banner and Continue.
    if (input.debug &&
        (main == 'maintenance' ||
            main == 'versionBlocked' ||
            main == 'updateRequired')) {
      banners.add('testBuild');
      allowContinue = true;
    }
    // 6. At most one card: What's new first, then the announcement.
    String? card;
    final whatsNew = rules.whatsNew;
    final announcement = rules.announcement;
    if (input.justUpdated &&
        !input.whatsNewShown &&
        whatsNew != null &&
        ControlVersion.compare(input.appVersion, whatsNew.version) == 0) {
      card = 'whatsNew';
    } else if (announcement != null &&
        input.now.isBefore(announcement.until) &&
        _covers(announcement.platforms, input.platform) &&
        !input.shownAnnouncements.contains(announcement.id)) {
      card = 'announcement';
    }
    return ControlOutcome(main, allowContinue, banners, card);
  }

  static bool _covers(Set<String>? platforms, String platform) =>
      platforms == null || platforms.contains(platform);
}
