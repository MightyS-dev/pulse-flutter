import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mightys_pulse/src/platform/environment.dart';
import 'package:mightys_pulse/src/platform/host.dart';
import 'package:package_info_plus/package_info_plus.dart';

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

class PhonePlugin extends DeviceInfoPlugin {
  PhonePlugin({this.features = const [], this.physical = true});
  final List<String> features;
  final bool physical;
  @override
  Future<AndroidDeviceInfo> get androidInfo async => AndroidDeviceInfo.fromMap({
    'version': {
      'codename': 'REL',
      'incremental': '1',
      'previewSdkInt': 0,
      'release': '14',
      'sdkInt': 34,
    },
    'board': 'b',
    'bootloader': 'b',
    'brand': 'google',
    'device': 'd',
    'display': 'd',
    'fingerprint': 'f',
    'hardware': 'h',
    'host': 'h',
    'id': 'i',
    'manufacturer': 'samsung',
    'model': 'SM-S916B',
    'product': 'p',
    'tags': 't',
    'time': 0,
    'type': 't',
    'isPhysicalDevice': physical,
    'freeDiskSize': 0,
    'totalDiskSize': 0,
    'systemFeatures': features,
    'isLowRamDevice': false,
    'physicalRamSize': 0,
    'availableRamSize': 0,
  });
  @override
  Future<IosDeviceInfo> get iosInfo async => IosDeviceInfo.fromMap({
    'name': 'private-device-name',
    'systemName': 'iOS',
    'systemVersion': '18.2.1',
    'model': 'iPad',
    'modelName': 'iPad Air',
    'localizedModel': 'iPad',
    'identifierForVendor': 'private-vendor-id',
    'freeDiskSize': 0,
    'totalDiskSize': 0,
    'isPhysicalDevice': physical,
    'physicalRamSize': 0,
    'availableRamSize': 0,
    'isiOSAppOnMac': false,
    'isiOSAppOnVision': false,
    'utsname': {
      'sysname': 'Darwin',
      'nodename': 'private-node',
      'release': '24',
      'version': 'v',
      'machine': 'iPad14,8',
    },
  });
}

Future<PackageInfo> info(String? installer) async => PackageInfo(
  appName: 'My Game',
  packageName: 'com.example.game',
  version: '2.0.1',
  buildNumber: '77',
  installerStore: installer,
);

const dartVersion = '3.10.4 (stable) (Mon Nov 3 2026) on "android_arm64"';

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
      expect(result['osVersion'], '26.1.2');
      expect(result['deviceModel'], 'Mac16,1');
      expect(result['deviceBrand'], 'Apple');
      expect(result['deviceType'], 'desktop');
      expect(result['targetEnvironment'], 'native');
      expect(result.values.any((v) => v.contains('private')), false);
    },
  );
  test('architecture and runtime version come from the Dart version', () {
    expect(architectureFromDart(dartVersion), 'arm64');
    expect(architectureFromDart('3.10.4 on "linux_x64"'), 'x86_64');
    expect(architectureFromDart('3.10.4 on "ios_sim_arm64"'), 'arm64');
    expect(architectureFromDart('3.10.4 on "android_arm"'), 'armv7');
    expect(architectureFromDart('3.10.4 on "windows_ia32"'), 'x86');
    expect(architectureFromDart('3.10.4'), isNull);
    expect(runtimeVersionFromDart(dartVersion), 'Dart 3.10.4');
    expect(runtimeVersionFromDart('unknown'), isNull);
  });
  test('install source maps the installer exactly', () {
    String source(HostOs host, String? installer, {bool debug = false}) =>
        installSourceFor(host: host, installer: installer, debug: debug);
    expect(source(HostOs.android, 'com.android.vending'), 'playstore');
    expect(
      source(HostOs.android, 'com.sec.android.app.samsungapps'),
      'galaxystore',
    );
    expect(source(HostOs.android, 'com.amazon.venezia'), 'amazon');
    expect(source(HostOs.android, null), 'sideload');
    expect(source(HostOs.android, 'org.example.store'), 'other');
    expect(source(HostOs.ios, 'com.apple.testflight'), 'testflight');
    expect(source(HostOs.ios, 'com.apple'), 'appstore');
    expect(source(HostOs.ios, 'com.apple.simulator'), 'other');
    expect(source(HostOs.macos, null), 'other');
    expect(source(HostOs.android, 'com.android.vending', debug: true), 'debug');
  });
  test('device type follows system features and screen size', () {
    expect(androidDeviceType(['android.software.leanback'], 900), 'tv');
    expect(androidDeviceType(['android.hardware.type.watch'], 200), 'watch');
    expect(androidDeviceType([], 411), 'phone');
    expect(androidDeviceType([], 600), 'tablet');
    expect(androidDeviceType([], 0), isNull);
  });
  test('zone id comes from a zoneinfo path only', () {
    expect(
      ianaFromPath('/var/db/timezone/zoneinfo/Europe/Belgrade'),
      'Europe/Belgrade',
    );
    expect(ianaFromPath('/usr/share/zoneinfo/UTC'), 'UTC');
    expect(ianaFromPath('/etc/other'), isNull);
  });
  test('Android environment carries every value the platform gives', () async {
    final env = NativeEnvironment(
      host: HostOs.android,
      dartVersion: dartVersion,
      debugBuild: false,
      shortestSide: () => 411,
      packageInfo: () => info('com.android.vending'),
      deviceInfo: PhonePlugin(),
    );
    final system = await env.system();
    expect(system, containsPair('platform', 'mobile'));
    expect(system, containsPair('osName', 'Android'));
    expect(system, containsPair('osVersion', '14'));
    expect(system, containsPair('osApiLevel', '34'));
    expect(system, containsPair('deviceModel', 'SM-S916B'));
    expect(system, containsPair('deviceBrand', 'samsung'));
    expect(system, containsPair('deviceType', 'phone'));
    expect(system, containsPair('architecture', 'arm64'));
    expect(system, containsPair('runtimeVersion', 'Dart 3.10.4'));
    expect(system, containsPair('appName', 'My Game'));
    expect(system, containsPair('appVersion', '2.0.1'));
    expect(system, containsPair('appBuildNumber', '77'));
    expect(system, containsPair('bundleId', 'com.example.game'));
    expect(system, containsPair('installSource', 'playstore'));
    expect(system, containsPair('isSimulator', 'false'));
    expect(system, containsPair('isDebugBuild', 'false'));
    expect(system.containsKey('targetEnvironment'), false);
    expect(system.containsKey('extensionId'), false);
    expect(system.containsKey('timeZone'), false);
  });
  test('Android emulator, debug build and tablet are detected', () async {
    final env = NativeEnvironment(
      host: HostOs.android,
      dartVersion: dartVersion,
      debugBuild: true,
      shortestSide: () => 800,
      packageInfo: () => info(null),
      deviceInfo: PhonePlugin(physical: false),
    );
    final system = await env.system();
    expect(system, containsPair('isSimulator', 'true'));
    expect(system, containsPair('isDebugBuild', 'true'));
    expect(system, containsPair('installSource', 'debug'));
    expect(system, containsPair('deviceType', 'tablet'));
  });
  test('iOS environment names the idiom without private values', () async {
    final env = NativeEnvironment(
      host: HostOs.ios,
      dartVersion: '3.10.4 on "ios_arm64"',
      debugBuild: false,
      packageInfo: () => info('com.apple.testflight'),
      deviceInfo: PhonePlugin(),
    );
    final system = await env.system();
    expect(system, containsPair('osVersion', '18.2.1'));
    expect(system, containsPair('deviceModel', 'iPad14,8'));
    expect(system, containsPair('deviceBrand', 'Apple'));
    expect(system, containsPair('deviceType', 'tablet'));
    expect(system, containsPair('targetEnvironment', 'native'));
    expect(system, containsPair('installSource', 'testflight'));
    expect(system, containsPair('isSimulator', 'false'));
    expect(system.containsKey('osApiLevel'), false);
    expect(system.values.any((v) => v.contains('private')), false);
  });
  test('missing app info and device info leave the keys out', () async {
    final env = NativeEnvironment(
      host: HostOs.android,
      dartVersion: 'unknown',
      debugBuild: false,
      packageInfo: () async => throw StateError('none'),
      deviceInfo: _Broken(),
    );
    final system = await env.system();
    expect(system.containsKey('appName'), false);
    expect(system.containsKey('deviceBrand'), false);
    expect(system.containsKey('architecture'), false);
    expect(system.containsKey('runtimeVersion'), false);
    expect(system['installSource'], 'other');
  }, timeout: const Timeout(Duration(seconds: 10)));
}

class _Broken extends DeviceInfoPlugin {
  @override
  Future<AndroidDeviceInfo> get androidInfo async => throw StateError('none');
}
