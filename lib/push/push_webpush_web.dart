// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import '../api/api_client.dart';
import '../auth/auth_store.dart';
import 'webpush_vapid.dart';

class WebPushRegistrar {
  final ApiClient api;
  final AuthStore authStore;

  WebPushRegistrar({required this.api, required this.authStore});

  Future<void> initBestEffort() async {
    if (!authStore.isLoggedIn) return;
    await _registerServiceWorkerBestEffort();
  }

  bool _isStandalone() {
    final win = web.window as JSObject;

    final mmAny = win.callMethod(
      'matchMedia'.toJS,
      <JSAny?>['(display-mode: standalone)'.toJS].toJS,
    );

    final JSObject mm;
    try {
      mm = mmAny as JSObject;
    } catch (_) {
      return false;
    }

    final matchesAny = mm.getProperty('matches'.toJS);

    try {
      return (matchesAny as JSBoolean).toDart;
    } catch (_) {
      return matchesAny?.toString() == 'true';
    }
  }

  Future<void> enableFromButtonClick() async {
    final win = web.window as JSObject;

    debugPrint('secureContext=${web.window.isSecureContext}');
    debugPrint('Notification in window=${win.getProperty('Notification'.toJS) != null}');
    debugPrint('SW in navigator=${_serviceWorkerContainer() != null}');
    debugPrint('displayModeStandalone=${_isStandalone()}');

    debugPrint('Notification.permission (before) = ${_getNotificationPermission()}');

    if (!authStore.isLoggedIn) return;
    if (!_supportsWebPush()) return;

    // Permission first (must be a direct user gesture).
    final perm = await _ensureNotificationPermission();

    debugPrint('Notification.requestPermission() result = $perm');
    debugPrint('Notification.permission (after) = ${_getNotificationPermission()}');

    if (perm != 'granted') return;

    await _registerServiceWorkerBestEffort();

    final sw = _serviceWorkerContainer();
    if (sw == null) return;

    debugPrint('PushManager.supported=${win.getProperty('PushManager'.toJS) != null}');
    debugPrint('serviceWorker.controller=${sw.getProperty('controller'.toJS) != null}');

    // Get a REAL ServiceWorkerRegistration (ready is too flaky via generic interop)
    final reg = await _getBestRegistrationForThisPage(sw);
    if (reg == null) {
      debugPrint('SW registration: null (cannot subscribe)');
      return;
    }

    final scope = reg.getProperty('scope'.toJS)?.toString();
    debugPrint('SW chosen scope=$scope');
    debugPrint('SW chosen active=${reg.getProperty('active'.toJS) != null}');
    debugPrint('SW chosen pushManager=${reg.getProperty('pushManager'.toJS) != null}');

    final pushManagerAny = reg.getProperty('pushManager'.toJS);
    if (pushManagerAny == null) {
      debugPrint('No pushManager on chosen registration (iOS: push not enabled for this reg/scope)');
      return;
    }
    final pushManager = pushManagerAny as JSObject;

    final vapidPublicKey = WebPushVapid.publicKey.trim();
    if (vapidPublicKey.isEmpty) return;

    final appServerKey = _urlBase64ToUint8List(vapidPublicKey).toJS;

    final options = <String, Object?>{
      'userVisibleOnly': true,
      'applicationServerKey': appServerKey,
    }.jsify();

    JSAny? subAny;
    try {
      subAny = await _awaitPromiseResolve(
        pushManager.callMethod('subscribe'.toJS, <JSAny?>[options].toJS),
      );
      debugPrint('subscribe() returned null? ${subAny == null}');
    } catch (e) {
      debugPrint('subscribe() failed: $e');
      rethrow;
    }

    if (subAny == null) return;
    final sub = subAny as JSObject;

    final endpointAny = sub.getProperty('endpoint'.toJS);
    final endpoint = endpointAny?.toString() ?? '';
    debugPrint('Push endpoint=$endpoint');
    if (endpoint.isEmpty) return;

    final p256dhBufAny = sub.callMethod('getKey'.toJS, <JSAny?>['p256dh'.toJS].toJS);
    final authBufAny = sub.callMethod('getKey'.toJS, <JSAny?>['auth'.toJS].toJS);
    if (p256dhBufAny == null || authBufAny == null) return;

    final p256dhBytes = _arrayBufferToBytes(p256dhBufAny);
    final authBytes = _arrayBufferToBytes(authBufAny);
    if (p256dhBytes == null || authBytes == null) return;

    final p256dhB64Url = _b64UrlNoPad(p256dhBytes);
    final authB64Url = _b64UrlNoPad(authBytes);

    final raw = <String, dynamic>{
      'endpoint': endpoint,
      'keys': {'p256dh': p256dhB64Url, 'auth': authB64Url},
    };

    await api.registerWebPush(
      endpoint: endpoint,
      p256dh: p256dhB64Url,
      auth: authB64Url,
      raw: raw,
    );
  }

  bool _supportsWebPush() {
    return _serviceWorkerContainer() != null;
  }

  Future<void> _registerServiceWorkerBestEffort() async {
    try {
      final sw = _serviceWorkerContainer();
      if (sw == null) return;

      // Touch ready but ignore it; we fetch registrations explicitly elsewhere.
      sw.getProperty('ready'.toJS);
    } catch (_) {
      // ignore
    }
  }

  // ---- Read current permission state without prompting ----
  String _getNotificationPermission() {
    final win = web.window as JSObject;

    final notificationCtorAny = win.getProperty('Notification'.toJS);
    if (notificationCtorAny == null) return 'missing';

    final ctor = notificationCtorAny as JSObject;
    final p = ctor.getProperty('permission'.toJS);
    return p?.toString() ?? 'unknown';
  }

  // ---- Permission request (supports Promise and callback forms) ----
  Future<String> _ensureNotificationPermission() async {
    final current = _getNotificationPermission();
    if (current == 'granted' || current == 'denied') return current;

    if (!_isStandalone() && _isProbablyIosSafari()) {
      return current;
    }

    final win = web.window as JSObject;
    final notificationCtorAny = win.getProperty('Notification'.toJS);
    if (notificationCtorAny == null) return 'missing';
    final ctor = notificationCtorAny as JSObject;

    final fnAny = ctor.getProperty('requestPermission'.toJS);
    if (fnAny == null) return 'missing';

    final fnObj = fnAny as JSObject;

    final lenAny = fnObj.getProperty('length'.toJS);
    final fnLen = int.tryParse(lenAny?.toString() ?? '') ?? 0;

    if (fnLen >= 1) {
      final completer = Completer<String>();
      final cb = ((JSAny? perm) {
        final s = perm?.toString() ?? 'default';
        if (!completer.isCompleted) completer.complete(s);
      }).toJS;

      try {
        (fnAny as JSFunction).callAsFunction(ctor, cb);
        return completer.future;
      } catch (_) {
        return _getNotificationPermission();
      }
    }

    try {
      final resAny = (fnAny as JSFunction).callAsFunction(ctor);
      final resolved = await _awaitPromiseResolve(resAny);
      return resolved?.toString() ?? 'default';
    } catch (_) {
      final completer = Completer<String>();
      final cb = ((JSAny? perm) {
        final s = perm?.toString() ?? 'default';
        if (!completer.isCompleted) completer.complete(s);
      }).toJS;

      try {
        (fnAny as JSFunction).callAsFunction(ctor, cb);
        return completer.future;
      } catch (_) {
        return _getNotificationPermission();
      }
    }
  }

  bool _isProbablyIosSafari() {
    final ua = _userAgent().toLowerCase();
    final isIos = ua.contains('iphone') || ua.contains('ipad') || ua.contains('ipod');
    final isSafari = ua.contains('safari') && !ua.contains('crios') && !ua.contains('fxios');
    return isIos && isSafari;
  }

  String _userAgent() {
    final nav = web.window.navigator as JSObject;
    return nav.getProperty('userAgent'.toJS)?.toString() ?? '';
  }

  // ---- Get the best ServiceWorkerRegistration for this page ----
  Future<JSObject?> _getBestRegistrationForThisPage(JSObject sw) async {
    // 1) Try getRegistration() for current scope/page.
    try {
      final regAny = await _awaitPromiseResolve(
        sw.callMethod('getRegistration'.toJS, <JSAny?>[].toJS),
      );
      final reg = _asJsObject(regAny);
      if (reg != null) {
        final scope = reg.getProperty('scope'.toJS)?.toString();
        debugPrint('SW getRegistration scope=$scope');
        return reg;
      }
    } catch (e) {
      debugPrint('SW getRegistration failed: $e');
    }

    // 2) Fallback: getRegistrations() and pick one with a scope and pushManager if possible.
    try {
      final regsAny = await _awaitPromiseResolve(
        sw.callMethod('getRegistrations'.toJS, <JSAny?>[].toJS),
      );
      final regs = _asJsArray(regsAny);
      if (regs == null) {
        debugPrint('SW getRegistrations not an array: ${regsAny?.toString()}');
        return null;
      }

      JSObject? best;
      int bestScore = -1;

      for (final item in regs) {
        final r = _asJsObject(item);
        if (r == null) continue;

        final scope = r.getProperty('scope'.toJS)?.toString() ?? '';
        final hasScope = scope.isNotEmpty && scope != 'null';
        final hasPm = r.getProperty('pushManager'.toJS) != null;

        debugPrint('SW reg candidate scope=$scope pushManager=$hasPm');

        var score = 0;
        if (hasScope) score += 1;
        if (hasPm) score += 2;

        if (score > bestScore) {
          bestScore = score;
          best = r;
        }
      }

      return best;
    } catch (e) {
      debugPrint('SW getRegistrations failed: $e');
      return null;
    }
  }

  JSObject? _asJsObject(JSAny? any) {
    if (any == null) return null;
    try {
      return any as JSObject;
    } catch (_) {
      return null;
    }
  }

  // Best-effort JS Array -> Dart List<JSAny?>
  List<JSAny?>? _asJsArray(JSAny? any) {
    if (any == null) return null;
    try {
      final arr = any as JSArray<JSAny?>;
      final out = <JSAny?>[];
      final lenAny = (arr as JSObject).getProperty('length'.toJS);
      final len = int.tryParse(lenAny?.toString() ?? '') ?? 0;
      for (var i = 0; i < len; i++) {
        out.add(arr[i]);
      }
      return out;
    } catch (_) {
      return null;
    }
  }

  // ---- Promise helper: always await via Promise.resolve(...) ----
  Future<JSAny?> _awaitPromiseResolve(JSAny? value) async {
    if (value == null) return null;

    final win = web.window as JSObject;

    final promiseCtorAny = win.getProperty('Promise'.toJS);
    if (promiseCtorAny == null) return value;

    final promiseCtor = promiseCtorAny as JSObject;

    final pAny = promiseCtor.callMethod('resolve'.toJS, <JSAny?>[value].toJS);
    return (pAny as JSPromise<JSAny?>).toDart;
  }

  // ---- Service Worker container access ----
  JSObject? _serviceWorkerContainer() {
    final nav = web.window.navigator as JSObject;
    final sw = nav.getProperty('serviceWorker'.toJS);
    return sw == null ? null : (sw as JSObject);
  }

  // ---- ArrayBuffer -> Uint8List ----
  Uint8List? _arrayBufferToBytes(JSAny buf) {
    try {
      final ab = buf as JSArrayBuffer;
      final u8 = JSUint8Array(ab);
      return u8.toDart;
    } catch (_) {
      return null;
    }
  }

  // ---- Base64url without padding (RFC 4648) ----
  String _b64UrlNoPad(Uint8List bytes) {
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  // ---- VAPID public key: base64url -> bytes ----
  Uint8List _urlBase64ToUint8List(String base64Url) {
    var s = base64Url.replaceAll('-', '+').replaceAll('_', '/');
    switch (s.length % 4) {
      case 0:
        break;
      case 2:
        s += '==';
        break;
      case 3:
        s += '=';
        break;
      default:
        break;
    }
    return base64Decode(s);
  }
}
