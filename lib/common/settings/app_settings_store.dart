import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../models/dtos.dart';
import '../cache/app_cache.dart';

class AppSettingsStore extends ChangeNotifier {
  AppSettingsStore._();

  static final AppSettingsStore I = AppSettingsStore._();

  static const storageKey = 'settings.user.v1';

  static const keyUiTheme = 'ui.theme';
  static const keyFilterPhilister = 'users.filterPhilister';

  static const knownKeys = <String>{
    keyUiTheme,
    keyFilterPhilister,
  };

  final Map<String, _LocalSetting> _settings = {};

  bool _syncing = false;

  ThemeMode get themeMode {
    final value = _valueOf(keyUiTheme, fallback: 'DARK').toUpperCase();
    return value == 'LIGHT' ? ThemeMode.light : ThemeMode.dark;
  }

  bool get hidePhilister {
    final value = _valueOf(keyFilterPhilister, fallback: 'false').toLowerCase();
    return value == 'true';
  }

  Future<void> initLocal() async {
    final entry = await AppCache.I.entryOrLoadPersisted<Map<String, _LocalSetting>>(
      storageKey,
      decode: (json) {
        final raw = json as Map;
        final parsed = <String, _LocalSetting>{};

        for (final entry in raw.entries) {
          final key = entry.key.toString();
          if (!knownKeys.contains(key)) continue;

          final value = entry.value;
          if (value is Map) {
            parsed[key] = _LocalSetting.fromJson(
              value.cast<String, dynamic>(),
            );
          }
        }

        return parsed;
      },
    );

    _settings
      ..clear()
      ..addAll(entry?.value ?? const {});
    _ensureDefaults();

    notifyListeners();
  }

  Future<void> syncWithBackend(ApiClient api) async {
    if (_syncing) return;
    _syncing = true;

    try {
      final remote = await api.getMySettings();
      final patches = <UserSettingPatchDto>[];

      for (final key in knownKeys) {
        final local = _settings[key];
        final backend = remote.settings[key];

        if (backend == null) {
          if (local != null && local.changedAt != null) {
            patches.add(
              UserSettingPatchDto(
                key: key,
                value: local.value,
                changedAt: local.changedAt!,
              ),
            );
          }
          continue;
        }

        final backendUpdatedAt = backend.updatedAt;
        final localChangedAt = local?.changedAt;

        final backendIsNewer = backendUpdatedAt != null &&
            (localChangedAt == null || backendUpdatedAt.isAfter(localChangedAt));

        final localIsNewer = localChangedAt != null &&
            (backendUpdatedAt == null || localChangedAt.isAfter(backendUpdatedAt));

        if (backendIsNewer || local == null) {
          _settings[key] = _LocalSetting(
            value: _sanitizeValue(key, backend.value),
            changedAt: backendUpdatedAt,
          );
        } else if (localIsNewer) {
          patches.add(
            UserSettingPatchDto(
              key: key,
              value: local.value,
              changedAt: localChangedAt,
            ),
          );
        }
      }

      _ensureDefaults();
      await _persist();

      if (patches.isNotEmpty) {
        await api.patchMySettings(patches);
      }

      notifyListeners();
    } catch (_) {
      // Keep local settings if the backend is temporarily unavailable.
    } finally {
      _syncing = false;
    }
  }

  Future<void> setThemeMode(ApiClient api, ThemeMode mode) async {
    final value = mode == ThemeMode.light ? 'LIGHT' : 'DARK';
    await _setKnownSetting(api, keyUiTheme, value);
  }

  Future<void> setHidePhilister(ApiClient api, bool value) async {
    await _setKnownSetting(api, keyFilterPhilister, value ? 'true' : 'false');
  }

  Future<void> clearLocalSettings() async {
    _settings.clear();
    await AppCache.I.removePersisted(storageKey);
    _ensureDefaults();
    notifyListeners();
  }

  String _valueOf(String key, {required String fallback}) {
    return _settings[key]?.value ?? fallback;
  }

  Future<void> _setKnownSetting(ApiClient api, String key, String rawValue) async {
    final now = DateTime.now().toUtc();
    final value = _sanitizeValue(key, rawValue);

    _settings[key] = _LocalSetting(value: value, changedAt: now);
    await _persist();
    notifyListeners();

    try {
      await api.patchMySettings([
        UserSettingPatchDto(
          key: key,
          value: value,
          changedAt: now,
        ),
      ]);
    } catch (_) {
      // Local value stays newer and will be uploaded during the next sync.
    }
  }

  void _ensureDefaults() {
    _settings.putIfAbsent(
      keyUiTheme,
          () => const _LocalSetting(value: 'DARK', changedAt: null),
    );
    _settings.putIfAbsent(
      keyFilterPhilister,
          () => const _LocalSetting(value: 'false', changedAt: null),
    );
  }

  String _sanitizeValue(String key, String value) {
    switch (key) {
      case keyUiTheme:
        final upper = value.toUpperCase();
        return upper == 'LIGHT' ? 'LIGHT' : 'DARK';

      case keyFilterPhilister:
        final lower = value.toLowerCase();
        return lower == 'true' ? 'true' : 'false';

      default:
        return value;
    }
  }

  Future<void> _persist() async {
    await AppCache.I.setPersisted<Map<String, _LocalSetting>>(
      storageKey,
      Map.unmodifiable(_settings),
      encode: (settings) => settings.map(
            (key, value) => MapEntry(key, value.toJson()),
      ),
    );
  }
}

class _LocalSetting {
  final String value;
  final DateTime? changedAt;

  const _LocalSetting({
    required this.value,
    required this.changedAt,
  });

  Map<String, dynamic> toJson() => {
    'value': value,
    'changedAt': changedAt?.toUtc().toIso8601String(),
  };

  factory _LocalSetting.fromJson(Map<String, dynamic> json) {
    return _LocalSetting(
      value: (json['value'] ?? '').toString(),
      changedAt: DateTime.tryParse((json['changedAt'] ?? '').toString()),
    );
  }
}
