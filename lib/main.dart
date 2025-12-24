import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app/router.dart';
import 'app/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
    );
  }
}
