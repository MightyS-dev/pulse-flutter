import 'dart:convert';
import 'heatmap.dart';
import 'screen_views.dart';

/// Type of the error signal. A normal signal: field groups apply, the
/// automatic-signal switches do not.
const errorSignalType = 'pulse.error';

/// Automatic signal types a portal setting can switch off.
const sessionStartedType = 'pulse.session_started';
const newInstallType = 'pulse.new_install';
const appUpdatedType = 'pulse.app_updated';
const appOpenedType = 'pulse.app_opened';
const appBackgroundedType = 'pulse.app_backgrounded';
const deepLinkType = 'pulse.deep_link';
const permissionChangedType = 'pulse.permission_changed';

/// Automatic types that are sent only when the cached portal settings list
/// them in `enabledSignals`.
const optInSignalTypes = {appOpenedType, appBackgroundedType};
const automaticSignalTypes = {
  sessionStartedType,
  newInstallType,
  appUpdatedType,
  screenViewType,
  appOpenedType,
  appBackgroundedType,
  deepLinkType,
  permissionChangedType,
};

/// Types the portal can disable or pause: the automatic ones and
/// `pulse.heatmap` (which has its own switch and no AE1 quota).
const configurableSignalTypes = {...automaticSignalTypes, heatmapType};

/// Field groups and the `system` keys each one owns. The base system keys
/// (platform, OS, app version, build, device model, locale, SDK, bundle id)
/// belong to no group and are never removed.
const fieldGroups = <String, List<String>>{
  'device': [
    'deviceType',
    'deviceBrand',
    'architecture',
    'osApiLevel',
    'runtimeVersion',
    'scriptingBackend',
    'isSimulator',
    'targetEnvironment',
    'extensionId',
  ],
  'screen': [
    'screenWidth',
    'screenHeight',
    'screenScale',
    'screenWidthPx',
    'screenHeightPx',
    'screenDpi',
    'screenCount',
    'orientation',
  ],
  'settings': [
    'colorScheme',
    'layoutDirection',
    'timeZone',
    'utcOffsetMinutes',
    'language',
    'preferredLanguage',
    'region',
    'fontScale',
    'contentSizeCategory',
    'reduceMotion',
    'boldText',
    'invertColors',
    'increaseContrast',
    'reduceTransparency',
    'differentiateWithoutColor',
    'fontWeightAdjustment',
  ],
  'network': ['connectionType', 'lowPowerMode'],
  'app': ['appName', 'installSource', 'isDebugBuild'],
  'usage': [
    'isNewInstall',
    'firstSessionDate',
    'totalSessionsCount',
    'distinctDaysUsed',
    'distinctDaysUsedLastMonth',
    'previousSessionSeconds',
    'averageSessionSeconds',
    'sessionSeconds',
    'launchMs',
    'foregroundsToday',
    'previousForegroundSeconds',
  ],
  // Both keys need a native permission API that no dependency of this package
  // exposes, so the package never sends them. The group exists so the portal
  // switch has the same name as in the other SDKs.
  'permissions': ['notificationPermission', 'trackingPermission'],
};

/// Settings read from the portal. Everything is on unless a value says false.
class PulseConfig {
  const PulseConfig({
    this.version = 0,
    this.screenViews = true,
    this.automaticSignals = true,
    this.heatmaps = false,
    this.groups = const {},
    this.disabledSignals = const {},
    this.enabledSignals = const {},
    this.pausedSignals = const {},
  });

  /// Everything on, version 0. Used when nothing is cached or readable.
  static const defaults = PulseConfig();

  final int version;
  final bool screenViews;
  final bool automaticSignals;

  /// The portal switched heatmaps on for this app. Off unless the settings
  /// say true, so no cache or an unreadable one means off.
  final bool heatmaps;

  /// Groups switched off, by name. A missing group is on.
  final Map<String, bool> groups;
  final Set<String> disabledSignals;

  /// Opt-in types the portal switched on. Empty when nothing is cached.
  final Set<String> enabledSignals;

  /// Types the server paused (for example near the plan limit).
  final Set<String> pausedSignals;

  /// Parses a response body defensively. Returns null when [text] is not a
  /// JSON object. Unknown keys are ignored, missing or non-boolean values mean
  /// on, unknown signal names are ignored. Never throws.
  static PulseConfig? parse(String text) {
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, Object?>) return null;
      bool flag(Object? v) => v is bool ? v : true;
      final rawVersion = decoded['version'];
      final version = rawVersion is num && rawVersion.isFinite
          ? rawVersion.toInt()
          : 0;
      final rawGroups = decoded['groups'];
      final groups = <String, bool>{};
      if (rawGroups is Map<String, Object?>) {
        for (final name in fieldGroups.keys) {
          groups[name] = flag(rawGroups[name]);
        }
      }
      final rawDisabled = decoded['disabledSignals'];
      final disabled = <String>{};
      if (rawDisabled is List<Object?>) {
        for (final item in rawDisabled) {
          if (item is String && configurableSignalTypes.contains(item)) {
            disabled.add(item);
          }
        }
      }
      Set<String> names(Object? raw, Set<String> known) => {
        if (raw is List<Object?>)
          for (final item in raw)
            if (item is String && known.contains(item)) item,
      };
      return PulseConfig(
        enabledSignals: names(decoded['enabledSignals'], optInSignalTypes),
        pausedSignals: names(decoded['pausedSignals'], configurableSignalTypes),
        heatmaps: decoded['heatmaps'] == true,
        version: version < 0 ? 0 : version,
        screenViews: flag(decoded['screenViews']),
        automaticSignals: flag(decoded['automaticSignals']),
        groups: groups,
        disabledSignals: disabled,
      );
    } catch (_) {
      return null;
    }
  }

  /// Canonical form written to the `config` file.
  List<int> encode() => utf8.encode(
    jsonEncode({
      'version': version,
      'screenViews': screenViews,
      'automaticSignals': automaticSignals,
      'heatmaps': heatmaps,
      'groups': {for (final n in fieldGroups.keys) n: groups[n] ?? true},
      'disabledSignals': disabledSignals.toList()..sort(),
      'enabledSignals': enabledSignals.toList()..sort(),
      'pausedSignals': pausedSignals.toList()..sort(),
    }),
  );

  /// Whether the portal lets a signal of [type] through. Only automatic types
  /// can be switched off or paused, and the opt-in ones are sent only when
  /// they are listed in [enabledSignals].
  bool allows(String type) {
    if (type == heatmapType) {
      return heatmaps &&
          automaticSignals &&
          screenViews &&
          !disabledSignals.contains(screenViewType) &&
          !disabledSignals.contains(type) &&
          !pausedSignals.contains(type);
    }
    if (!automaticSignalTypes.contains(type)) return true;
    if (!automaticSignals ||
        disabledSignals.contains(type) ||
        pausedSignals.contains(type)) {
      return false;
    }
    if (optInSignalTypes.contains(type) && !enabledSignals.contains(type)) {
      return false;
    }
    return type != screenViewType || screenViews;
  }

  /// Whether the portal allows screen views (automatic or manual).
  bool get screenViewsAllowed => allows(screenViewType);

  /// [system] without the keys of every group switched off.
  Map<String, String> filterSystem(Map<String, String> system) {
    final off = [
      for (final e in fieldGroups.entries)
        if (groups[e.key] == false) ...e.value,
    ];
    if (off.isEmpty) return system;
    return {
      for (final e in system.entries)
        if (!off.contains(e.key)) e.key: e.value,
    };
  }
}
