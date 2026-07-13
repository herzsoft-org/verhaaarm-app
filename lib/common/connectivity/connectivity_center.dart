import 'dart:async';

import 'package:dio/dio.dart';

/// Thrown in place of the raw [DioException] for connection-level failures
/// (no internet, server unreachable/down) so existing `'...: $e'` snackbars
/// show a short message instead of Dio's multi-paragraph default text.
class ServerUnreachableException implements Exception {
  const ServerUnreachableException();

  @override
  String toString() =>
      'Keine Serververbindung (kein Internet oder Server wird gerade gewartet).';
}

/// Tracks whether the backend is currently reachable, based on outcomes
/// observed by [ApiClient]'s Dio interceptor. While unreachable, retries a
/// cheap request on a timer so the app auto-recovers without user action.
class ConnectivityCenter {
  ConnectivityCenter._();

  static final ConnectivityCenter I = ConnectivityCenter._();

  static const _retryInterval = Duration(seconds: 5);

  // Brief blips (e.g. right after the app resumes from background, before the
  // OS network stack has fully reconnected) shouldn't flash the banner - only
  // show it if the failure is still happening after this grace period.
  static const _graceBeforeShowingBanner = Duration(seconds: 3);

  bool _reachable = true;
  Timer? _pendingUnreachableTimer;
  Timer? _retryTimer;
  Dio? _dio;

  final _controller = StreamController<bool>.broadcast();

  bool get isReachable => _reachable;
  Stream<bool> get reachableStream => _controller.stream;

  void reportSuccess() {
    _pendingUnreachableTimer?.cancel();
    _pendingUnreachableTimer = null;
    _retryTimer?.cancel();
    _retryTimer = null;

    if (!_reachable) {
      _reachable = true;
      _controller.add(true);
    }
  }

  void reportFailure(Dio dio) {
    _dio = dio;

    // Already showing the banner, or already waiting out the grace period -
    // nothing new to do here.
    if (!_reachable || _pendingUnreachableTimer != null) return;

    _pendingUnreachableTimer = Timer(_graceBeforeShowingBanner, () {
      _pendingUnreachableTimer = null;
      _reachable = false;
      _controller.add(false);
      _retryTimer ??= Timer.periodic(_retryInterval, (_) => _pingOnce());
    });

    // Probe right away too: if the connection has already recovered by itself
    // (the common resume-from-background case), this resolves and cancels the
    // pending timer above before the banner ever shows.
    unawaited(_pingOnce());
  }

  Future<void> _pingOnce() async {
    final dio = _dio;
    if (dio == null) return;

    try {
      // Any HTTP response (even an error status) means the server is reachable;
      // validateStatus avoids Dio throwing for non-2xx so only real connection
      // failures (no route, refused, timeout) keep this loop going.
      await dio.get(
        '/',
        options: Options(
          validateStatus: (_) => true,
          sendTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
        ),
      );
      reportSuccess();
    } catch (_) {
      // still unreachable; timer keeps retrying
    }
  }

  static bool isConnectionError(DioException e) {
    return switch (e.type) {
      DioExceptionType.connectionError ||
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout ||
      DioExceptionType.unknown => true,
      _ => false,
    };
  }
}
