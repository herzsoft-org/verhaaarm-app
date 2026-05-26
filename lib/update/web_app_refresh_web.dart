import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

@JS('fetch')
external JSPromise<JSAny?> _fetch(JSAny input, [JSAny? init]);

Future<void> forceReloadWebApp() async {
  await _deleteBrowserCaches();
  await _refreshMutableAppAssets();
  await _unregisterFlutterServiceWorkersOnly();

  web.window.location.reload();
}

Future<void> _refreshMutableAppAssets() async {
  try {
    final manifestText = await _fetchTextWithCacheReload(
      _assetUrl('assets/FontManifest.json'),
    );
    if (manifestText == null || manifestText.isEmpty) {
      return;
    }

    final manifest = jsonDecode(manifestText);
    if (manifest is! List) {
      return;
    }

    final fontUrls = <String>{};
    for (final family in manifest) {
      if (family is! Map) continue;

      final fonts = family['fonts'];
      if (fonts is! List) continue;

      for (final font in fonts) {
        if (font is! Map) continue;

        final asset = font['asset'];
        if (asset is String && asset.isNotEmpty) {
          fontUrls.add(_assetUrl('assets/${_stripLeadingSlashes(asset)}'));
        }
      }
    }

    for (final url in fontUrls) {
      await _fetchWithCacheReload(url);
    }
  } catch (_) {
    // Best effort only. CacheStorage cleanup and service worker unregistering
    // should still run even if one asset refresh fails.
  }
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
    await caches.callMethod<JSPromise<JSBoolean>>('delete'.toJS, key).toDart;
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

  final registrationsPromise = serviceWorker
      .callMethod<JSPromise<JSArray<JSAny>>>('getRegistrations'.toJS);

  final registrations = (await registrationsPromise.toDart).toDart;

  for (final registrationAny in registrations) {
    final registration = registrationAny as JSObject;
    final scriptUrl = _scriptUrlForRegistration(registration);

    // Keep your custom Web Push service worker alive.
    // Only unregister Flutter's generated app-cache service worker.
    if (scriptUrl != null && scriptUrl.contains('flutter_service_worker.js')) {
      await registration
          .callMethod<JSPromise<JSBoolean>>('unregister'.toJS)
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

Future<String?> _fetchTextWithCacheReload(String url) async {
  final responseAny = await _fetchWithCacheReload(url);
  if (responseAny == null || responseAny.isUndefinedOrNull) {
    return null;
  }

  final response = responseAny as JSObject;
  final textPromise = response.callMethod<JSPromise<JSString>>('text'.toJS);
  return (await textPromise.toDart).toDart;
}

Future<JSAny?> _fetchWithCacheReload(String url) {
  final init = JSObject()
    ..setProperty('cache'.toJS, 'reload'.toJS)
    ..setProperty('credentials'.toJS, 'same-origin'.toJS);

  return _fetch(url.toJS, init).toDart;
}

String _assetUrl(String path) {
  final baseUri = web.document.baseURI;
  final separator = baseUri.endsWith('/') ? '' : '/';
  return '$baseUri$separator${_stripLeadingSlashes(path)}';
}

String _stripLeadingSlashes(String value) {
  var index = 0;
  while (index < value.length && value.codeUnitAt(index) == 47) {
    index++;
  }
  return value.substring(index);
}
