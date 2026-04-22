// ignore_for_file: avoid_web_libraries_in_flutter

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
      final readyAny = sw.getProperty('ready'.toJS);
      if (readyAny == null) return PushStatus.disabled;

      final readyPromise = readyAny as JSPromise<JSAny?>;
      final regResolved = await readyPromise.toDart;
      if (regResolved == null) return PushStatus.disabled;

      final reg = regResolved as JSObject;

      final pushManagerAny = reg.getProperty('pushManager'.toJS);
      if (pushManagerAny == null) return PushStatus.disabled;

      final pushManager = pushManagerAny as JSObject;
      final getSubscriptionAny = pushManager.getProperty('getSubscription'.toJS);
      if (getSubscriptionAny == null) return PushStatus.disabled;

      final subPromise =
      (getSubscriptionAny as JSFunction).callAsFunction(pushManager) as JSPromise<JSAny?>;
      final subAny = await subPromise.toDart;

      if (subAny == null) {
        return PushStatus.disabled;
      }

      return PushStatus.enabled;
    } catch (_) {
      return PushStatus.error;
    }
  }
}

PushStatusProbe createPushStatusProbeImpl() => _WebPushStatusProbe();