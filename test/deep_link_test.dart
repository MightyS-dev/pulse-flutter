import 'package:flutter_test/flutter_test.dart';
import 'package:mightys_pulse/src/core/auto_events.dart';

Map<String, Object?>? p(String link) => DeepLink.props(Uri.parse(link));

void main() {
  test('scheme, host and path; numeric and uuid segments become :id', () {
    expect(p('myapp://Shop/a/42/b/123e4567-e89b-12d3-a456-426614174000'), {
      'scheme': 'myapp',
      'host': 'shop',
      'path': '/a/:id/b/:id',
    });
  });

  test('credentials, port, query and fragment are never kept', () {
    final r = p('myapp://user:pw@box:8443/x?token=1&email=a@b.co#sec')!;
    expect(r, {'scheme': 'myapp', 'host': 'box', 'path': '/x'});
  });

  test('only the three utm tags, filtered and at most 64 characters', () {
    final r = p(
      'app://h/p?utm_source=${'a' * 100}&utm_medium=mail%40x.com'
      '&utm_campaign=c1&utm_term=nope&ref=zz',
    )!;
    expect((r['utmSource']! as String).length, 64);
    expect(r['utmMedium'], '<filtered>');
    expect(r['utmCampaign'], 'c1');
    expect(r.containsKey('utm_term'), false);
    expect(r.length, 6);
  });

  test('a first repeated utm tag wins and a missing value is skipped', () {
    final r = p('app://h/p?utm_source=a&utm_source=b&utm_medium')!;
    expect(r['utmSource'], 'a');
    expect(r.containsKey('utmMedium'), false);
  });

  test('a path is cut at 128 characters, a bare scheme link has root path', () {
    expect((p('app://h/${'x' * 300}')!['path']! as String).length, 128);
    expect(p('app://h'), {'scheme': 'app', 'host': 'h', 'path': '/'});
    expect(p('mailto:someone@example.com')!['path'], '<filtered>');
  });

  test('links without scheme or target are not usable', () {
    expect(p('/only/a/path'), isNull);
    expect(p('app://'), isNull);
    expect(p(''), isNull);
  });
}
