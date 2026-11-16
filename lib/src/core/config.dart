import 'dart:convert';
import 'screen_views.dart';

/// Automatic signal types a portal setting can switch off.
const sessionStartedType = 'pulse.session_started';
const newInstallType = 'pulse.new_install';
const appUpdatedType = 'pulse.app_updated';
const automaticSignalTypes = {
  sessionStartedType,
  newInstallType,
  appUpdatedType,
  screenViewType,
};

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
  ],
};

/// Settings read from the portal. Everything is on unless a value says false.
class PulseConfig {
  const PulseConfig({
    this.version = 0,
    this.screenViews = true,
    this.automaticSignals = true,
    this.groups = const {},
    this.disabledSignals = const {},
  });

  /// Everything on, version 0. Used when nothing is cached or readable.
  static const defaults = PulseConfig();

  final int version;
  final bool screenViews;
  final bool automaticSignals;

  /// Groups switched off, by name. A missing group is on.
  final Map<String, bool> groups;
  final Set<String> disabledSignals;

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
          if (item is String && automaticSignalTypes.contains(item)) {
            disabled.add(item);
          }
        }
      }
      return PulseConfig(
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
      'groups': {for (final n in fieldGroups.keys) n: groups[n] ?? true},
      'disabledSignals': disabledSignals.toList()..sort(),
    }),
  );

  /// Whether the portal lets a signal of [type] through. Only the four
  /// automatic types can be switched off.
  bool allows(String type) {
    if (!automaticSignalTypes.contains(type)) return true;
    if (!automaticSignals || disabledSignals.contains(type)) return false;
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
