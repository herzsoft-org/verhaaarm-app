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
import '../features/office/office_page.dart';
import '../features/office/users/users_page.dart';
import '../features/office/users/user_form_page.dart';
import '../features/office/users/user_password_page.dart';
import '../features/office/catalog/catalog_page.dart';
import '../features/office/catalog/catalog_form_page.dart';
import '../features/office/periods/periods_page.dart';
import '../features/office/periods/period_form_page.dart';
import '../features/office/fine_suggestions/office_fine_suggestions_page.dart';

import '../features/live_events/live_events_page.dart';
import '../features/live_events/live_event_form_page.dart';

import '../features/events/events_page.dart';
import '../features/events/event_form_page.dart';

import '../features/tasks/tasks_page.dart';
import '../features/tasks/task_form_page.dart';
import '../features/office/tasks/office_tasks_page.dart';

import '../models/dtos.dart';
import '../auth/roles.dart';

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

      // --- Tasks (my)
      GoRoute(
        path: '/tasks',
        builder: (context, state) => TasksPage(api: api, authStore: authStore),
      ),
      GoRoute(
        path: '/tasks/new',
        builder: (context, state) => TaskFormPage(
          api: api,
          authStore: authStore,
          isEdit: false,
          isAdminEdit: false,
        ),
      ),

      // --- Events (scheduled)
      GoRoute(
        path: '/events',
        builder: (context, state) => EventsPage(api: api, authStore: authStore),
      ),
      GoRoute(
        path: '/events/new',
        builder: (context, state) => EventFormPage(api: api, authStore: authStore),
      ),
      GoRoute(
        path: '/events/:id/edit',
        builder: (context, state) => EventFormPage(
          api: api,
          authStore: authStore,
          eventId: state.pathParameters['id']!,
        ),
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
        builder: (context, state) => FineFormPage(
          api: api,
          authStore: authStore,
          mode: FineFormMode.official,
        ),
      ),
      GoRoute(
        path: '/suggestions/new',
        builder: (context, state) => FineFormPage(
          api: api,
          authStore: authStore,
          mode: FineFormMode.suggestion,
        ),
      ),

      GoRoute(
        path: '/fines/:id',
        builder: (context, state) => FineDetailPage(
          api: api,
          authStore: authStore,
          fineId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/office/fine-suggestions',
        builder: (context, state) => OfficeFineSuggestionsPage(
          api: api,
          authStore: authStore,
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

      // --- Office
      GoRoute(
        path: '/office',
        builder: (context, state) => OfficePage(api: api, authStore: authStore),
      ),

      // Office: Tasks (ADMIN)
      GoRoute(
        path: '/office/tasks',
        builder: (context, state) => OfficeTasksPage(api: api, authStore: authStore),
      ),
      GoRoute(
        path: '/office/tasks/:id/edit',
        builder: (context, state) {
          final roles = Roles.fromAccessToken(authStore.accessToken);
          if (!Roles.canManageTasks(roles)) {
            return const Scaffold(body: Center(child: Text('Kein Zugriff.')));
          }

          // We pass TaskDto as extra from OfficeTasksPage for instant edit.
          final TaskDto? t = state.extra is TaskDto ? state.extra as TaskDto : null;

          return TaskFormPage(
            api: api,
            authStore: authStore,
            initial: t,
            isEdit: true,
            isAdminEdit: true,
          );
        },
      ),

      GoRoute(
        path: '/office/periods',
        builder: (context, state) => PeriodsPage(api: api, authStore: authStore),
      ),
      GoRoute(
        path: '/office/periods/new',
        builder: (context, state) => PeriodFormPage(api: api, authStore: authStore),
      ),
      GoRoute(
        path: '/office/periods/:id/edit',
        builder: (context, state) => PeriodFormPage(
          api: api,
          authStore: authStore,
          periodId: state.pathParameters['id']!,
        ),
      ),

      // Users
      GoRoute(
        path: '/office/users',
        builder: (context, state) => UsersPage(api: api, authStore: authStore),
      ),
      GoRoute(
        path: '/office/users/new',
        builder: (context, state) => UserFormPage(api: api, authStore: authStore),
      ),
      GoRoute(
        path: '/office/users/:id/edit',
        builder: (context, state) => UserFormPage(
          api: api,
          authStore: authStore,
          userId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/office/users/:id/password',
        builder: (context, state) => UserPasswordPage(
          api: api,
          authStore: authStore,
          userId: state.pathParameters['id']!,
        ),
      ),

      // Catalog
      GoRoute(
        path: '/office/catalog',
        builder: (context, state) => CatalogPage(api: api, authStore: authStore),
      ),
      GoRoute(
        path: '/office/catalog/new',
        builder: (context, state) => CatalogFormPage(api: api, authStore: authStore),
      ),
      GoRoute(
        path: '/office/catalog/:id/edit',
        builder: (context, state) => CatalogFormPage(
          api: api,
          authStore: authStore,
          itemId: state.pathParameters['id']!,
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
