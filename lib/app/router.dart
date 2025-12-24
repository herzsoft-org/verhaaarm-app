import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'route_observer.dart';

import '../api/api_client.dart';
import '../auth/auth_store.dart';
import '../auth/login_page.dart';
import '../features/home/home_page.dart';
import '../features/profile/profile_page.dart';

import '../features/fines/fines_list_page.dart';
import '../features/fines/fine_detail_page.dart';
import '../features/fines/fine_form_page.dart';
import '../features/fines/my_fines_page.dart';
import '../features/live_events/live_events_page.dart';
import '../features/live_events/live_event_form_page.dart';


Future<GoRouter> buildRouter() async {
  final authStore = AuthStore();
  await authStore.init();

  final api = ApiClient(authStore: authStore);

  // On app start: if we have refresh token but no access token (or it expired earlier), try refresh.
  if (!authStore.isLoggedIn) {
    await authStore.tryRefresh(api);
  }

  return GoRouter(
    observers: [routeObserver],
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

      GoRoute(
        path: '/my-fines',
        builder: (context, state) => MyFinesPage(api: api),
      ),

      GoRoute(
        path: '/fines',
        builder: (context, state) => FinesListPage(api: api),
      ),
      GoRoute(
        path: '/fines/new',
        builder: (context, state) => FineFormPage(api: api, mode: FineFormMode.official),
      ),
      GoRoute(
        path: '/suggestions/new',
        builder: (context, state) => FineFormPage(api: api, mode: FineFormMode.suggestion),
      ),
      GoRoute(
        path: '/fines/:id',
        builder: (context, state) => FineDetailPage(
          api: api,
          fineId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/live-events',
        builder: (context, state) => LiveEventsPage(api: api, authStore: authStore),
      ),
      GoRoute(
        path: '/live-events/new',
        builder: (context, state) => LiveEventFormPage(api: api, authStore: authStore),
      ),
      GoRoute(
        path: '/live-events/:id/edit',
        builder: (context, state) => LiveEventFormPage(
          api: api,
          authStore: authStore,
          liveEventId: state.pathParameters['id']!,
        ),
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
