import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:mightys_pulse/src/core/control_local.dart';

String show(ControlLocal l) => [
  l.appVersion,
  l.updatedTo,
  l.updateReturns,
  l.pressPending,
  l.dismissedVersion,
  l.dismissedAt,
  l.shownAnnouncements.join('+'),
  l.whatsNewShown,
].map((v) => v ?? '').join('|');

ControlLocal read(Object? json) =>
    ControlLocal.decode(utf8.encode(jsonEncode(json)));

void main() {
  test('what App Control remembers survives a round trip', () {
    final local = ControlLocal(
      appVersion: '1.0',
      updatedTo: '1.0',
      updateReturns: 2,
      pressPending: '0.9',
      dismissedVersion: '1.0',
      dismissedAt: 1763287200000,
      shownAnnouncements: [for (var i = 0; i < 25; i++) 'a$i'],
      whatsNewShown: '1.0',
    );
    final back = ControlLocal.decode(local.encode());
    expect(
      show(back),
      '1.0|1.0|2|0.9|1.0|1763287200000|${[for (var i = 5; i < 25; i++) 'a$i'].join('+')}|1.0',
    );
    expect(
      show(ControlLocal.decode(const ControlLocal().encode())),
      '||0|||0||',
    );
  });

  test('missing, damaged or wrongly typed data reads as empty fields', () {
    expect(show(ControlLocal.decode(null)), '||0|||0||');
    expect(show(ControlLocal.decode([0xff, 0x00])), '||0|||0||');
    expect(show(read([1, 2])), '||0|||0||');
    expect(
      show(
        read({
          'appVersion': 3,
          'updatedTo': true,
          'updateReturns': 5000,
          'pressPending': ['x'],
          'dismissedVersion': '2',
          'dismissedAt': 12.9,
          'shownAnnouncements': ['a', 1, 'b'],
          'whatsNewShown': null,
        }),
      ),
      '||1000||2|12|a+b|',
    );
    expect(show(read({'updateReturns': -4, 'dismissedAt': 'x'})), '||0|||0||');
    expect(show(read({'shownAnnouncements': 'a'})), '||0|||0||');
  });

  test(
    'copyWith keeps what it is not given and can clear the pending press',
    () {
      const base = ControlLocal(
        appVersion: '1',
        pressPending: '1',
        updateReturns: 1,
      );
      expect(show(base.copyWith(updateReturns: 2)), '1||2|1||0||');
      expect(show(base.copyWith(pressPending: null)), '1||1|||0||');
    },
  );
}
