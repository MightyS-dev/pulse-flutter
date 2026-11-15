import 'dart:io';
import 'dart:ui' show PlatformDispatcher;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../core/ports.dart';

class NativeEnvironment implements PulseEnvironment {
  @override
  Future<Map<String, String>> system() async {
    final os = Platform.operatingSystem;
    final result = <String, String>{
      'platform': Platform.isAndroid || Platform.isIOS ? 'mobile' : 'desktop',
      'osName': switch (os) {
        'ios' => 'iOS',
        'macos' => 'macOS',
        'windows' => 'Windows',
        'linux' => 'Linux',
        'android' => 'Android',
        _ => 'Unknown',
      },
      'osVersion': '',
      'deviceModel': '',
      'appVersion': '',
      'appBuildNumber': '',
      'locale': PlatformDispatcher.instance.locale.toLanguageTag(),
    };
    try {
      final info = await PackageInfo.fromPlatform();
      result.addAll({
        'appVersion': info.version,
        'appBuildNumber': info.buildNumber,
        'bundleId': info.packageName,
      });
    } catch (_) {
      /* App metadata is optional if the platform plugin is unavailable. */
    }
    try {
      result.addAll(await deviceSystem(DeviceInfoPlugin()));
    } catch (_) {
      /* Never substitute unique identifiers for missing model data. */
    }
    return result;
  }

  Future<Map<String, String>> deviceSystem(DeviceInfoPlugin plugin) async {
    String version = '', model = '';
    if (Platform.isAndroid) {
      final info = await plugin.androidInfo;
      version = info.version.release;
      model = info.model;
    } else if (Platform.isIOS) {
      final info = await plugin.iosInfo;
      version = info.systemVersion;
      model = info.utsname.machine;
    } else if (Platform.isMacOS) {
      final info = await plugin.macOsInfo;
      version =
          '${info.majorVersion}.${info.minorVersion}.${info.patchVersion}';
      model = info.model;
    } else if (Platform.isWindows) {
      final info = await plugin.windowsInfo;
      version = '${info.majorVersion}.${info.minorVersion}.${info.buildNumber}';
      model = 'PC';
    } else if (Platform.isLinux) {
      final info = await plugin.linuxInfo;
      version = info.versionId ?? '';
      model = 'Desktop';
    }
    return {'osVersion': pulseOsVersion(version), 'deviceModel': model};
  }
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
