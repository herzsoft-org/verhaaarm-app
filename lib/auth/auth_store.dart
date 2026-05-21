import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api/api_client.dart';
import '../models/dtos.dart';
import 'roles.dart';
import 'token_storage.dart';
import 'device_info_payload.dart';

class AuthStore extends ChangeNotifier {
  static const _kAccessToken = 'auth_access_token';
  static const _kRefreshToken = 'auth_refresh_token';
  static const _kSessionId = 'auth_session_id';

  String? _sessionId;

  String? get sessionId => _sessionId;

  final TokenStorage _storage;

  String? _accessToken;
  String? _refreshToken;

  AuthStore({FlutterSecureStorage? secureStorage})
      : _storage = createTokenStorage(secureStorage: secureStorage);

  String? get accessToken => _accessToken;
  String? get refreshToken => _refreshToken;

  bool get isLoggedIn => (_accessToken != null && _accessToken!.isNotEmpty);

  Future<void> init() async {
    _accessToken = await _storage.read(_kAccessToken);
    _refreshToken = await _storage.read(_kRefreshToken);
    _sessionId = await _storage.read(_kSessionId);
    notifyListeners();
  }

  Future<void> setTokens({
    required String accessToken,
    required String refreshToken,
    String? sessionId,
  }) async {
    _accessToken = accessToken;
    _refreshToken = refreshToken;

    if (sessionId != null && sessionId.trim().isNotEmpty) {
      _sessionId = sessionId.trim();
    }

    await _storage.write(_kAccessToken, accessToken);
    await _storage.write(_kRefreshToken, refreshToken);

    if (_sessionId != null && _sessionId!.isNotEmpty) {
      await _storage.write(_kSessionId, _sessionId!);
    }

    notifyListeners();
  }

  Future<void> clear() async {
    _accessToken = null;
    _refreshToken = null;
    _sessionId = null;
    _currentUser = null;
    _lastMeRefreshAt = null;

    await _storage.delete(_kSessionId);

    await _storage.delete(_kAccessToken);
    await _storage.delete(_kRefreshToken);

    notifyListeners();
  }

  Future<bool> tryRefresh(ApiClient api) async {
    final rt = _refreshToken ?? await _storage.read(_kRefreshToken);
    if (rt == null || rt.isEmpty) return false;

    try {
      final tokens = await api.auth.refresh(
        refreshToken: rt,
        deviceInfo: await collectDeviceInfoPayload(),
      );
      await setTokens(
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken,
        sessionId: tokens.sessionId,
      );
      return true;
    } catch (_) {
      await clear();
      return false;
    }
  }

  Future<void> clearAllUserData() async {
    _accessToken = null;
    _refreshToken = null;
    _sessionId = null;
    _currentUser = null;
    _lastMeRefreshAt = null;

    await _storage.deleteAll();
    notifyListeners();
  }

  UserDto? _currentUser;
  Future<void>? _refreshMeInFlight;
  DateTime? _lastMeRefreshAt;

  UserDto? get currentUser => _currentUser;

  Set<AppRole> get currentRoles {
    final user = _currentUser;
    if (user != null) return Roles.fromRoleNames(user.roles);
    return Roles.fromAccessToken(_accessToken);
  }

  Future<bool> refreshMe(
      ApiClient api, {
        bool force = false,
      }) async {
    if (!isLoggedIn) return false;

    if (!force && _refreshMeInFlight != null) {
      await _refreshMeInFlight;
      return false;
    }

    bool changed = false;

    _refreshMeInFlight = () async {
      final beforeRoles = currentRoles;
      final beforeUpdatedAt = _currentUser?.updatedAt;

      final fresh = await api.getMe();

      _currentUser = fresh;
      _lastMeRefreshAt = DateTime.now();

      final afterRoles = currentRoles;
      final rolesChanged = !_sameRoleSet(beforeRoles, afterRoles);
      final updatedAtChanged = beforeUpdatedAt != fresh.updatedAt;

      changed = rolesChanged || updatedAtChanged;
      if (changed) notifyListeners();
    }();

    try {
      await _refreshMeInFlight;
    } finally {
      _refreshMeInFlight = null;
    }

    return changed;
  }

  Future<void> refreshMeIfStale(
      ApiClient api, {
        Duration ttl = const Duration(minutes: 2),
      }) async {
    if (!isLoggedIn) return;

    final last = _lastMeRefreshAt;
    if (last != null && DateTime.now().difference(last) < ttl) return;

    try {
      await refreshMe(api);
    } catch (_) {
      // Keep current local state.
    }
  }

  bool _sameRoleSet(Set<AppRole> a, Set<AppRole> b) {
    if (a.length != b.length) return false;
    for (final role in a) {
      if (!b.contains(role)) return false;
    }
    return true;
  }

}

