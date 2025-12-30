// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:convert';
import 'dart:typed_data';

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

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
    if (!authStore.isLoggedIn) return;
    if (!_supportsWebPush()) return;

    // IMPORTANT: do permission first, before any awaited work
    final perm = await _requestNotificationPermission();
    if (perm != 'granted') return;

    await _registerServiceWorkerBestEffort();

    final sw = _serviceWorkerContainer();
    if (sw == null) return;

    final readyPromise = sw.getProperty('ready'.toJS);
    if (readyPromise is! JSPromise<JSAny?>) return;

    final regAny = await readyPromise.toDart;
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

    final subPromiseAny = pushManager.callMethod(
      'subscribe'.toJS,
      <JSAny?>[options].toJS,
    );

    if (subPromiseAny is! JSPromise<JSAny?>) return;
    final subAny = await subPromiseAny.toDart;
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
    try {
      final sw = _serviceWorkerContainer();
      if (sw == null) return;

      final opts = <String, Object?>{'scope': '/'}.jsify();

      final pAny = sw.callMethod(
        'register'.toJS,
        <JSAny?>['/webpush-sw.js'.toJS, opts].toJS, // JSArray args
      );

      if (pAny is JSPromise<JSAny?>) {
        await pAny.toDart;
      }
    } catch (_) {
      // ignore
    }
  }

  // ---- Notifications permission (no dart:html) ----
  Future<String> _requestNotificationPermission() async {
    final win = web.window as JSObject;
    final notificationCtor = win.getProperty('Notification'.toJS);
    if (notificationCtor == null) return 'denied';

    final ctor = notificationCtor as JSObject;
    final reqAny = ctor.callMethod('requestPermission'.toJS, (<JSAny?>[]).toJS);
    if (reqAny is! JSPromise<JSAny?>) return 'denied';

    final res = await reqAny.toDart;
    return res?.toString() ?? 'denied';
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
