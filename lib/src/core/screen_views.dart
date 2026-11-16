/// Signal type sent for every screen view.
const screenViewType = 'pulse.screen_view';

/// Longest screen name that is sent.
const maxScreenNameLength = 128;

final _numeric = RegExp(r'^\d+$');
final _uuidLike = RegExp(
  r'^[0-9a-fA-F]{8}(-?[0-9a-fA-F]{4}){3}-?[0-9a-fA-F]{12}$',
);

/// Reduces a route name to a path-like name that carries no identifiers:
/// query and fragment are removed, numeric and uuid-like segments become `:id`.
String routeScreenName(String raw) {
  var name = raw.trim();
  for (final mark in ['?', '#']) {
    final at = name.indexOf(mark);
    if (at >= 0) name = name.substring(0, at);
  }
  if (name.contains('/')) {
    name = name
        .split('/')
        .map((s) => _numeric.hasMatch(s) || _uuidLike.hasMatch(s) ? ':id' : s)
        .join('/');
  }
  return name;
}

/// Name used when a route has no name: its type without generic arguments.
String routeTypeName(Object route) {
  final text = route.runtimeType.toString();
  final at = text.indexOf('<');
  return at > 0 ? text.substring(0, at) : text;
}

/// Sends one screen view per distinct screen: the same screen appearing again
/// with no other screen in between is ignored.
class ScreenViews {
  ScreenViews(this._send);
  final void Function(String type, Map<String, Object?> props) _send;
  String? _current;

  /// True when the observer may capture screens (the `automaticScreenViews` option).
  bool automatic = true;

  /// Whether the portal settings allow screen views right now.
  bool Function() portalAllows = _always;
  static bool _always() => true;

  /// A screen seen by the navigator observer: needs the code option and the portal.
  void observed(String name) {
    if (!automatic) return;
    screen(name);
  }

  /// Records [name] as the current screen. Empty names are ignored, and
  /// nothing is sent when the portal switched screen views off.
  void screen(String name) {
    if (!portalAllows()) return;
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final clipped = trimmed.length > maxScreenNameLength
        ? trimmed.substring(0, maxScreenNameLength)
        : trimmed;
    final previous = _current;
    if (previous == clipped) return;
    _current = clipped;
    _send(screenViewType, {'screen': clipped, 'previousScreen': ?previous});
  }
}
