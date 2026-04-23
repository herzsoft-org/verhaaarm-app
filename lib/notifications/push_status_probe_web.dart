// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import 'notification_center.dart';
import 'push_status_probe.dart';

class _WebPushStatusProbe implements PushStatusProbe {
  @override
  Future<PushStatus> readStatus() async {
    final nav = web.window.navigator as JSObject;

    final swAny = nav.getProperty('serviceWorker'.toJS);
    if (swAny == null) return PushStatus.unsupported;
    final sw = swAny as JSObject;

    final win = web.window as JSObject;
    final notificationCtorAny = win.getProperty('Notification'.toJS);
    if (notificationCtorAny == null) return PushStatus.unsupported;

    final ctor = notificationCtorAny as JSObject;
    final permission = ctor.getProperty('permission'.toJS)?.toString() ?? 'default';

    if (permission != 'granted') {
      return PushStatus.disabled;
    }

    try {
      final reg = await _getUsablePushRegistration(sw);
      if (reg == null) {
        return PushStatus.disabled;
      }

      final pushManagerAny = reg.getProperty('pushManager'.toJS);
      if (pushManagerAny == null) {
        return PushStatus.disabled;
      }

      final pushManager = pushManagerAny as JSObject;
      final getSubscriptionAny = pushManager.getProperty('getSubscription'.toJS);
      if (getSubscriptionAny == null) {
        return PushStatus.disabled;
      }

      final subAny = await _awaitPromise(
        (getSubscriptionAny as JSFunction).callAsFunction(pushManager),
        label: 'pushManager.getSubscription',
      );

      if (subAny == null) {
        return PushStatus.disabled;
      }

      return PushStatus.enabled;
    } catch (_) {
      return PushStatus.error;
    }
  }

  Future<JSObject?> _getUsablePushRegistration(JSObject sw) async {
    final existing = await _findPushServiceWorkerRegistration(sw);
    if (existing != null) {
      return existing;
    }

    final registered = await _registerPushServiceWorker(sw);
    if (registered != null) {
      return registered;
    }

    try {
      final readyAny = sw.getProperty('ready'.toJS);
      if (readyAny == null) return null;

      final regAny = await _awaitPromise(
        readyAny,
        label: 'serviceWorker.ready',
      );

      return _asJsObject(regAny);
    } catch (_) {
      return null;
    }
  }

  Future<JSObject?> _findPushServiceWorkerRegistration(JSObject sw) async {
    try {
      final getRegistrationsAny = sw.getProperty('getRegistrations'.toJS);
      if (getRegistrationsAny == null) return null;

      final regsAny = await _awaitPromise(
        (getRegistrationsAny as JSFunction).callAsFunction(sw),
        label: 'serviceWorker.getRegistrations',
      );

      final regsObj = _asJsObject(regsAny);
      if (regsObj == null) return null;

      final lengthAny = regsObj.getProperty('length'.toJS);
      final length = int.tryParse(lengthAny?.toString() ?? '') ?? 0;

      for (var i = 0; i < length; i++) {
        final regAny = regsObj.getProperty(i.toString().toJS);
        final reg = _asJsObject(regAny);
        if (reg == null) continue;

        final scriptUrl = _registrationScriptUrl(reg);
        if (scriptUrl != null && scriptUrl.contains('/push-sw.js')) {
          return reg;
        }
      }

      return null;
    } catch (_) {
      return null;
    }
  }

  String? _registrationScriptUrl(JSObject reg) {
    for (final key in const ['active', 'waiting', 'installing']) {
      final workerAny = reg.getProperty(key.toJS);
      final worker = _asJsObject(workerAny);
      if (worker == null) continue;

      final url = worker.getProperty('scriptURL'.toJS)?.toString();
      if (url != null && url.isNotEmpty) {
        return url;
      }
    }
    return null;
  }

  Future<JSObject?> _registerPushServiceWorker(JSObject sw) async {
    try {
      final registerAny = sw.getProperty('register'.toJS);
      if (registerAny == null) return null;

      final regAny = await _awaitPromise(
        (registerAny as JSFunction).callAsFunction(
          sw,
          '/push-sw.js'.toJS,
          <String, Object?>{'scope': '/'}.jsify(),
        ),
        label: 'serviceWorker.register(/push-sw.js)',
      );

      return _asJsObject(regAny);
    } catch (_) {
      return null;
    }
  }

  Future<JSAny?> _awaitPromise(
      JSAny? promiseLike, {
        required String label,
        Duration timeout = const Duration(seconds: 10),
      }) async {
    if (promiseLike == null) return null;

    final promise = promiseLike as JSPromise<JSAny?>;
    return promise.toDart.timeout(
      timeout,
      onTimeout: () => throw TimeoutException('Timed out waiting for $label'),
    );
  }

  JSObject? _asJsObject(JSAny? any) {
    if (any == null) return null;
    try {
      return any as JSObject;
    } catch (_) {
      return null;
    }
  }
}

PushStatusProbe createPushStatusProbeImpl() => _WebPushStatusProbe();