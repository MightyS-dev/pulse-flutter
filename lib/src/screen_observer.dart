import 'package:flutter/widgets.dart';
import 'core/screen_views.dart';

/// Reports screen views from a Navigator. Works with `Navigator` 1 and with
/// Navigator 2 routers such as go_router, where page names become route names.
///
/// Popup routes (dialogs, bottom sheets, menus) are not screens and are skipped.
/// Does nothing when the `automaticScreenViews` option is false.
class PulseNavigatorObserver extends NavigatorObserver {
  /// Creates an observer that reports to [views].
  PulseNavigatorObserver(this._views);
  final ScreenViews _views;

  void _capture(Route<dynamic>? route) {
    try {
      if (!_views.automatic || route == null || route is PopupRoute) return;
      final name = route.settings.name;
      _views.observed(
        name == null || name.trim().isEmpty
            ? routeTypeName(route)
            : routeScreenName(name),
      );
    } catch (_) {
      /* A screen view must never break navigation. */
    }
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _capture(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _capture(newRoute);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _capture(previousRoute);
}
