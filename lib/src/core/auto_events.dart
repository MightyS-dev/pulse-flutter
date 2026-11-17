import 'config.dart';
import 'error_filter.dart';
import 'model.dart';
import 'screen_views.dart';

/// Quota guards for automatic signals.
abstract final class AutoQuota {
  /// Most automatic signals of one type per session. Types not listed here
  /// have no per-session cap.
  static const sessionCaps = <String, int>{
    appOpenedType: 20,
    appBackgroundedType: 20,
    deepLinkType: 10,
    permissionChangedType: 5,
    screenViewType: 100,
  };

  /// Most automatic signals per install and local day.
  static const dayCap = 300;

  /// Longest launch time that is believed (one hour, in milliseconds).
  static const maxLaunchMs = 3600000;
}

final _scheme = RegExp(r'^([A-Za-z][A-Za-z0-9+.\-]*):(.*)$', dotAll: true);
final _email = RegExp(r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}');
final _numeric = RegExp(r'^\d+$');
final _uuidLike = RegExp(
  r'^[0-9a-fA-F]{8}(-?[0-9a-fA-F]{4}){3}-?[0-9a-fA-F]{12}$',
);
const _utmTags = {
  'utm_source': 'utmSource',
  'utm_medium': 'utmMedium',
  'utm_campaign': 'utmCampaign',
};

/// Reduces a link to the props of `pulse.deep_link`: scheme, host and a path
/// without ids, plus the three utm_ tags. Never the rest of the query, a
/// fragment, credentials or a port.
abstract final class DeepLink {
  static const _maxRaw = 2048, _maxPath = 128, _maxHost = 128, _maxUtm = 64;

  /// The props for [uri], or null when it has no scheme, host or path.
  static Map<String, Object?>? props(Uri uri) {
    final raw = uri.toString();
    if (raw.length > _maxRaw || !validUnicode(raw)) return null;
    final match = _scheme.firstMatch(raw.trim());
    if (match == null) return null;
    final scheme = _cut(match[1]!.toLowerCase(), 32);
    final noFragment = match[2]!.split('#').first;
    final queryAt = noFragment.indexOf('?');
    final query = queryAt < 0 ? '' : noFragment.substring(queryAt + 1);
    var rest = queryAt < 0 ? noFragment : noFragment.substring(0, queryAt);
    var host = '';
    if (rest.startsWith('//')) {
      rest = rest.substring(2);
      final slash = rest.indexOf('/');
      final authority = slash < 0 ? rest : rest.substring(0, slash);
      rest = slash < 0 ? '' : rest.substring(slash);
      host = _cut(
        authority.split('@').last.split(':').first.toLowerCase(),
        _maxHost,
      );
      if (host.isEmpty && rest.isEmpty) return null;
    } else if (rest.trim().isEmpty) {
      return null;
    }
    final path = _cut(
      rest
          .split('/')
          .map((s) => _numeric.hasMatch(s) || _uuidLike.hasMatch(s) ? ':id' : s)
          .join('/')
          .replaceAll(_email, '<filtered>'),
      _maxPath,
    );
    return {
      'scheme': scheme,
      if (host.isNotEmpty) 'host': host,
      'path': path.isEmpty ? '/' : path,
      ..._utm(query),
    };
  }

  static Map<String, String> _utm(String query) {
    final found = <String, String>{};
    for (final pair in query.split('&').take(64)) {
      final eq = pair.indexOf('=');
      if (eq < 0) continue;
      final key = _utmTags[pair.substring(0, eq)];
      if (key == null || found.containsKey(key)) continue;
      String value;
      try {
        value = Uri.decodeQueryComponent(pair.substring(eq + 1));
      } catch (_) {
        continue;
      }
      final clean = _cut(ErrorFilter.apply(value.trim()), _maxUtm);
      if (clean.isNotEmpty && validUnicode(clean)) found[key] = clean;
    }
    return found;
  }

  static String _cut(String text, int limit) {
    if (text.length <= limit) return text;
    final high = text.codeUnitAt(limit - 1);
    return text.substring(
      0,
      high >= 0xd800 && high <= 0xdbff ? limit - 1 : limit,
    );
  }
}
