import 'dart:async';

import '../api/api_client.dart';
import '../auth/auth_store.dart';
import 'push_status_probe.dart';

enum PushStatus {
  unknown,
  unsupported,
  disabled,
  enabled,
  error,
}

class NotificationCenter {
  NotificationCenter._();
  static final NotificationCenter I = NotificationCenter._();

  ApiClient? _api;
  AuthStore? _auth;

  final PushStatusProbe _pushStatusProbe = createPushStatusProbe();

  int _unread = 0;
  int get unread => _unread;

  PushStatus _pushStatus = PushStatus.unknown;
  PushStatus get pushStatus => _pushStatus;

  final StreamController<int> _unreadStream = StreamController<int>.broadcast();
  Stream<int> get unreadStream => _unreadStream.stream;

  final StreamController<PushStatus> _pushStatusStream =
  StreamController<PushStatus>.broadcast();
  Stream<PushStatus> get pushStatusStream => _pushStatusStream.stream;

  Timer? _pollTimer;
  bool _initialized = false;

  void init({required ApiClient api, required AuthStore authStore}) {
    _api = api;
    _auth = authStore;

    if (_initialized) return;
    _initialized = true;

    authStore.addListener(_onAuthChanged);
    _onAuthChanged();
  }

  void dispose() {
    _pollTimer?.cancel();
    _unreadStream.close();
    _pushStatusStream.close();
  }

  void reset() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _setUnread(0);
    _setPushStatus(PushStatus.unknown);
  }

  void _onAuthChanged() {
    final loggedIn = _auth?.isLoggedIn == true;

    _pollTimer?.cancel();
    _pollTimer = null;

    if (!loggedIn) {
      _setUnread(0);
      _setPushStatus(PushStatus.unknown);
      return;
    }

    refreshUnreadCount();
    refreshPushStatus();

    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      refreshUnreadCount();
      refreshPushStatus();
    });
  }

  Future<void> refreshUnreadCount() async {
    final api = _api;
    final auth = _auth;
    if (api == null || auth == null || !auth.isLoggedIn) return;

    try {
      final dto = await api.getUnreadCount();
      _setUnread(dto.unread);
    } catch (_) {
      // ignore
    }
  }

  Future<void> refreshPushStatus() async {
    final auth = _auth;
    if (auth == null || !auth.isLoggedIn) return;

    try {
      final status = await _pushStatusProbe.readStatus();
      _setPushStatus(status);
    } catch (_) {
      _setPushStatus(PushStatus.error);
    }
  }

  void _setUnread(int v) {
    if (v < 0) v = 0;
    if (_unread == v) return;
    _unread = v;
    _unreadStream.add(_unread);
  }

  void _setPushStatus(PushStatus v) {
    if (_pushStatus == v) return;
    _pushStatus = v;
    _pushStatusStream.add(_pushStatus);
  }

  void decrementUnread({int by = 1}) => _setUnread(_unread - by);
  void resetUnread() => _setUnread(0);
}