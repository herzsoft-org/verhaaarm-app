import 'dart:async';

import '../api/api_client.dart';
import '../auth/auth_store.dart';

class NotificationCenter {
  NotificationCenter._();
  static final NotificationCenter I = NotificationCenter._();

  ApiClient? _api;
  AuthStore? _auth;

  int _unread = 0;
  int get unread => _unread;

  final StreamController<int> _unreadStream = StreamController<int>.broadcast();
  Stream<int> get unreadStream => _unreadStream.stream;

  Timer? _pollTimer;
  bool _initialized = false;

  void init({required ApiClient api, required AuthStore authStore}) {
    _api = api;
    _auth = authStore;

    if (_initialized) return;
    _initialized = true;

    // On auth changes: refresh + start/stop polling.
    authStore.addListener(_onAuthChanged);
    _onAuthChanged();
  }

  void dispose() {
    _pollTimer?.cancel();
    _unreadStream.close();
  }

  void _onAuthChanged() {
    final loggedIn = _auth?.isLoggedIn == true;

    _pollTimer?.cancel();
    _pollTimer = null;

    if (!loggedIn) {
      _setUnread(0);
      return;
    }

    // Immediately refresh, then poll occasionally (cheap endpoint).
    refreshUnreadCount();
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) => refreshUnreadCount());
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

  void _setUnread(int v) {
    if (v < 0) v = 0;
    if (_unread == v) return;
    _unread = v;
    _unreadStream.add(_unread);
  }

  // Call this when you know you changed read state locally.
  void decrementUnread({int by = 1}) => _setUnread(_unread - by);
  void resetUnread() => _setUnread(0);
}
