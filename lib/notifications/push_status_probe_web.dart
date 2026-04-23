// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import 'notification_center.dart';
import 'push_status_probe.dart';

class _WebPushStatusProbe implements PushStatusProbe {
  void _dbg(String msg) {
    NotificationCenter.I.setPushDebugMessage(msg);
  }

  @override
  Future<PushStatus> readStatus() async {
    try {
      _dbg('Start probe');

      final nav = web.window.navigator as JSObject;
      final win = web.window as JSObject;

      final swAny = nav.getProperty('serviceWorker'.toJS);
      if (swAny == null) {
        _dbg('navigator.serviceWorker is null');
        return PushStatus.disabled;
      }
      _dbg('navigator.serviceWorker OK');

      final notificationCtorAny = win.getProperty('Notification'.toJS);
      if (notificationCtorAny == null) {
        _dbg('window.Notification is null');
        return PushStatus.disabled;
      }
      _dbg('window.Notification OK');

      final ctor = notificationCtorAny as JSObject;
      final permission = ctor.getProperty('permission'.toJS)?.toString() ?? 'default';
      _dbg('Notification.permission = $permission');

      if (permission != 'granted') {
        return PushStatus.disabled;
      }

      final sw = swAny as JSObject;
      final reg = await _getUsablePushRegistration(sw);
      if (reg == null) {
        _dbg('No usable push service worker registration');
        return PushStatus.disabled;
      }
      _dbg('Usable push service worker registration found');

      final pushManagerAny = reg.getProperty('pushManager'.toJS);
      if (pushManagerAny == null) {
        _dbg('registration.pushManager is null');
        return PushStatus.disabled;
      }
      _dbg('registration.pushManager OK');

      final pushManager = pushManagerAny as JSObject;
      final getSubscriptionAny = pushManager.getProperty('getSubscription'.toJS);
      if (getSubscriptionAny == null) {
        _dbg('pushManager.getSubscription missing');
        return PushStatus.disabled;
      }

      _dbg('Calling pushManager.getSubscription() ...');
      final subAny = await _awaitPromise(
        (getSubscriptionAny as JSFunction).callAsFunction(pushManager),
        label: 'pushManager.getSubscription',
      );

      if (subAny == null) {
        _dbg('getSubscription returned null');
        return PushStatus.disabled;
      }

      _dbg('PushSubscription found');
      return PushStatus.enabled;
    } catch (e, st) {
      _dbg('Probe failed: $e');
      // ignore: avoid_print
      print(st);
      return PushStatus.error;
    }
  }

  Future<JSObject?> _getUsablePushRegistration(JSObject sw) async {
    final existing = await _findPushServiceWorkerRegistration(sw);
    if (existing != null) {
      _dbg('Found existing /push-sw.js registration');
      return existing;
    }

    final registered = await _registerPushServiceWorker(sw);
    if (registered != null) {
      _dbg('Registered /push-sw.js successfully');
      return registered;
    }

    try {
      final readyAny = sw.getProperty('ready'.toJS);
      if (readyAny == null) {
        _dbg('serviceWorker.ready missing');
        return null;
      }

      _dbg('Awaiting serviceWorker.ready ...');
      final regAny = await _awaitPromise(
        readyAny,
        label: 'serviceWorker.ready',
      );

      final reg = _asJsObject(regAny);
      if (reg == null) {
        _dbg('serviceWorker.ready returned non-object/null');
      } else {
        _dbg('Using serviceWorker.ready registration');
      }
      return reg;
    } catch (e) {
      _dbg('serviceWorker.ready failed: $e');
      return null;
    }
  }

  Future<JSObject?> _findPushServiceWorkerRegistration(JSObject sw) async {
    try {
      final getRegistrationsAny = sw.getProperty('getRegistrations'.toJS);
      if (getRegistrationsAny == null) {
        _dbg('serviceWorker.getRegistrations missing');
        return null;
      }

      _dbg('Calling serviceWorker.getRegistrations() ...');
      final regsAny = await _awaitPromise(
        (getRegistrationsAny as JSFunction).callAsFunction(sw),
        label: 'serviceWorker.getRegistrations',
      );

      final regsObj = _asJsObject(regsAny);
      if (regsObj == null) {
        _dbg('getRegistrations returned non-object/null');
        return null;
      }

      final lengthAny = regsObj.getProperty('length'.toJS);
      final length = int.tryParse(lengthAny?.toString() ?? '') ?? 0;
      _dbg('Registrations count = $length');

      for (var i = 0; i < length; i++) {
        final regAny = regsObj.getProperty(i.toString().toJS);
        final reg = _asJsObject(regAny);
        if (reg == null) continue;

        final scriptUrl = _registrationScriptUrl(reg);
        _dbg('Registration[$i] scriptURL = ${scriptUrl ?? "(none)"}');

        if (scriptUrl != null && scriptUrl.contains('/push-sw.js')) {
          return reg;
        }
      }

      return null;
    } catch (e) {
      _dbg('getRegistrations failed: $e');
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
      if (registerAny == null) {
        _dbg('serviceWorker.register missing');
        return null;
      }

      _dbg('Calling serviceWorker.register(/push-sw.js) ...');
      final regAny = await _awaitPromise(
        (registerAny as JSFunction).callAsFunction(
          sw,
          '/push-sw.js'.toJS,
          <String, Object?>{'scope': '/'}.jsify(),
        ),
        label: 'serviceWorker.register(/push-sw.js)',
      );

      final reg = _asJsObject(regAny);
      if (reg == null) {
        _dbg('register(/push-sw.js) returned non-object/null');
      }
      return reg;
    } catch (e) {
      _dbg('register(/push-sw.js) failed: $e');
      return null;
    }
  }

  Future<JSAny?> _awaitPromise(
      JSAny? promiseLike, {
        required String label,
        Duration timeout = const Duration(seconds: 10),
      }) async {
    if (promiseLike == null) return null;

    try {
      final promise = promiseLike as JSPromise<JSAny?>;
      return promise.toDart.timeout(
        timeout,
        onTimeout: () => throw TimeoutException('Timed out waiting for $label'),
      );
    } catch (e) {
      _dbg('Promise cast/await failed for $label: $e');
      rethrow;
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
}

PushStatusProbe createPushStatusProbeImpl() => _WebPushStatusProbe();