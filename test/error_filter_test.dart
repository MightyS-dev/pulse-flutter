import 'package:flutter_test/flutter_test.dart';
import 'package:mightys_pulse/src/core/error_filter.dart';

void main() {
  const vectors = <String, (String, String)>{
    'email': (
      'failed for jane.doe+x@example.co.uk today',
      'failed for <filtered> today',
    ),
    'url with query': (
      'GET https://pulse.mightys.dev/v1/items?token=abc&id=7 failed',
      'GET https://pulse.mightys.dev/v1/items<filtered> failed',
    ),
    'url with fragment': (
      'see https://pulse.mightys.dev/docs/page#section-2 now',
      'see https://pulse.mightys.dev/docs/page<filtered> now',
    ),
    'uuid': (
      'order 123e4567-e89b-12d3-a456-426614174000 missing',
      'order <filtered> missing',
    ),
    'ipv4': ('connect to 10.1.2.3 refused', 'connect to <filtered> refused'),
    'ipv6 full': (
      'peer 2001:0db8:85a3:0000:0000:8a2e:0370:7334 closed',
      'peer <filtered> closed',
    ),
    'ipv6 compressed': (
      'peer fe80::1ff:fe23:4567:890a closed',
      'peer <filtered> closed',
    ),
    'six digit run': (
      'account 1234567 not found',
      'account <filtered> not found',
    ),
    'hex literal kept': (
      'at MyApp+0x1234567 and abs 0x00000071a2b3c4d5',
      'at MyApp+0x1234567 and abs 0x00000071a2b3c4d5',
    ),
    'five digit run kept': ('code 12345 not found', 'code 12345 not found'),
    'unix path': (
      'cannot read /data/user/0/com.example.app/files/state.db',
      'cannot read state.db',
    ),
    'windows path': (
      r'cannot read C:\Users\jane\AppData\state.db',
      'cannot read state.db',
    ),
    'frame with path and line': (
      'Cart.checkout /srv/work/cart.dart:42',
      'Cart.checkout cart.dart:42',
    ),
  };

  test('the shared vector table (12 cases)', () {
    expect(vectors.length, greaterThanOrEqualTo(12));
    vectors.forEach((name, pair) {
      expect(ErrorFilter.apply(pair.$1), pair.$2, reason: name);
    });
  });

  test('file URLs keep only the file name', () {
    expect(
      ErrorFilter.apply('opened file:///srv/data/state.db ok'),
      'opened state.db ok',
    );
  });

  test('ordinary text is left alone and the filter is idempotent', () {
    expect(
      ErrorFilter.apply('Foo::bar and a/b and 10:30:45'),
      'Foo::bar and a/b and 10:30:45',
    );
    for (final pair in vectors.values) {
      final once = ErrorFilter.apply(pair.$1);
      expect(ErrorFilter.apply(once), once);
    }
  });

  test('a frame keeps the line and column after a file name', () {
    expect(
      ErrorFilter.apply('checkout app.js:1:234567', frame: true),
      'checkout app.js:1:234567',
    );
    expect(
      ErrorFilter.apply('Cart.swift:1234567', frame: true),
      'Cart.swift:1234567',
    );
    expect(
      ErrorFilter.apply('order 1234567 Cart.kt:42', frame: true),
      'order <filtered> Cart.kt:42',
    );
  });

  test('a message has no line and column exemption', () {
    expect(
      ErrorFilter.apply('failed at app.js:1:234567'),
      'failed at app.js:1:<filtered>',
    );
  });
}
