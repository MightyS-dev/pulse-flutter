import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mightys_pulse/src/platform/environment.dart';

class ModelPlugin extends DeviceInfoPlugin {
  @override
  Future<MacOsDeviceInfo> get macOsInfo async => MacOsDeviceInfo.fromMap({
    'computerName': 'private-name',
    'hostName': 'private-host',
    'arch': 'arm64',
    'model': 'Mac16,1',
    'modelName': 'MacBook Pro',
    'kernelVersion': 'Darwin kernel build',
    'osRelease': '25.0.0',
    'majorVersion': 26,
    'minorVersion': 1,
    'patchVersion': 2,
    'cpuFrequency': 0,
    'memorySize': 0,
    'activeCPUs': 1,
    'systemGUID': 'private-guid',
  });
}

void main() {
  test('OS version is major.minor with the patch only when it is not zero', () {
    expect(pulseOsVersion('26.5.0'), '26.5');
    expect(pulseOsVersion('26.5'), '26.5');
    expect(pulseOsVersion('18.6.1'), '18.6.1');
    expect(pulseOsVersion('15'), '15');
    expect(pulseOsVersion('10.0.26100'), '10.0.26100');
    expect(pulseOsVersion('Android 15 beta'), '15');
    expect(pulseOsVersion('14.2.0.1'), '14.2');
    expect(pulseOsVersion('unknown'), '');
  });
  test(
    'macOS adapter sends product OS version rather than Darwin release and only allowed fields',
    () async {
      if (!Platform.isMacOS) {
        return;
      }
      final result = await NativeEnvironment().deviceSystem(ModelPlugin());
      expect(result, {'osVersion': '26.1.2', 'deviceModel': 'Mac16,1'});
      expect(result.values.any((v) => v.contains('private')), false);
    },
  );
}
