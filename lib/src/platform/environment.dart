import 'dart:io';
import 'dart:ui' show PlatformDispatcher;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:package_info_plus/package_info_plus.dart';
import '../core/ports.dart';
import 'host.dart';

/// Device and app values that do not change while the app runs.
class NativeEnvironment implements PulseEnvironment {
  NativeEnvironment({
    HostOs? host,
    String? dartVersion,
    bool? debugBuild,
    double Function()? shortestSide,
    Future<PackageInfo> Function()? packageInfo,
    DeviceInfoPlugin? deviceInfo,
  }) : _host = host ?? HostOs.current,
       _dartVersion = dartVersion ?? Platform.version,
       _debug = debugBuild ?? kDebugMode,
       _shortestSide = shortestSide ?? _logicalShortestSide,
       _packageInfo = packageInfo ?? PackageInfo.fromPlatform,
       _deviceInfo = deviceInfo;
  final HostOs _host;
  final String _dartVersion;
  final bool _debug;
  final double Function() _shortestSide;
  final Future<PackageInfo> Function() _packageInfo;
  final DeviceInfoPlugin? _deviceInfo;

  static double _logicalShortestSide() {
    final displays = PlatformDispatcher.instance.displays.toList();
    if (displays.isEmpty || displays.first.devicePixelRatio <= 0) {
      return 0;
    }
    final size = displays.first.size;
    return (size.width < size.height ? size.width : size.height) /
        displays.first.devicePixelRatio;
  }

  @override
  Future<Map<String, String>> system() async {
    final result = <String, String>{
      'platform': _host.isMobile ? 'mobile' : 'desktop',
      'osName': switch (_host) {
        HostOs.ios => 'iOS',
        HostOs.macos => 'macOS',
        HostOs.windows => 'Windows',
        HostOs.linux => 'Linux',
        HostOs.android => 'Android',
        HostOs.other => 'Unknown',
      },
      'osVersion': '',
      'deviceModel': '',
      'appVersion': '',
      'appBuildNumber': '',
      'locale': PlatformDispatcher.instance.locale.toLanguageTag(),
      'isDebugBuild': '$_debug',
    };
    final architecture = architectureFromDart(_dartVersion);
    if (architecture != null) {
      result['architecture'] = architecture;
    }
    final runtime = runtimeVersionFromDart(_dartVersion);
    if (runtime != null) {
      result['runtimeVersion'] = runtime;
    }
    try {
      final info = await _retry(_packageInfo);
      result.addAll({
        'appVersion': info.version,
        'appBuildNumber': info.buildNumber,
        'bundleId': info.packageName,
        'installSource': installSourceFor(
          host: _host,
          installer: info.installerStore,
          debug: _debug,
        ),
        if (info.appName.isNotEmpty) 'appName': info.appName,
      });
    } catch (_) {
      /* App metadata is optional if the platform plugin is unavailable. */
      result['installSource'] = _debug ? 'debug' : 'other';
    }
    try {
      result.addAll(
        await _retry(() => deviceSystem(_deviceInfo ?? DeviceInfoPlugin())),
      );
    } catch (_) {
      /* Never substitute unique identifiers for missing model data. */
      result['osVersion'] = pulseOsVersion(Platform.operatingSystemVersion);
    }
    final zone = await _timeZone();
    if (zone != null) {
      result['timeZone'] = zone;
    }
    return result;
  }

  /// Platform channels can fail right at start; try a few times quickly.
  static Future<T> _retry<T>(Future<T> Function() action) async {
    for (var attempt = 1; ; attempt++) {
      try {
        return await action();
      } catch (_) {
        if (attempt == 3) {
          rethrow;
        }
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }
  }

  /// The IANA zone id where the system file tells it (macOS and Linux); the
  /// Dart runtime itself only knows abbreviations, so mobile omits it.
  Future<String?> _timeZone() async {
    if (_host != HostOs.macos && _host != HostOs.linux) {
      return null;
    }
    try {
      final target = await Link('/etc/localtime').target();
      return ianaFromPath(target);
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, String>> deviceSystem(DeviceInfoPlugin plugin) async {
    String version = '', model = '';
    final extra = <String, String>{};
    switch (_host) {
      case HostOs.android:
        final info = await plugin.androidInfo;
        version = info.version.release;
        model = info.model;
        extra['osApiLevel'] = '${info.version.sdkInt}';
        if (info.manufacturer.isNotEmpty) {
          extra['deviceBrand'] = info.manufacturer;
        }
        extra['isSimulator'] = '${!info.isPhysicalDevice}';
        final type = androidDeviceType(info.systemFeatures, _shortestSide());
        if (type != null) {
          extra['deviceType'] = type;
        }
      case HostOs.ios:
        final info = await plugin.iosInfo;
        version = info.systemVersion;
        model = info.utsname.machine;
        extra['deviceBrand'] = 'Apple';
        extra['isSimulator'] = '${!info.isPhysicalDevice}';
        extra['targetEnvironment'] = info.isiOSAppOnMac
            ? 'ios-on-mac'
            : (info.isPhysicalDevice ? 'native' : 'simulator');
        extra['deviceType'] = info.model.toLowerCase().contains('ipad')
            ? 'tablet'
            : 'phone';
      case HostOs.macos:
        final info = await plugin.macOsInfo;
        version =
            '${info.majorVersion}.${info.minorVersion}.${info.patchVersion}';
        model = info.model;
        extra['deviceBrand'] = 'Apple';
        extra['targetEnvironment'] = 'native';
        extra['deviceType'] = 'desktop';
      case HostOs.windows:
        final info = await plugin.windowsInfo;
        version =
            '${info.majorVersion}.${info.minorVersion}.${info.buildNumber}';
        model = 'PC';
        extra['deviceType'] = 'desktop';
      case HostOs.linux:
        final info = await plugin.linuxInfo;
        version = info.versionId ?? info.version ?? '';
        model = 'Desktop';
        extra['deviceType'] = 'desktop';
      case HostOs.other:
        break;
    }
    var osVersion = pulseOsVersion(version);
    if (osVersion.isEmpty) {
      osVersion = pulseOsVersion(Platform.operatingSystemVersion);
    }
    return {'osVersion': osVersion, 'deviceModel': model, ...extra};
  }
}

/// Phone or tablet from the screen, television and watch from system features.
String? androidDeviceType(List<String> features, double shortestLogicalSide) {
  if (features.contains('android.software.leanback') ||
      features.contains('android.hardware.type.television')) {
    return 'tv';
  }
  if (features.contains('android.hardware.type.watch')) {
    return 'watch';
  }
  if (features.contains('android.hardware.type.automotive')) {
    return 'car';
  }
  if (shortestLogicalSide <= 0) {
    return null;
  }
  return shortestLogicalSide >= 600 ? 'tablet' : 'phone';
}

/// Where the app came from, from the installer the platform reports.
String installSourceFor({
  required HostOs host,
  required String? installer,
  required bool debug,
}) {
  if (debug) {
    return 'debug';
  }
  switch (host) {
    case HostOs.android:
      return switch (installer) {
        null || '' => 'sideload',
        'com.android.vending' => 'playstore',
        'com.sec.android.app.samsungapps' => 'galaxystore',
        'com.amazon.venezia' => 'amazon',
        _ => 'other',
      };
    case HostOs.ios:
      return switch (installer) {
        'com.apple.testflight' => 'testflight',
        'com.apple' => 'appstore',
        _ => 'other',
      };
    default:
      return 'other';
  }
}

/// CPU architecture of the running Dart runtime, from its version string.
String? architectureFromDart(String version) {
  final target = RegExp(r'on "([a-z0-9_]+)"').firstMatch(version)?.group(1);
  return switch (target?.split('_').last) {
    'arm64' => 'arm64',
    'x64' => 'x86_64',
    'arm' => 'armv7',
    'ia32' => 'x86',
    'riscv64' => 'riscv64',
    _ => null,
  };
}

/// The Dart version, for example `Dart 3.6.0`.
String? runtimeVersionFromDart(String version) {
  final number = RegExp(r'^\d+\.\d+\.\d+').firstMatch(version)?.group(0);
  return number == null ? null : 'Dart $number';
}

/// The zone id from a zoneinfo path such as `/usr/share/zoneinfo/Europe/Belgrade`.
String? ianaFromPath(String path) {
  final match = RegExp(r'zoneinfo/(.+)$').firstMatch(path);
  final id = match?.group(1);
  if (id == null || !RegExp(r'^[A-Za-z0-9_+\-/]{1,64}$').hasMatch(id)) {
    return null;
  }
  return id;
}

/// One format for every Pulse SDK: the leading numeric version, at most three
/// parts, with the patch part dropped when it is zero.
String pulseOsVersion(String raw) {
  final numeric = RegExp(r'\d+(?:\.\d+)*').firstMatch(raw)?.group(0) ?? '';
  if (numeric.isEmpty) {
    return '';
  }
  final parts = numeric.split('.').take(3).toList();
  if (parts.length == 3 && int.tryParse(parts[2]) == 0) {
    parts.removeLast();
  }
  return parts.join('.');
}
