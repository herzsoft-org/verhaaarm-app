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
    await _registerServiceWorkerBestEffort();
  }

  Future<void> enableFromButtonClick() async {
    final win = web.window as JSObject;
    debugPrint('secureContext=${web.window.isSecureContext}');
    debugPrint('Notification in window=${win.getProperty('Notification'.toJS) != null}');
    debugPrint('SW in navigator=${_serviceWorkerContainer() != null}');

    if (!authStore.isLoggedIn) return;
    if (!_supportsWebPush()) return;

    // IMPORTANT: do permission first, before any awaited work
    final perm = await _requestNotificationPermission();
    if (perm != 'granted') return;

    await _registerServiceWorkerBestEffort();

    final sw = _serviceWorkerContainer();
    if (sw == null) return;

    // Wait for Flutter's SW to be ready
    final regAny = await _awaitPromise(sw.getProperty('ready'.toJS));
    if (regAny == null) return;
    final reg = regAny as JSObject;

    final pushManagerAny = reg.getProperty('pushManager'.toJS);
    if (pushManagerAny == null) return;
    final pushManager = pushManagerAny as JSObject;

    final vapidPublicKey = WebPushVapid.publicKey.trim();
    if (vapidPublicKey.isEmpty) return;

    final appServerKey = _urlBase64ToUint8List(vapidPublicKey).toJS;

    final options = <String, Object?>{
      'userVisibleOnly': true,
      'applicationServerKey': appServerKey,
    }.jsify();

    final subAny = await _awaitPromise(
      pushManager.callMethod('subscribe'.toJS, <JSAny?>[options].toJS),
    );
    if (subAny == null) return;
    final sub = subAny as JSObject;

    final endpointAny = sub.getProperty('endpoint'.toJS);
    final endpoint = endpointAny?.toString() ?? '';
    if (endpoint.isEmpty) return;

    final p256dhBufAny = sub.callMethod('getKey'.toJS, <JSAny?>['p256dh'.toJS].toJS);
    final authBufAny = sub.callMethod('getKey'.toJS, <JSAny?>['auth'.toJS].toJS);
    if (p256dhBufAny == null || authBufAny == null) return;

    final p256dhBytes = _arrayBufferToBytes(p256dhBufAny);
    final authBytes = _arrayBufferToBytes(authBufAny);
    if (p256dhBytes == null || authBytes == null) return;

    final p256dhB64 = base64Encode(p256dhBytes);
    final authB64 = base64Encode(authBytes);

    final raw = <String, dynamic>{
      'endpoint': endpoint,
      'keys': {'p256dh': p256dhB64, 'auth': authB64},
    };

    await api.registerWebPush(
      endpoint: endpoint,
      p256dh: p256dhB64,
      auth: authB64,
      raw: raw,
    );
  }

  bool _supportsWebPush() {
    return _serviceWorkerContainer() != null;
  }

  Future<void> _registerServiceWorkerBestEffort() async {
    // Do nothing: Flutter registers its own SW.
    // We only wait for it to become ready.
    try {
      final sw = _serviceWorkerContainer();
      if (sw == null) return;
      await _awaitPromise(sw.getProperty('ready'.toJS));
    } catch (_) {
      // ignore
    }
  }

  // ---- Notifications permission (no dart:html) ----
  Future<String> _requestNotificationPermission() async {
    final win = web.window as JSObject;

    final notificationCtorAny = win.getProperty('Notification'.toJS);
    if (notificationCtorAny == null) return 'denied';

    final notificationCtor = notificationCtorAny as JSObject;

    final res = await _awaitPromise(
      notificationCtor.callMethod('requestPermission'.toJS, <JSAny?>[].toJS),
    );

    return res?.toString() ?? 'denied';
  }

  // ---- Promise helper (avoid `is JSPromise` runtime checks) ----
  Future<JSAny?> _awaitPromise(JSAny? any) async {
    if (any == null) return null;
    try {
      return (any as JSPromise<JSAny?>).toDart;
    } catch (_) {
      return null;
    }
  }

  // ---- Service Worker container access ----
  JSObject? _serviceWorkerContainer() {
    final nav = web.window.navigator as JSObject;
    final sw = nav.getProperty('serviceWorker'.toJS);
    return sw == null ? null : (sw as JSObject);
  }

  // ---- ArrayBuffer -> Uint8List ----
  Uint8List? _arrayBufferToBytes(JSAny buf) {
    // subscription.getKey(...) returns an ArrayBuffer
    // Wrap it in a JSUint8Array and copy to Dart.
    try {
      final ab = buf as JSArrayBuffer;
      final u8 = JSUint8Array(ab);
      return u8.toDart;
    } catch (_) {
      return null;
    }
  }

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
