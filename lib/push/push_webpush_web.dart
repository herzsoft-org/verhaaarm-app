// lib/push/push_webpush_web.dart
// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:convert';

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
    unawaited(_ensurePushServiceWorkerRegistered());
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

    if (!authStore.isLoggedIn) {
      debugPrint('ABORT: not logged in');
      return;
    }
    if (!_supportsWebPush()) {
      debugPrint('ABORT: no serviceWorker container');
      return;
    }

    final perm = await _ensureNotificationPermission();
    debugPrint('Notification.requestPermission() result = $perm');
    debugPrint('Notification.permission (after) = ${_getNotificationPermission()}');
    if (perm != 'granted') {
      debugPrint('ABORT: permission not granted');
      return;
    }

    final reg = await _getUsablePushRegistration();
    if (reg == null) {
      debugPrint('ABORT: no usable push service worker registration');
      return;
    }

    debugPrint('Using SW registration scope=${reg.getProperty('scope'.toJS)?.toString()}');

    final activeAny = reg.getProperty('active'.toJS);
    debugPrint('SW active=${activeAny != null}');
    if (activeAny != null) {
      final a = _asJsObject(activeAny);
      if (a != null) {
        debugPrint('SW active.scriptURL=${a.getProperty('scriptURL'.toJS)?.toString()}');
        debugPrint('SW active.state=${a.getProperty('state'.toJS)?.toString()}');
      }
    }

    final pushManagerAny = reg.getProperty('pushManager'.toJS);
    debugPrint('SW pushManager=${pushManagerAny != null}');
    if (pushManagerAny == null) {
      debugPrint('ABORT: no pushManager on registration');
      return;
    }
    final pushManager = pushManagerAny as JSObject;

    final getSubscriptionAny = pushManager.getProperty('getSubscription'.toJS);
    if (getSubscriptionAny == null) {
      debugPrint('ABORT: pushManager.getSubscription missing');
      return;
    }
    final getSubscriptionFn = getSubscriptionAny as JSFunction;

    final subscribeAny = pushManager.getProperty('subscribe'.toJS);
    if (subscribeAny == null) {
      debugPrint('ABORT: pushManager.subscribe missing');
      return;
    }
    final subscribeFn = subscribeAny as JSFunction;

    final key = WebPushVapid.publicKey;
    debugPrint('VAPID publicKey len=${key.length}');
    debugPrint('VAPID publicKey head=${key.length >= 12 ? key.substring(0, 12) : key}');
    debugPrint('VAPID publicKey tail=${key.length >= 12 ? key.substring(key.length - 12) : key}');

    Uint8List appServerKeyDart;
    try {
      appServerKeyDart = _urlBase64ToUint8List(key);
      debugPrint('VAPID decoded bytes=${appServerKeyDart.length}');
    } catch (e) {
      debugPrint('ABORT: VAPID key base64 decode failed: $e');
      return;
    }

    if (appServerKeyDart.length != 65) {
      debugPrint('ABORT: VAPID decoded length is ${appServerKeyDart.length}, expected 65');
      return;
    }

    final options = <String, Object?>{
      'userVisibleOnly': true,
      'applicationServerKey': appServerKeyDart.toJS,
    }.jsify();

    JSObject? sub;

    try {
      debugPrint('Calling pushManager.getSubscription(...)...');
      final existingAny = await _awaitPromiseThen(
        getSubscriptionFn.callAsFunction(pushManager),
        label: 'pushManager.getSubscription',
      );
      final existing = _asJsObject(existingAny);
      debugPrint('Existing subscription? ${existing != null}');
      if (existing != null) {
        debugPrint('Existing endpoint=${existing.getProperty('endpoint'.toJS)?.toString()}');
        sub = existing;
      }
    } catch (e) {
      debugPrint('getSubscription() failed: $e');
    }

    if (sub == null) {
      try {
        debugPrint('Calling pushManager.subscribe(...)...');
        final subAny = await _awaitPromiseThen(
          subscribeFn.callAsFunction(pushManager, options),
          label: 'pushManager.subscribe',
        );
        sub = _asJsObject(subAny);
        debugPrint('subscribe() returned null? ${sub == null}');
      } catch (e) {
        debugPrint('subscribe() threw: $e');
        rethrow;
      }
    }

    if (sub == null) {
      debugPrint('ABORT: subscribe returned null');
      return;
    }

    final endpoint = sub.getProperty('endpoint'.toJS)?.toString() ?? '';
    debugPrint('Subscription endpoint=$endpoint');
    if (endpoint.isEmpty) {
      debugPrint('ABORT: empty endpoint');
      return;
    }

    final getKeyAny = sub.getProperty('getKey'.toJS);
    if (getKeyAny == null) {
      debugPrint('ABORT: subscription.getKey missing');
      return;
    }
    final getKeyFn = getKeyAny as JSFunction;

    final p256dhBufAny = getKeyFn.callAsFunction(sub, 'p256dh'.toJS);
    final authBufAny = getKeyFn.callAsFunction(sub, 'auth'.toJS);

    if (p256dhBufAny == null || authBufAny == null) {
      debugPrint('ABORT: subscription keys missing');
      return;
    }

    final p256dhBytes = _arrayBufferToBytes(p256dhBufAny);
    final authBytes = _arrayBufferToBytes(authBufAny);
    if (p256dhBytes == null || authBytes == null) {
      debugPrint('ABORT: key buffers could not be converted');
      return;
    }

    final p256dhB64Url = _b64UrlNoPad(p256dhBytes);
    final authB64Url = _b64UrlNoPad(authBytes);

    debugPrint('About to call api.registerWebPush');
    debugPrint('endpoint=$endpoint');
    debugPrint('p256dh len=${p256dhB64Url.length}');
    debugPrint('auth len=${authB64Url.length}');

    try {
      await api.registerWebPush(
        endpoint: endpoint,
        p256dh: p256dhB64Url,
        auth: authB64Url,
        raw: {
          'endpoint': endpoint,
          'keys': {'p256dh': p256dhB64Url, 'auth': authB64Url},
        },
      );
      debugPrint('api.registerWebPush finished successfully');
    } catch (e) {
      debugPrint('api.registerWebPush failed: $e');
      rethrow;
    }

    debugPrint('WebPush subscription registered on backend.');
  }

  bool _supportsWebPush() => _serviceWorkerContainer() != null;

  Future<JSObject?> _getUsablePushRegistration() async {
    final sw = _serviceWorkerContainer();
    if (sw == null) {
      debugPrint('No service worker container');
      return null;
    }

    final existing = await _getPushServiceWorkerRegistration();
    if (existing != null) {
      debugPrint('Found existing /push-sw.js registration');
      return existing;
    }

    debugPrint('No existing /push-sw.js registration, registering now...');
    final registered = await _registerPushServiceWorker();
    if (registered != null) {
      debugPrint('push-sw.js registered successfully');
      return registered;
    }

    debugPrint('Falling back to navigator.serviceWorker.ready...');
    try {
      final readyAny = await _awaitPromiseThen(
        sw.getProperty('ready'.toJS),
        label: 'serviceWorker.ready',
      );
      final readyReg = _asJsObject(readyAny);
      if (readyReg != null) {
        debugPrint('serviceWorker.ready returned a registration');
      }
      return readyReg;
    } catch (e) {
      debugPrint('serviceWorker.ready failed: $e');
      return null;
    }
  }

  Future<JSObject?> _getPushServiceWorkerRegistration() async {
    try {
      final sw = _serviceWorkerContainer();
      if (sw == null) return null;

      final getRegistrationAny = sw.getProperty('getRegistration'.toJS);
      if (getRegistrationAny == null) {
        debugPrint('SW getRegistration missing');
        return null;
      }

      final getRegistrationFn = getRegistrationAny as JSFunction;

      final regAny = await _awaitPromiseThen(
        getRegistrationFn.callAsFunction(sw, '/push-sw.js'.toJS),
        label: 'serviceWorker.getRegistration(/push-sw.js)',
      );

      return _asJsObject(regAny);
    } catch (e) {
      debugPrint('getRegistration(/push-sw.js) failed: $e');
      return null;
    }
  }

  Future<JSObject?> _ensurePushServiceWorkerRegistered() async {
    final existing = await _getPushServiceWorkerRegistration();
    if (existing != null) return existing;
    return _registerPushServiceWorker();
  }

  Future<JSObject?> _registerPushServiceWorker() async {
    try {
      final sw = _serviceWorkerContainer();
      if (sw == null) return null;

      final registerAny = sw.getProperty('register'.toJS);
      if (registerAny == null) {
        debugPrint('SW register missing');
        return null;
      }

      final registerFn = registerAny as JSFunction;

      final regAny = await _awaitPromiseThen(
        registerFn.callAsFunction(
          sw,
          '/push-sw.js'.toJS,
          <String, Object?>{'scope': '/'}.jsify(),
        ),
        label: 'serviceWorker.register(/push-sw.js)',
      );

      return _asJsObject(regAny);
    } catch (e) {
      debugPrint('SW register failed: $e');
      return null;
    }
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
        return completer.future.timeout(
          const Duration(seconds: 10),
          onTimeout: () => _getNotificationPermission(),
        );
      } catch (_) {
        return _getNotificationPermission();
      }
    }

    try {
      final resAny = (fnAny as JSFunction).callAsFunction(ctor);
      final resolved = await _awaitPromiseThen(
        resAny,
        label: 'Notification.requestPermission',
      );
      return resolved?.toString() ?? 'default';
    } catch (_) {
      final completer = Completer<String>();
      final cb = ((JSAny? perm) {
        final s = perm?.toString() ?? 'default';
        if (!completer.isCompleted) completer.complete(s);
      }).toJS;

      try {
        (fnAny as JSFunction).callAsFunction(ctor, cb);
        return completer.future.timeout(
          const Duration(seconds: 10),
          onTimeout: () => _getNotificationPermission(),
        );
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

  Future<JSAny?> _awaitPromiseThen(
      JSAny? promiseLike, {
        String? label,
        Duration timeout = const Duration(seconds: 15),
      }) async {
    if (promiseLike == null) return null;

    try {
      final promise = promiseLike as JSPromise<JSAny?>;
      return await promise.toDart.timeout(
        timeout,
        onTimeout: () {
          throw TimeoutException('Timed out waiting for ${label ?? 'promise'}');
        },
      );
    } catch (e) {
      debugPrint('_awaitPromiseThen failed for ${label ?? 'promise'}: $e');
      rethrow;
    }
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
    var s = base64Url.trim();
    s = s.replaceAll('\n', '').replaceAll('\r', '').replaceAll(' ', '');

    s = s.replaceAll('-', '+').replaceAll('_', '/');
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