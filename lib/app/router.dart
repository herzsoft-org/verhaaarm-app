import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../api/api_client.dart';
import '../auth/auth_store.dart';
import '../auth/login_page.dart';
import '../features/home/home_page.dart';
import '../features/profile/profile_page.dart';

Future<GoRouter> buildRouter() async {
  final authStore = AuthStore();
  await authStore.init();

  final api = ApiClient(authStore: authStore);

  return GoRouter(
    initialLocation: '/home',
    refreshListenable: authStore,
    redirect: (context, state) {
      final loggedIn = authStore.isLoggedIn;

      final goingToLogin = state.matchedLocation == '/login';

      if (!loggedIn && !goingToLogin) return '/login';
      if (loggedIn && goingToLogin) return '/home';

      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => LoginPage(api: api, authStore: authStore),
      ),
      GoRoute(
        path: '/home',
        builder: (context, state) => HomePage(api: api, authStore: authStore),
      ),
      GoRoute(
        path: '/profile',
        builder: (context, state) => ProfilePage(api: api, authStore: authStore),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Navigation fehlgeschlagen: ${state.error}'),
        ),
      ),
    ),
  );
}
