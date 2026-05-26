import 'package:device_info_plus/device_info_plus.dart';

Future<Map<String, dynamic>?> collectDeviceInfoPayload() async {
  try {
    final web = await DeviceInfoPlugin().webBrowserInfo;

    final ua = web.userAgent?.trim();
    final browserName = _browserName(web.browserName.name, ua);
    final browserVersion = _browserVersion(browserName, ua);
    final userAgent = ua != null && ua.isNotEmpty ? ua : null;

    return {
      'appType': 'WEB',
      'browserName': browserName,
      'browserVersion': ?browserVersion,
      'osName': _osNameFromUserAgent(ua),
      'userAgent': ?userAgent,
    };
  } catch (_) {
    return const {'appType': 'WEB'};
  }
}

String _browserName(String raw, String? ua) {
  final r = raw.trim().toLowerCase();
  final u = (ua ?? '').toLowerCase();

  if (u.contains('edg/')) return 'Edge';
  if (r.contains('chrome') || u.contains('chrome/')) return 'Chrome';
  if (r.contains('firefox') || u.contains('firefox/')) return 'Firefox';
  if (r.contains('safari') || u.contains('safari/')) return 'Safari';
  if (r.contains('opera') || u.contains('opr/')) return 'Opera';

  return 'UNKNOWN';
}

String? _browserVersion(String browserName, String? ua) {
  if (ua == null || ua.trim().isEmpty) return null;

  RegExp? re;
  switch (browserName) {
    case 'Edge':
      re = RegExp(r'Edg/([0-9.]+)');
      break;
    case 'Chrome':
      re = RegExp(r'Chrome/([0-9.]+)');
      break;
    case 'Firefox':
      re = RegExp(r'Firefox/([0-9.]+)');
      break;
    case 'Safari':
      re = RegExp(r'Version/([0-9.]+)');
      break;
    case 'Opera':
      re = RegExp(r'OPR/([0-9.]+)');
      break;
    default:
      return null;
  }

  final m = re.firstMatch(ua);
  final version = m?.group(1)?.trim();
  if (version == null || version.isEmpty) return null;

  final major = version.split('.').first;
  return major.isEmpty ? version : major;
}

String _osNameFromUserAgent(String? ua) {
  final u = (ua ?? '').toLowerCase();

  if (u.contains('android')) return 'Android';
  if (u.contains('iphone') || u.contains('ipad')) return 'iOS';
  if (u.contains('windows')) return 'Windows';
  if (u.contains('mac os x') || u.contains('macintosh')) return 'macOS';
  if (u.contains('linux')) return 'Linux';

  return 'UNKNOWN';
}
