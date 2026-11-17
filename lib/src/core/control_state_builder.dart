import 'control_decision.dart';
import 'control_rules.dart';
import 'control_state.dart';
import 'control_texts.dart';

/// What the screens need to know about the app and the device.
class ControlContext {
  const ControlContext({
    required this.appName,
    required this.appVersion,
    required this.languageTags,
    required this.fallbackStoreUrl,
    required this.now,
    this.localTime = _local,
    this.canOpenStore = true,
  });
  final String appName, appVersion;
  final List<String> languageTags;

  /// The store page the SDK can build itself, or null.
  final String? fallbackStoreUrl;
  final DateTime now;

  /// Whether the app can open a store link. Without it a screen offers no
  /// update button and a blocked version says a fix is on the way.
  final bool canOpenStore;

  /// Converts an instant to device local time (replaceable in tests).
  final DateTime Function(DateTime) localTime;
  static DateTime _local(DateTime value) => value.toLocal();
}

/// Turns a decision into the public state: texts in the right language, custom
/// texts, times in the device zone.
abstract final class ControlStateBuilder {
  static ControlState build(
    ControlOutcome outcome,
    ControlRules rules,
    ControlContext context,
    String platform,
  ) {
    final language = ControlTexts.pick(context.languageTags);
    final testBuild = outcome.banners.contains('testBuild');
    final String kind;
    if (outcome.state != 'normal') {
      kind = outcome.state;
    } else if (outcome.card != null) {
      kind = outcome.card!;
    } else if (outcome.banners.contains('maintenanceUpcoming')) {
      kind = 'maintenanceUpcoming';
    } else {
      return ControlState.normal;
    }
    final custom = rules.custom[kind];
    final rule = rules.update[platform];
    final maintenance = rules.maintenance;
    final announcement = rules.announcement;
    final whatsNew = rules.whatsNew;
    final storeUrl = rule?.storeUrl ?? context.fallbackStoreUrl;
    final version = kind == 'whatsNew'
        ? whatsNew?.version
        : rule?.storeVersion ?? rule?.latest ?? rule?.min;
    String t(String key) =>
        ControlTexts.text(language, key) ?? ControlTexts.text('en', key) ?? '';
    String? fill(String? text) => text == null
        ? null
        : _fillIn(text, context, language, version, maintenance);
    String? pick(String? own, String? key) =>
        fill(own ?? (key == null ? null : t(key)));

    // One shape for every kind: the texts come from `<kind>.title`, `.body`
    // and `.button` unless the kind says otherwise.
    final isAnnouncement = kind == 'announcement';
    final isCard = isAnnouncement || kind == 'whatsNew';
    final isUpcoming = kind == 'maintenanceUpcoming';
    final isUpdate = kind.startsWith('update') || kind == 'versionBlocked';
    final hasWindow = kind.startsWith('maintenance');
    final noUpdate =
        kind == 'versionBlocked' && (storeUrl == null || !context.canOpenStore);
    final allowed = outcome.state == 'normal' ? true : outcome.allowContinue;
    return ControlState(
      ControlKind.values.byName(kind),
      title: pick(
        custom?.title ?? (isAnnouncement ? announcement?.title : null),
        isUpcoming || isAnnouncement ? null : '$kind.title',
      ),
      body: pick(
        custom?.body ??
            (isAnnouncement
                ? announcement?.body
                : isCard
                ? whatsNew?.body
                : null),
        isUpcoming
            ? '$kind.banner'
            : isCard
            ? null
            : noUpdate
            ? 'versionBlocked.bodyNoUpdate'
            : '$kind.body',
      ),
      buttonText: isUpcoming || noUpdate
          ? null
          : pick(
              custom?.buttonText ??
                  (isAnnouncement ? announcement?.buttonText : null),
              '$kind.button',
            ),
      secondaryButtonText: outcome.allowContinue && !isCard && !isUpcoming
          ? fill(
              t(
                kind == 'updateSuggested'
                    ? 'updateSuggested.dismiss'
                    : 'continue',
              ),
            )
          : null,
      url: isUpdate
          ? storeUrl
          : isAnnouncement
          ? announcement?.url
          : null,
      startsAt: hasWindow ? maintenance?.startsAt : null,
      endsAt: hasWindow ? maintenance?.endsAt : null,
      version: isAnnouncement
          ? announcement?.id
          : isCard
          ? whatsNew?.version
          : null,
      allowContinue: allowed,
      isTestBuild: testBuild,
      testBuildText: testBuild ? fill(t('testBuild.banner')) : null,
    );
  }

  static String _fillIn(
    String text,
    ControlContext context,
    String language,
    String? version,
    ControlMaintenance? maintenance,
  ) {
    if (!text.contains('{')) return text;
    final tag = context.languageTags.isEmpty
        ? language
        : context.languageTags.first.replaceAll('_', '-');
    return text
        .replaceAll(
          '{appName}',
          context.appName.isEmpty ? 'this app' : context.appName,
        )
        .replaceAll('{version}', version ?? context.appVersion)
        .replaceAll(
          '{startTime}',
          maintenance == null ? '' : time(maintenance.startsAt, context, tag),
        )
        .replaceAll(
          '{endTime}',
          maintenance == null ? '' : time(maintenance.endsAt, context, tag),
        );
  }

  /// Short time in the device zone, with the date when it is not today. The
  /// clock has 12 hours for English and 24 hours for every other language, and
  /// the date order follows the language.
  static String time(DateTime at, ControlContext context, String tag) {
    final local = context.localTime(at);
    final today = context.localTime(context.now);
    final primary = tag.toLowerCase().split('-').first;
    String two(int v) => v.toString().padLeft(2, '0');
    final clock = primary == 'en'
        ? '${local.hour % 12 == 0 ? 12 : local.hour % 12}:${two(local.minute)} ${local.hour < 12 ? 'AM' : 'PM'}'
        : '${two(local.hour)}:${two(local.minute)}';
    if (local.year == today.year &&
        local.month == today.month &&
        local.day == today.day) {
      return clock;
    }
    final date = switch (primary) {
      'en' || 'ja' || 'ko' || 'zh' => '${local.month}/${local.day}',
      'de' || 'ru' || 'tr' || 'sr' => '${local.day}.${local.month}.',
      _ => '${local.day}/${local.month}',
    };
    return '$date $clock';
  }
}
