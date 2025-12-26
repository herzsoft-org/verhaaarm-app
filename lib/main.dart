import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app/router.dart';
import 'app/theme.dart';
import 'common/cache/app_cache.dart';

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

      // Global safe-area handling (prevents content from rendering behind
      // Android gesture/3-button navigation bar without adding SafeArea on every page)
      builder: (context, child) {
        final c = child;
        if (c == null) return const SizedBox.shrink();

        return SafeArea(
          top: false,     // leave status bar behavior unchanged
          bottom: true,   // protect from Android nav bar
          left: false,
          right: false,
          child: c,
        );
      },
    );
  }
}
