import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

Future<void> forceReloadWebApp() async {
  await _deleteBrowserCaches();
  await _unregisterFlutterServiceWorkersOnly();

  web.window.location.reload();
}

Future<void> _deleteBrowserCaches() async {
  final cachesAny = web.window.getProperty<JSAny?>('caches'.toJS);

  if (cachesAny == null || cachesAny.isUndefinedOrNull) {
    return;
  }

  final caches = cachesAny as JSObject;

  final keysPromise = caches.callMethod<JSPromise<JSArray<JSString>>>(
    'keys'.toJS,
  );

  final keys = (await keysPromise.toDart).toDart;

  for (final key in keys) {
    await caches
        .callMethod<JSPromise<JSBoolean>>(
      'delete'.toJS,
      key,
    )
        .toDart;
  }
}

Future<void> _unregisterFlutterServiceWorkersOnly() async {
  final serviceWorkerAny = web.window.navigator.getProperty<JSAny?>(
    'serviceWorker'.toJS,
  );

  if (serviceWorkerAny == null || serviceWorkerAny.isUndefinedOrNull) {
    return;
  }

  final serviceWorker = serviceWorkerAny as JSObject;

  final registrationsPromise =
  serviceWorker.callMethod<JSPromise<JSArray<JSAny>>>(
    'getRegistrations'.toJS,
  );

  final registrations = (await registrationsPromise.toDart).toDart;

  for (final registrationAny in registrations) {
    final registration = registrationAny as JSObject;
    final scriptUrl = _scriptUrlForRegistration(registration);

    // Keep your custom Web Push service worker alive.
    // Only unregister Flutter's generated app-cache service worker.
    if (scriptUrl != null && scriptUrl.contains('flutter_service_worker.js')) {
      await registration
          .callMethod<JSPromise<JSBoolean>>(
        'unregister'.toJS,
      )
          .toDart;
    }
  }
}

String? _scriptUrlForRegistration(JSObject registration) {
  for (final state in const ['active', 'waiting', 'installing']) {
    final workerAny = registration.getProperty<JSAny?>(state.toJS);

    if (workerAny == null || workerAny.isUndefinedOrNull) {
      continue;
    }

    final worker = workerAny as JSObject;
    final scriptUrlAny = worker.getProperty<JSAny?>('scriptURL'.toJS);

    if (scriptUrlAny == null || scriptUrlAny.isUndefinedOrNull) {
      continue;
    }

    final s = (scriptUrlAny as JSString).toDart.trim();

    if (s.isNotEmpty) {
      return s;
    }
  }

  return null;
}