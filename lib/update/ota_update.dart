import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

class OtaLatest {
  final String version; // e.g. 1.0.2+4
  final String sha1;

  OtaLatest({required this.version, required this.sha1});

  static OtaLatest fromJson(Map<String, dynamic> json) {
    return OtaLatest(
      version: (json['version'] as String).trim(),
      sha1: (json['sha1'] as String).trim(),
    );
  }
}

/// Compare versions like "1.0.2+4"
/// Returns -1 if a<b, 0 if equal, +1 if a>b.
int compareAppVersions(String a, String b) {
  VersionParts pa = VersionParts.parse(a);
  VersionParts pb = VersionParts.parse(b);

  int cmp = pa.major.compareTo(pb.major);
  if (cmp != 0) return cmp;
  cmp = pa.minor.compareTo(pb.minor);
  if (cmp != 0) return cmp;
  cmp = pa.patch.compareTo(pb.patch);
  if (cmp != 0) return cmp;

  // If both have build numbers: compare them.
  // If only one has build: treat missing build as 0.
  return (pa.build ?? 0).compareTo(pb.build ?? 0);
}

class VersionParts {
  final int major;
  final int minor;
  final int patch;
  final int? build;

  VersionParts({required this.major, required this.minor, required this.patch, required this.build});

  static VersionParts parse(String s) {
    final parts = s.trim().split('+');
    final core = parts[0];
    final build = (parts.length > 1) ? int.tryParse(parts[1]) : null;

    final coreParts = core.split('.');
    int major = coreParts.isNotEmpty ? int.tryParse(coreParts[0]) ?? 0 : 0;
    int minor = coreParts.length > 1 ? int.tryParse(coreParts[1]) ?? 0 : 0;
    int patch = coreParts.length > 2 ? int.tryParse(coreParts[2]) ?? 0 : 0;

    return VersionParts(major: major, minor: minor, patch: patch, build: build);
  }
}

class OtaUpdateState {
  final OtaLatest latest;
  final String currentVersion; // same format as latest
  final bool downloading;
  final double progress; // 0..1
  final String? error;
  final String? downloadedPath;

  bool get updateAvailable => compareAppVersions(latest.version, currentVersion) > 0;

  const OtaUpdateState({
    required this.latest,
    required this.currentVersion,
    required this.downloading,
    required this.progress,
    required this.error,
    required this.downloadedPath,
  });

  OtaUpdateState copyWith({
    OtaLatest? latest,
    String? currentVersion,
    bool? downloading,
    double? progress,
    String? error,
    String? downloadedPath,
  }) {
    return OtaUpdateState(
      latest: latest ?? this.latest,
      currentVersion: currentVersion ?? this.currentVersion,
      downloading: downloading ?? this.downloading,
      progress: progress ?? this.progress,
      error: error,
      downloadedPath: downloadedPath ?? this.downloadedPath,
    );
  }
}

class OtaUpdateController extends ChangeNotifier {
  OtaUpdateController({
    Dio? dio,
    this.latestJsonUrl = 'https://herz.moe/verhaarm/latest.json',
    this.apkUrlTemplate = 'https://herz.moe/verhaarm/verhaarm-release-<VERSION>.apk',
  }) : _dio = dio ?? Dio();

  final Dio _dio;

  final String latestJsonUrl;
  final String apkUrlTemplate;

  static const _platform = MethodChannel('verhaaarm.ota');

  OtaUpdateState? _state;
  OtaUpdateState? get state => _state;

  Timer? _timer;
  bool _checkInFlight = false;

  void startPeriodicChecks({Duration interval = const Duration(hours: 24)}) {
    // Android only
    if (kIsWeb || !Platform.isAndroid) return;

    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => checkNow());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> checkNow() async {
    if (kIsWeb || !Platform.isAndroid) return;
    if (_checkInFlight) return;
    _checkInFlight = true;

    try {
      final pkg = await PackageInfo.fromPlatform();
      final current = '${pkg.version}+${pkg.buildNumber}';

      final res = await _dio.get<String>(
        latestJsonUrl,
        options: Options(responseType: ResponseType.plain),
      );

      final map = jsonDecode(res.data ?? '{}') as Map<String, dynamic>;
      final latest = OtaLatest.fromJson(map);

      final newState = OtaUpdateState(
        latest: latest,
        currentVersion: current,
        downloading: false,
        progress: 0,
        error: null,
        downloadedPath: null,
      );

      _state = newState;
      notifyListeners();
    } catch (e) {
      // keep last state; you can log if you want
    } finally {
      _checkInFlight = false;
    }
  }

  String _apkUrlFor(String version) => apkUrlTemplate.replaceAll('<VERSION>', version);

  Future<void> downloadLatest() async {
    final st = _state;
    if (st == null) return;
    if (!st.updateAvailable) return;
    if (kIsWeb || !Platform.isAndroid) return;

    final url = _apkUrlFor(st.latest.version);

    try {
      final dir = await getTemporaryDirectory();
      final safeVersion = st.latest.version.replaceAll('/', '_');
      final outPath = '${dir.path}/verhaaarm-$safeVersion.apk';

      _state = st.copyWith(downloading: true, progress: 0, error: null, downloadedPath: null);
      notifyListeners();

      await _dio.download(
        url,
        outPath,
        options: Options(
          responseType: ResponseType.bytes,
          followRedirects: true,
          receiveTimeout: const Duration(minutes: 10),
        ),
        onReceiveProgress: (received, total) {
          if (total <= 0) return;
          final p = received / total;
          final cur = _state;
          if (cur == null) return;
          _state = cur.copyWith(progress: p);
          notifyListeners();
        },
      );

      final cur = _state;
      if (cur == null) return;

      _state = cur.copyWith(downloading: false, progress: 1.0, downloadedPath: outPath);
      notifyListeners();
    } catch (e) {
      final cur = _state;
      if (cur == null) return;
      _state = cur.copyWith(downloading: false, error: e.toString());
      notifyListeners();
    }
  }

  Future<void> installDownloaded() async {
    final st = _state;
    if (st == null) return;
    final path = st.downloadedPath;
    if (path == null) return;
    if (kIsWeb || !Platform.isAndroid) return;

    final canInstall = await _platform.invokeMethod<bool>('canInstallUnknownApps') ?? false;
    if (!canInstall) {
      await _platform.invokeMethod('openUnknownAppsSettings');
      return;
    }

    await _platform.invokeMethod('installApk', {'path': path});
  }
}
