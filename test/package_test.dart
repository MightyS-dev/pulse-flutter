import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mightys_pulse/src/core/info.dart';

void main() {
  test('version matches pubspec and wire SDK name is stable', () {
    expect(
      File('pubspec.yaml').readAsStringSync(),
      contains('version: ${PulseInfo.version}\n'),
    );
    expect(PulseInfo.sdkName, 'pulse-flutter');
  });
}
