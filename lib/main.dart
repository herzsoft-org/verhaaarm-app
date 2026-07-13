import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app/router.dart';
import 'app/theme.dart';
import 'common/cache/app_cache.dart';
import 'common/connectivity/connectivity_center.dart';
import 'common/settings/app_settings_store.dart';

// Firebase (only initialize on non-web)
import 'package:firebase_core/firebase_core.dart';

import 'push/push_fcm.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppCache.I.init();
  await AppSettingsStore.I.initLocal();
  await initializeDateFormatting('de_DE', null);

  if (!kIsWeb) {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  }

  final router = await buildRouter();
  runApp(VerhaaarmApp(router: router));
}

class VerhaaarmApp extends StatelessWidget {
  final RouterConfig<Object> router;

  const VerhaaarmApp({super.key, required this.router});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppSettingsStore.I,
      builder: (context, _) {
        return MaterialApp.router(
          title: 'Verhåårm',
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(Brightness.light),
          darkTheme: buildAppTheme(Brightness.dark),
          themeMode: AppSettingsStore.I.themeMode,
          routerConfig: router,
          builder: (context, child) {
            if (child == null) return const SizedBox.shrink();
            return _ConnectivityLifecycle(
              child: SafeArea(
                top: false,
                bottom: true,
                left: false,
                right: false,
                child: child,
              ),
            );
          },
        );
      },
    );
  }
}

class _ConnectivityLifecycle extends StatefulWidget {
  final Widget child;

  const _ConnectivityLifecycle({required this.child});

  @override
  State<_ConnectivityLifecycle> createState() => _ConnectivityLifecycleState();
}

class _ConnectivityLifecycleState extends State<_ConnectivityLifecycle>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycleState = WidgetsBinding.instance.lifecycleState;
    ConnectivityCenter.I.setAppForeground(
      lifecycleState == null || lifecycleState == AppLifecycleState.resumed,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    ConnectivityCenter.I.setAppForeground(state == AppLifecycleState.resumed);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ConnectivityCenter.I.setAppForeground(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
