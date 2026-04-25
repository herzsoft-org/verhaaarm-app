import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';

Future<Map<String, dynamic>?> collectDeviceInfoPayload() async {
  try {
    final plugin = DeviceInfoPlugin();

    if (Platform.isAndroid) {
      final a = await plugin.androidInfo;

      return {
        'appType': 'ANDROID',
        'deviceName': _clean(a.name),
        'deviceModel': _clean('${a.manufacturer} ${a.model}'),
        'osName': 'Android',
        'osVersion': _clean(a.version.release),
      };
    }

    if (Platform.isIOS) {
      final i = await plugin.iosInfo;

      return {
        'appType': 'UNKNOWN',
        'deviceName': _clean(i.name),
        'deviceModel': _clean(i.model),
        'osName': _clean(i.systemName),
        'osVersion': _clean(i.systemVersion),
      };
    }

    if (Platform.isLinux) {
      final l = await plugin.linuxInfo;

      return {
        'appType': 'UNKNOWN',
        'deviceName': _clean(l.prettyName),
        'deviceModel': _clean(l.name),
        'osName': 'Linux',
        'osVersion': _clean(l.version),
      };
    }

    if (Platform.isWindows) {
      final w = await plugin.windowsInfo;

      return {
        'appType': 'UNKNOWN',
        'deviceName': _clean(w.computerName),
        'deviceModel': 'Windows PC',
        'osName': 'Windows',
        'osVersion': _clean(w.displayVersion),
      };
    }

    if (Platform.isMacOS) {
      final m = await plugin.macOsInfo;

      return {
        'appType': 'UNKNOWN',
        'deviceName': _clean(m.computerName),
        'deviceModel': _clean(m.model),
        'osName': 'macOS',
        'osVersion': _clean(m.osRelease),
      };
    }

    return const {'appType': 'UNKNOWN'};
  } catch (_) {
    return const {'appType': 'UNKNOWN'};
  }
}

String? _clean(String? s) {
  final v = s?.trim();
  if (v == null || v.isEmpty) return null;
  return v;
}