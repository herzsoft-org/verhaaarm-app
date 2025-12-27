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

  VersionParts({
    required this.major,
    required this.minor,
    required this.patch,
    required this.build,
  });

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

  /// If we found a higher APK already sitting in temp cache, store its version+path
  final String? cachedApkVersion;
  final String? downloadedPath;

  /// Highest available version we can offer (network latest vs cached apk)
  String get effectiveAvailableVersion {
    final c = cachedApkVersion;
    if (c == null || c.isEmpty) return latest.version;
    return compareAppVersions(c, latest.version) > 0 ? c : latest.version;
  }

  bool get updateAvailable => compareAppVersions(effectiveAvailableVersion, currentVersion) > 0;

  const OtaUpdateState({
    required this.latest,
    required this.currentVersion,
    required this.downloading,
    required this.progress,
    required this.error,
    required this.cachedApkVersion,
    required this.downloadedPath,
  });

  OtaUpdateState copyWith({
    OtaLatest? latest,
    String? currentVersion,
    bool? downloading,
    double? progress,
    String? error,
    String? cachedApkVersion,
    String? downloadedPath,
  }) {
    return OtaUpdateState(
      latest: latest ?? this.latest,
      currentVersion: currentVersion ?? this.currentVersion,
      downloading: downloading ?? this.downloading,
      progress: progress ?? this.progress,
      error: error,
      cachedApkVersion: cachedApkVersion ?? this.cachedApkVersion,
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

  String _apkUrlFor(String version) => apkUrlTemplate.replaceAll('<VERSION>', version);

  // --- Cache management (temp dir) ---

  static const String _apkPrefix = 'verhaaarm-';
  static const String _apkSuffix = '.apk';

  String _safeVersionForFileName(String version) => version.replaceAll('/', '_');

  String? _extractVersionFromFileName(String name) {
    if (!name.startsWith(_apkPrefix) || !name.endsWith(_apkSuffix)) return null;
    final raw = name.substring(_apkPrefix.length, name.length - _apkSuffix.length);
    // We only ever replaced '/' -> '_' when writing; restore is optional.
    return raw.replaceAll('_', '/');
  }

  Future<Directory> _tempDir() => getTemporaryDirectory();

  Future<List<FileSystemEntity>> _listCachedApks() async {
    final dir = await _tempDir();
    if (!await dir.exists()) return const [];
    final items = await dir.list(followLinks: false).toList();
    return items.where((e) {
      final n = e.uri.pathSegments.isNotEmpty ? e.uri.pathSegments.last : '';
      return n.startsWith(_apkPrefix) && n.endsWith(_apkSuffix);
    }).toList(growable: false);
  }

  Future<void> _deleteFileQuietly(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) {
        await f.delete();
      }
    } catch (_) {
      // ignore
    }
  }

  /// Cleans cached APKs:
  /// - Deletes any cached APK with version <= currentVersion
  /// - Returns the highest cached APK with version > currentVersion (if any)
  Future<({String version, String path})?> _cleanupAndFindBestCachedApk(String currentVersion) async {
    if (kIsWeb || !Platform.isAndroid) return null;

    final cached = await _listCachedApks();

    ({String version, String path})? best;

    for (final e in cached) {
      final path = e.path;
      final name = path.split(Platform.pathSeparator).last;
      final v = _extractVersionFromFileName(name);
      if (v == null || v.isEmpty) {
        // unknown file name pattern -> delete to prevent accumulation
        await _deleteFileQuietly(path);
        continue;
      }

      final cmp = compareAppVersions(v, currentVersion);
      if (cmp <= 0) {
        // installed version is same/newer -> safe to delete (this is how we delete after successful install+restart)
        await _deleteFileQuietly(path);
        continue;
      }

      if (best == null || compareAppVersions(v, best.version) > 0) {
        best = (version: v, path: path);
      }
    }

    // If multiple higher versions exist, keep only the highest and delete the rest.
    if (best != null) {
      for (final e in cached) {
        final path = e.path;
        if (path == best.path) continue;
        final name = path.split(Platform.pathSeparator).last;
        final v = _extractVersionFromFileName(name);
        if (v == null) continue;
        if (compareAppVersions(v, currentVersion) > 0) {
          await _deleteFileQuietly(path);
        }
      }
    }

    return best;
  }

  /// Delete all cached APKs except `keepPath` (or delete all if keepPath is null)
  Future<void> _purgeCachedApks({String? keepPath}) async {
    final cached = await _listCachedApks();
    for (final e in cached) {
      if (keepPath != null && e.path == keepPath) continue;
      await _deleteFileQuietly(e.path);
    }
  }

  // --- OTA flow ---

  Future<void> checkNow() async {
    if (kIsWeb || !Platform.isAndroid) return;
    if (_checkInFlight) return;
    _checkInFlight = true;

    try {
      final pkg = await PackageInfo.fromPlatform();
      final current = '${pkg.version}+${pkg.buildNumber}';

      // First: cleanup old APKs and detect cached newer one (for "Install" after restart)
      final bestCached = await _cleanupAndFindBestCachedApk(current);

      // Default latest (in case network fails): use cached as "latest" so banner can still appear
      OtaLatest latestFallback = OtaLatest(
        version: bestCached?.version ?? current,
        sha1: '',
      );

      OtaLatest latest;
      try {
        final res = await _dio.get<String>(
          latestJsonUrl,
          options: Options(responseType: ResponseType.plain),
        );
        final map = jsonDecode(res.data ?? '{}') as Map<String, dynamic>;
        latest = OtaLatest.fromJson(map);
      } catch (_) {
        latest = latestFallback;
      }

      final newState = OtaUpdateState(
        latest: latest,
        currentVersion: current,
        downloading: false,
        progress: 0,
        error: null,
        cachedApkVersion: bestCached?.version,
        downloadedPath: bestCached?.path,
      );

      _state = newState;
      notifyListeners();
    } catch (_) {
      // keep last state
    } finally {
      _checkInFlight = false;
    }
  }

  Future<void> downloadLatest() async {
    final st = _state;
    if (st == null) return;
    if (kIsWeb || !Platform.isAndroid) return;

    // We download the network-latest version, not "effective".
    // (If you want to download "effective", you must also host it.)
    final targetVersion = st.latest.version;

    // If there is no update available, no need to download.
    if (compareAppVersions(targetVersion, st.currentVersion) <= 0) return;

    final url = _apkUrlFor(targetVersion);

    try {
      final dir = await _tempDir();
      final safeVersion = _safeVersionForFileName(targetVersion);
      final outPath = '${dir.path}/verhaaarm-$safeVersion.apk';

      // Prevent accumulation: keep only the file we are about to write (or none).
      await _purgeCachedApks(keepPath: null);

      _state = st.copyWith(
        downloading: true,
        progress: 0,
        error: null,
        cachedApkVersion: null,
        downloadedPath: null,
      );
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

      // After download: keep only this one APK in cache.
      await _purgeCachedApks(keepPath: outPath);

      _state = cur.copyWith(
        downloading: false,
        progress: 1.0,
        cachedApkVersion: targetVersion,
        downloadedPath: outPath,
      );
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

    // If the file vanished (Android cache purge), clear state
    final f = File(path);
    if (!await f.exists()) {
      _state = st.copyWith(cachedApkVersion: null, downloadedPath: null);
      notifyListeners();
      return;
    }

    final canInstall = await _platform.invokeMethod<bool>('canInstallUnknownApps') ?? false;
    if (!canInstall) {
      await _platform.invokeMethod('openUnknownAppsSettings');
      return;
    }

    await _platform.invokeMethod('installApk', {'path': path});

    // Do NOT delete here: we don't know if user completed install.
    // Cleanup happens on next app start/checkNow() when currentVersion >= apkVersion.
  }
}
