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

    final perm = await _ensureNotificationPermission();

    debugPrint('Notification.requestPermission() result = $perm');
    debugPrint('Notification.permission (after) = ${_getNotificationPermission()}');

    if (perm != 'granted') return;

    await _registerServiceWorkerBestEffort();

    final sw = _serviceWorkerContainer();
    if (sw == null) return;

    debugPrint('PushManager.supported=${win.getProperty('PushManager'.toJS) != null}');

    // Get registration (WebKit-safe: Promise.then)
    // Wait until we have an active SW registration (this is what matters)
    final reg = await _waitForReadyRegistration();
    if (reg == null) {
      debugPrint('serviceWorker.ready returned null (cannot subscribe)');
      return;
    }

    debugPrint('SW ready.scope=${reg.getProperty('scope'.toJS)?.toString()}');

    final activeAny = reg.getProperty('active'.toJS);
    debugPrint('SW reg.active=${activeAny != null}');
    if (activeAny != null) {
      final a = _asJsObject(activeAny);
      if (a != null) {
        debugPrint('SW active.scriptURL=${a.getProperty('scriptURL'.toJS)?.toString()}');
        debugPrint('SW active.state=${a.getProperty('state'.toJS)?.toString()}');
      }
    }

    final pushManagerAny = reg.getProperty('pushManager'.toJS);
    debugPrint('SW reg.pushManager=${pushManagerAny != null}');
    if (pushManagerAny == null) {
      debugPrint('No pushManager on registration (cannot subscribe)');
      return;
    }

    final pushManager = pushManagerAny as JSObject;

    // Check existing subscription first (optional, but useful)
    try {
      final existingAny = await _awaitPromiseThen(
        pushManager.callMethod('getSubscription'.toJS, <JSAny?>[].toJS),
      );
      debugPrint('getSubscription() is null? ${existingAny == null}');
      if (existingAny != null) {
        final existing = existingAny as JSObject;
        final endpoint = existing.getProperty('endpoint'.toJS)?.toString() ?? '';
        debugPrint('Existing subscription endpoint=$endpoint');
      }
    } catch (e) {
      debugPrint('getSubscription() failed: $e');
    }

    final vapidPublicKey = WebPushVapid.publicKey.trim();
    if (vapidPublicKey.isEmpty) return;

    final appServerKey = _urlBase64ToUint8List(vapidPublicKey).toJS;

    final options = <String, Object?>{
      'userVisibleOnly': true,
      'applicationServerKey': appServerKey,
    }.jsify();

    JSAny? subAny;
    try {
      subAny = await _awaitPromiseThen(
        pushManager.callMethod('subscribe'.toJS, <JSAny?>[options].toJS),
      );
      debugPrint('subscribe() returned null? ${subAny == null}');
    } catch (e) {
      debugPrint('subscribe() failed: $e');
      rethrow;
    }

    if (subAny == null) return;
    final sub = subAny as JSObject;

    final endpoint = sub.getProperty('endpoint'.toJS)?.toString() ?? '';
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

    debugPrint('WebPush subscription registered on backend.');
  }

  bool _supportsWebPush() => _serviceWorkerContainer() != null;

  Future<JSObject?> _waitForReadyRegistration() async {
    final sw = _serviceWorkerContainer();
    if (sw == null) return null;

    try {
      // navigator.serviceWorker.ready -> Promise<ServiceWorkerRegistration>
      final readyAny = sw.getProperty('ready'.toJS);
      final regAny = await _awaitPromiseThen(readyAny as JSAny?);
      final reg = _asJsObject(regAny);
      return reg;
    } catch (e) {
      debugPrint('serviceWorker.ready failed: $e');
      return null;
    }
  }

  Future<void> _registerServiceWorkerBestEffort() async {
    // For Flutter web: don’t register your own SW here.
    // Just touching ready is fine, but do it properly so the SW activates.
    await _waitForReadyRegistration();
  }


  String _getNotificationPermission() {
    final win = web.window as JSObject;
    final notificationCtorAny = win.getProperty('Notification'.toJS);
    if (notificationCtorAny == null) return 'missing';
    final ctor = notificationCtorAny as JSObject;
    return ctor.getProperty('permission'.toJS)?.toString() ?? 'unknown';
  }

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
      final resolved = await _awaitPromiseThen(resAny);
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

  Future<JSObject?> _getRegistrationViaThen(JSObject sw) async {
    try {
      final regAny = await _awaitPromiseThen(
        sw.callMethod('getRegistration'.toJS, <JSAny?>[].toJS),
      );
      final reg = _asJsObject(regAny);
      return reg;
    } catch (e) {
      debugPrint('SW getRegistration failed: $e');
      return null;
    }
  }

  // Promise helper: unwrap via Promise.resolve(...).then(...) (WebKit-safe)
  Future<JSAny?> _awaitPromiseThen(JSAny? promiseLike) {
    if (promiseLike == null) return Future.value(null);

    final c = Completer<JSAny?>();
    final win = web.window as JSObject;

    final promiseCtorAny = win.getProperty('Promise'.toJS);
    if (promiseCtorAny == null) return Future.value(promiseLike);

    final promiseCtor = promiseCtorAny as JSObject;
    final pAny = promiseCtor.callMethod('resolve'.toJS, <JSAny?>[promiseLike].toJS);

    final onFulfilled = ((JSAny? v) {
      if (!c.isCompleted) c.complete(v);
    }).toJS;

    final onRejected = ((JSAny? e) {
      if (!c.isCompleted) c.completeError(e ?? 'Promise rejected');
    }).toJS;

    (pAny as JSObject).callMethod('then'.toJS, <JSAny?>[onFulfilled, onRejected].toJS);
    return c.future;
  }

  JSObject? _serviceWorkerContainer() {
    final nav = web.window.navigator as JSObject;
    final sw = nav.getProperty('serviceWorker'.toJS);
    return sw == null ? null : (sw as JSObject);
  }

  JSObject? _asJsObject(JSAny? any) {
    if (any == null) return null;
    try {
      return any as JSObject;
    } catch (_) {
      return null;
    }
  }

  Uint8List? _arrayBufferToBytes(JSAny buf) {
    try {
      final ab = buf as JSArrayBuffer;
      final u8 = JSUint8Array(ab);
      return u8.toDart;
    } catch (_) {
      return null;
    }
  }

  String _b64UrlNoPad(Uint8List bytes) => base64UrlEncode(bytes).replaceAll('=', '');

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
