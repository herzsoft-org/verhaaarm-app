import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app/router.dart';
import 'app/theme.dart';
import 'common/cache/app_cache.dart';
import 'common/widgets/mobile_web_keyboard_fix.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppCache.I.init();
  await initializeDateFormatting('de_DE', null);

  final router = await buildRouter();
  runApp(VerhaaarmApp(router: router));
}

class VerhaaarmApp extends StatelessWidget {
  final RouterConfig<Object> router;

  const VerhaaarmApp({super.key, required this.router});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Verhåårm',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      darkTheme: buildAppTheme(),
      themeMode: ThemeMode.dark,
      routerConfig: router,
      builder: (context, child) {
        if (child == null) return const SizedBox.shrink();

        return MobileWebKeyboardFix(
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
  }
}
