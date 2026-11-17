import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mightys_pulse/mightys_pulse.dart';
import 'package:mightys_pulse/src/client.dart';
import 'package:mightys_pulse/src/core/screen_views.dart';
import 'support.dart';

class _Page extends MaterialPageRoute<void> {
  _Page(String? name)
    : super(
        settings: RouteSettings(name: name),
        builder: (_) => const SizedBox(),
      );
}

class _Dialog extends PopupRoute<void> {
  @override
  Color? get barrierColor => null;
  @override
  bool get barrierDismissible => true;
  @override
  String? get barrierLabel => null;
  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => const SizedBox();
  @override
  Duration get transitionDuration => Duration.zero;
}

class _Setup {
  _Setup({PulseOptions options = const PulseOptions(debug: false)})
    : h = Harness(options: options) {
    client = PulseClient(() => h.runtime);
    unawaited(client.initialize('synthetic-key', options: options));
    observer = PulseNavigatorObserver(client.screens);
  }
  final Harness h;
  late final PulseClient client;
  late final PulseNavigatorObserver observer;
  Future<List<Map<String, Object?>>> sent() async {
    await h.flush();
    return h.allEvents
        .where((e) => e['type'] == 'pulse.screen_view')
        .map((e) => (e['props'] ?? {}) as Map<String, Object?>)
        .toList();
  }
}

void main() {
  test(
    'push uses settings name, then the route type; previousScreen follows',
    () async {
      final s = _Setup();
      s.observer.didPush(_Page('/home'), null);
      s.observer.didPush(_Page(null), _Page('/home'));
      expect(await s.sent(), [
        {'screen': '/home'},
        {
          'screen': '_Page',
          'previousScreen': '/home',
          'previousScreenSeconds': 0,
        },
      ]);
    },
  );

  test('pop reports the revealed route, replace reports the new one', () async {
    final s = _Setup();
    final a = _Page('a'), b = _Page('b'), c = _Page('c');
    s.observer.didPush(a, null);
    s.observer.didPush(b, a);
    s.observer.didPop(b, a);
    s.observer.didReplace(newRoute: c, oldRoute: a);
    expect((await s.sent()).map((e) => e['screen']), ['a', 'b', 'a', 'c']);
  });

  test(
    'same screen again without another in between is not repeated',
    () async {
      final s = _Setup();
      final a = _Page('a');
      s.observer.didPush(a, null);
      s.observer.didPush(_Dialog(), a);
      s.observer.didPop(_Dialog(), a);
      s.observer.didPush(_Page('a'), a);
      s.client.screen('a');
      expect(await s.sent(), [
        {'screen': 'a'},
      ]);
    },
  );

  test('popup routes are skipped', () async {
    final s = _Setup();
    s.observer.didPush(_Dialog(), null);
    s.observer.didReplace(newRoute: _Dialog());
    s.observer.didPop(_Dialog(), null);
    s.observer.didPop(_Page('b'), _Dialog());
    expect(await s.sent(), isEmpty);
  });

  test('null previous route and null route are ignored', () async {
    final s = _Setup();
    s.observer.didPop(_Page('a'), null);
    s.observer.didReplace();
    expect(await s.sent(), isEmpty);
  });

  test(
    'automaticScreenViews false: the observer does nothing, manual still works',
    () async {
      final s = _Setup(
        options: const PulseOptions(debug: false, automaticScreenViews: false),
      );
      s.observer.didPush(_Page('a'), null);
      s.client.screen('Manual');
      expect(await s.sent(), [
        {'screen': 'Manual'},
      ]);
    },
  );

  test('manual screen: trimmed, clipped to 128, empty ignored', () async {
    final s = _Setup();
    s.client.screen('  ');
    s.client.screen('x' * 300);
    final sent = await s.sent();
    expect(sent.length, 1);
    expect((sent.single['screen']! as String).length, maxScreenNameLength);
  });

  test('opt-out sends nothing', () async {
    final s = _Setup();
    await s.client.setOptOut(true);
    s.observer.didPush(_Page('a'), null);
    s.client.screen('b');
    expect(await s.sent(), isEmpty);
  });

  test('route names lose query, fragment and identifiers', () {
    expect(routeScreenName('/item/42?x=1#top'), '/item/:id');
    expect(
      routeScreenName('/u/123e4567-e89b-12d3-a456-426614174000/edit'),
      '/u/:id/edit',
    );
    expect(routeScreenName('Settings'), 'Settings');
    expect(routeTypeName(_Page(null)), '_Page');
  });

  testWidgets('Navigator 1 named routes and Navigator 2 pages in a real app', (
    wt,
  ) async {
    final s = _Setup();
    final key = GlobalKey<NavigatorState>();
    await wt.pumpWidget(
      MaterialApp(
        navigatorKey: key,
        navigatorObservers: [s.observer],
        routes: {
          '/': (_) => const Text('home'),
          '/detail/7': (_) => const Text('detail'),
        },
      ),
    );
    unawaited(key.currentState!.pushNamed('/detail/7'));
    await wt.pumpAndSettle();
    key.currentState!.pop();
    await wt.pumpAndSettle();
    expect((await s.sent()).map((e) => e['screen']), ['/', '/detail/:id', '/']);

    final s2 = _Setup();
    var showSecond = false;
    late StateSetter set;
    await wt.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            set = setState;
            return Navigator(
              observers: [s2.observer],
              pages: [
                const MaterialPage<void>(name: 'first', child: Text('1')),
                if (showSecond)
                  const MaterialPage<void>(name: 'second', child: Text('2')),
              ],
              onDidRemovePage: (_) {},
            );
          },
        ),
      ),
    );
    set(() => showSecond = true);
    await wt.pumpAndSettle();
    expect((await s2.sent()).map((e) => e['screen']), ['first', 'second']);
  });

  test('the public facade exposes one shared observer', () {
    expect(Pulse.navigatorObserver, same(Pulse.navigatorObserver));
    Pulse.screen('');
  });
}
