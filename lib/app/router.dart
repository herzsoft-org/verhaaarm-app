import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'main_tab_shell.dart';
import 'route_observer.dart';
import 'dart:async';

import '../common/settings/app_settings_store.dart';
import '../api/api_client.dart';
import '../auth/auth_store.dart';
import '../auth/login_page.dart';
import '../features/paukstunden/my_paukstunden_page.dart';
import '../features/paukstunden/paukstunde_form_page.dart';
import '../features/paukstunden/fechtwart_page.dart';

import '../features/fines/fines_list_page.dart';
import '../features/fines/fine_detail_page.dart';
import '../features/fines/fine_form_page.dart';
import '../features/fines/my_fines_page.dart';
import '../features/office/office_page.dart';
import '../features/office/users/users_page.dart';
import '../features/office/users/user_form_page.dart';
import '../features/office/users/user_password_page.dart';
import '../features/office/users/active_member_stats_page.dart';
import '../features/office/catalog/catalog_page.dart';
import '../features/office/catalog/catalog_form_page.dart';
import '../features/office/periods/periods_page.dart';
import '../features/office/periods/period_form_page.dart';
import '../features/office/fine_suggestions/office_fine_suggestions_page.dart';
import '../features/fines/my_fine_suggestions_page.dart';
import '../features/fines/fine_suggestion_detail_page.dart';

import '../features/legal/legal_document.dart';
import '../features/legal/legal_documents_page.dart';
import '../features/legal/legal_document_viewer_page.dart';

import '../features/live_events/live_events_page.dart';
import '../features/live_events/live_event_form_page.dart';

import '../features/events/events_page.dart';
import '../features/events/event_form_page.dart';

import '../features/tasks/tasks_page.dart';
import '../features/tasks/task_form_page.dart';
import '../features/office/tasks/office_tasks_page.dart';

import '../features/notifications/notifications_page.dart';
import '../notifications/notification_center.dart';
import '../notifications/notification_router.dart';
import '../push/push_manager.dart';
import '../push/push_fcm.dart' show setPushTapHandler;

import '../models/dtos.dart';
import '../auth/roles.dart';

import '../features/profile/sessions_page.dart';
import '../features/office/session_stats_page.dart';

import '../features/office/periods/period_protocol_page.dart';
import '../features/profile/convent_protocols_page.dart';

import '../features/office/admin_sessions_page.dart';
import '../features/office/admin_user_sessions_page.dart';

final GlobalKey<NavigatorState> rootNavKey = GlobalKey<NavigatorState>();

GoRouter? _appRouter;
GoRouter get appRouter => _appRouter!;

Widget _noAccessPage() {
  return const Scaffold(body: Center(child: Text('Kein Zugriff.')));
}

Set<AppRole> _roles(AuthStore authStore) {
  return authStore.currentRoles;
}

bool _canAccessLocation(String location, Set<AppRole> roles) {
  if (location == '/login') return true;
  if (location == '/home') return true;
  if (location == '/actions' || location.startsWith('/actions/')) return true;
  if (location == '/profile' || location.startsWith('/profile/')) return true;
  if (location == '/notifications' || location.startsWith('/notifications/')) {
    return true;
  }
  if (location == '/legal-documents' ||
      location.startsWith('/legal-documents/')) {
    return true;
  }
  if (location == '/convent-protocols' ||
      location.startsWith('/convent-protocols/')) {
    return true;
  }
  if (location == '/events' || location.startsWith('/events/')) return true;
  if (location == '/tasks' || location.startsWith('/tasks/')) return true;
  if (location == '/my-fines' || location.startsWith('/my-fines/')) return true;
  if (location == '/my-fine-suggestions' ||
      location.startsWith('/my-fine-suggestions/')) {
    return true;
  }
  if (location == '/suggestions/new') return true;
  if (location.startsWith('/suggestions/')) return true;
  if (location == '/live-events' || location.startsWith('/live-events/')) {
    return true;
  }
  if (location == '/paukstunden/me' || location == '/paukstunden/new') {
    return true;
  }
  if (location.startsWith('/office/active-member-stats')) {
    return true;
  }

  if (location == '/fines' || location.startsWith('/fines/')) {
    if (location == '/fines/new') return Roles.canCreateOfficialFine(roles);
    return Roles.canSeeAllFines(roles);
  }

  if (location == '/office') return Roles.canAccessOffice(roles);

  if (location.startsWith('/office/fechtwart')) {
    return Roles.canManagePaukstunden(roles);
  }

  if (location.startsWith('/office/fine-suggestions')) {
    return Roles.canAcceptFineSuggestions(roles);
  }

  if (location.startsWith('/office/tasks')) {
    return Roles.canManageTasks(roles);
  }

  if (location.startsWith('/office/session-stats')) {
    return Roles.canManageSessions(roles);
  }

  if (location.startsWith('/office/sessions')) {
    return Roles.canManageSessions(roles);
  }

  if (location.startsWith('/office/periods')) {
    return Roles.canManagePeriods(roles);
  }

  if (location.startsWith('/office/users')) {
    return Roles.canManageUsers(roles);
  }

  if (location.startsWith('/office/catalog')) {
    return Roles.canManageCatalog(roles);
  }

  return true;
}

Future<GoRouter> buildRouter() async {
  final authStore = AuthStore();
  await authStore.init();

  final api = ApiClient(authStore: authStore);

  if (!authStore.isLoggedIn) {
    await authStore.tryRefresh(api);
  }

  if (authStore.isLoggedIn) {
    await AppSettingsStore.I.syncWithBackend(api);

    try {
      await authStore.refreshMe(api, force: true);
    } catch (_) {
      // Keep token-derived roles until /users/me is reachable.
    }
  }

  NotificationCenter.I.init(api: api, authStore: authStore);

  final push = PushManager(api: api, authStore: authStore);

  authStore.addListener(() {
    if (authStore.isLoggedIn) {
      push.initAndRegisterBestEffort();
      NotificationCenter.I.refreshUnreadCount();

      unawaited(AppSettingsStore.I.syncWithBackend(api));
      unawaited(authStore.refreshMeIfStale(api));
    } else {
      push.stop();
      NotificationCenter.I.reset();
    }
  });

  if (authStore.isLoggedIn) {
    push.initAndRegisterBestEffort();
    NotificationCenter.I.refreshUnreadCount();
  }

  final router = GoRouter(
    navigatorKey: rootNavKey,
    observers: [routeObserver],
    initialLocation: '/home',
    refreshListenable: authStore,
    redirect: (context, state) {
      final loggedIn = authStore.isLoggedIn;
      final goingToLogin = state.matchedLocation == '/login';

      if (!loggedIn && !goingToLogin) return '/login';
      if (loggedIn && goingToLogin) return '/home';

      if (loggedIn) {
        unawaited(authStore.refreshMeIfStale(api));

        final location = state.matchedLocation;
        final roles = _roles(authStore);

        if (!_canAccessLocation(location, roles)) {
          return '/home';
        }
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => LoginPage(api: api, authStore: authStore),
      ),
      GoRoute(
        path: '/home',
        builder: (context, state) =>
            MainTabShell(api: api, authStore: authStore, initialIndex: 0),
      ),
      GoRoute(
        path: '/actions',
        builder: (context, state) =>
            MainTabShell(api: api, authStore: authStore, initialIndex: 1),
      ),
      GoRoute(
        path: '/profile',
        builder: (context, state) =>
            MainTabShell(api: api, authStore: authStore, initialIndex: 2),
      ),
      GoRoute(
        path: '/paukstunden/me',
        builder: (context, state) => MyPaukstundenPage(api: api),
      ),
      GoRoute(
        path: '/paukstunden/new',
        builder: (context, state) =>
            PaukstundeFormPage(api: api, authStore: authStore),
      ),
      GoRoute(
        path: '/profile/sessions',
        builder: (context, state) => SessionsPage(api: api),
      ),
      GoRoute(
        path: '/notifications',
        builder: (context, state) =>
            NotificationsPage(api: api, authStore: authStore),
      ),

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
      GoRoute(
        path: '/tasks/:id/edit',
        builder: (context, state) {
          final TaskDto? t = state.extra is TaskDto
              ? state.extra as TaskDto
              : null;

          return TaskFormPage(
            api: api,
            authStore: authStore,
            initial: t,
            isEdit: true,
            isAdminEdit: false,
          );
        },
      ),
      GoRoute(
        path: '/legal-documents',
        builder: (context, state) => const LegalDocumentsPage(),
      ),

      GoRoute(
        path: '/legal-documents/:id',
        builder: (context, state) {
          final id = state.pathParameters['id'] ?? '';
          final doc = LegalDocument.byId(id);

          if (doc == null) {
            return const LegalDocumentsPage();
          }

          return LegalDocumentViewerPage(document: doc);
        },
      ),
      GoRoute(
        path: '/convent-protocols',
        builder: (context, state) => ConventProtocolsPage(api: api),
      ),
      GoRoute(
        path: '/convent-protocols/:id',
        builder: (context, state) {
          final period = state.extra is ConventPeriodDto
              ? state.extra as ConventPeriodDto
              : null;

          return PeriodProtocolPage(
            api: api,
            periodId: state.pathParameters['id']!,
            initialPeriod: period,
          );
        },
      ),
      GoRoute(
        path: '/events',
        builder: (context, state) => EventsPage(api: api, authStore: authStore),
      ),
      GoRoute(
        path: '/events/new',
        builder: (context, state) =>
            EventFormPage(api: api, authStore: authStore),
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
        builder: (context, state) {
          final roles = _roles(authStore);
          if (!Roles.canSeeAllFines(roles)) return _noAccessPage();

          return FinesListPage(api: api, authStore: authStore);
        },
      ),
      GoRoute(
        path: '/fines/new',
        builder: (context, state) {
          final roles = _roles(authStore);
          if (!Roles.canCreateOfficialFine(roles)) return _noAccessPage();

          return FineFormPage(
            api: api,
            authStore: authStore,
            mode: FineFormMode.official,
          );
        },
      ),
      GoRoute(
        path: '/my-fine-suggestions',
        builder: (context, state) => MyFineSuggestionsPage(api: api),
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
        path: '/suggestions/:id',
        builder: (context, state) => FineSuggestionDetailPage(
          api: api,
          authStore: authStore,
          suggestionId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/suggestions/:id/edit',
        builder: (context, state) => FineFormPage(
          api: api,
          authStore: authStore,
          mode: FineFormMode.suggestion,
          suggestionId: state.pathParameters['id'],
        ),
      ),
      GoRoute(
        path: '/fines/:id',
        builder: (context, state) {
          final roles = _roles(authStore);
          if (!Roles.canViewFineDetails(roles)) return _noAccessPage();

          return FineDetailPage(
            api: api,
            authStore: authStore,
            fineId: state.pathParameters['id']!,
          );
        },
      ),

      GoRoute(
        path: '/office/fine-suggestions',
        builder: (context, state) {
          final roles = _roles(authStore);
          if (!Roles.canAcceptFineSuggestions(roles)) return _noAccessPage();

          return OfficeFineSuggestionsPage(api: api, authStore: authStore);
        },
      ),

      GoRoute(
        path: '/live-events',
        builder: (context, state) =>
            LiveEventsPage(api: api, authStore: authStore),
      ),
      GoRoute(
        path: '/live-events/new',
        builder: (context, state) =>
            LiveEventFormPage(api: api, authStore: authStore),
      ),
      GoRoute(
        path: '/live-events/:id/edit',
        builder: (context, state) => LiveEventFormPage(
          api: api,
          authStore: authStore,
          liveEventId: state.pathParameters['id']!,
        ),
      ),

      GoRoute(
        path: '/office',
        builder: (context, state) {
          final roles = _roles(authStore);
          if (!Roles.canAccessOffice(roles)) return _noAccessPage();

          return OfficePage(api: api, authStore: authStore);
        },
      ),
      GoRoute(
        path: '/office/fechtwart',
        builder: (context, state) {
          final roles = _roles(authStore);
          if (!Roles.canManagePaukstunden(roles)) return _noAccessPage();

          return FechtwartPage(api: api, authStore: authStore);
        },
      ),
      GoRoute(
        path: '/office/fechtwart/paukstunden/new',
        builder: (context, state) {
          final roles = _roles(authStore);
          if (!Roles.canManagePaukstunden(roles)) return _noAccessPage();

          return PaukstundeFormPage(
            api: api,
            authStore: authStore,
            fechtwartMode: true,
          );
        },
      ),

      GoRoute(
        path: '/office/tasks',
        builder: (context, state) {
          final roles = _roles(authStore);
          if (!Roles.canManageTasks(roles)) return _noAccessPage();

          return OfficeTasksPage(api: api, authStore: authStore);
        },
      ),
      GoRoute(
        path: '/office/session-stats',
        builder: (context, state) {
          final roles = _roles(authStore);
          if (!Roles.canManageSessions(roles)) return _noAccessPage();

          return SessionStatsPage(api: api, authStore: authStore);
        },
      ),
      GoRoute(
        path: '/office/sessions',
        builder: (context, state) {
          final roles = _roles(authStore);
          if (!Roles.canManageSessions(roles)) return _noAccessPage();

          return AdminSessionsPage(api: api, authStore: authStore);
        },
      ),
      GoRoute(
        path: '/office/sessions/users/:userId',
        builder: (context, state) {
          final roles = _roles(authStore);
          if (!Roles.canManageSessions(roles)) return _noAccessPage();

          final userId = state.pathParameters['userId']!;
          return AdminUserSessionsPage(
            api: api,
            authStore: authStore,
            userId: userId,
          );
        },
      ),
      GoRoute(
        path: '/office/tasks/new',
        builder: (context, state) {
          final roles = _roles(authStore);
          if (!Roles.canManageTasks(roles)) return _noAccessPage();

          return TaskFormPage(
            api: api,
            authStore: authStore,
            isEdit: false,
            isAdminEdit: true,
          );
        },
      ),
      GoRoute(
        path: '/office/tasks/:id/edit',
        builder: (context, state) {
          final roles = _roles(authStore);
          if (!Roles.canManageTasks(roles)) return _noAccessPage();

          final TaskDto? t = state.extra is TaskDto
              ? state.extra as TaskDto
              : null;

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
        builder: (context, state) {
          final roles = _roles(authStore);
          if (!Roles.canManagePeriods(roles)) return _noAccessPage();

          return PeriodsPage(api: api, authStore: authStore);
        },
      ),
      GoRoute(
        path: '/office/periods/new',
        builder: (context, state) {
          final roles = _roles(authStore);
          if (!Roles.canManagePeriods(roles)) return _noAccessPage();

          return PeriodFormPage(api: api, authStore: authStore);
        },
      ),
      GoRoute(
        path: '/office/periods/:id/edit',
        builder: (context, state) {
          final roles = _roles(authStore);
          if (!Roles.canManagePeriods(roles)) return _noAccessPage();

          return PeriodFormPage(
            api: api,
            authStore: authStore,
            periodId: state.pathParameters['id']!,
          );
        },
      ),
      GoRoute(
        path: '/office/periods/:id/protocol',
        builder: (context, state) {
          final period = state.extra is ConventPeriodDto
              ? state.extra as ConventPeriodDto
              : null;

          return PeriodProtocolPage(
            api: api,
            periodId: state.pathParameters['id']!,
            initialPeriod: period,
          );
        },
      ),
      GoRoute(
        path: '/office/users',
        builder: (context, state) {
          final roles = _roles(authStore);
          if (!Roles.canManageUsers(roles)) return _noAccessPage();

          return UsersPage(api: api, authStore: authStore);
        },
      ),
      GoRoute(
        path: '/office/users/new',
        builder: (context, state) {
          final roles = _roles(authStore);
          if (!Roles.canManageUsers(roles)) return _noAccessPage();

          return UserFormPage(api: api, authStore: authStore);
        },
      ),
      GoRoute(
        path: '/office/users/:id/edit',
        builder: (context, state) {
          final roles = _roles(authStore);
          if (!Roles.canManageUsers(roles)) return _noAccessPage();

          return UserFormPage(
            api: api,
            authStore: authStore,
            userId: state.pathParameters['id']!,
          );
        },
      ),
      GoRoute(
        path: '/office/users/:id/password',
        builder: (context, state) {
          final roles = _roles(authStore);
          if (!Roles.canManageUsers(roles)) return _noAccessPage();

          return UserPasswordPage(
            api: api,
            authStore: authStore,
            userId: state.pathParameters['id']!,
          );
        },
      ),
      GoRoute(
        path: '/office/active-member-stats',
        builder: (context, state) {
          return ActiveMemberStatsPage(api: api, authStore: authStore);
        },
      ),
      GoRoute(
        path: '/office/catalog',
        builder: (context, state) {
          final roles = _roles(authStore);
          if (!Roles.canManageCatalog(roles)) return _noAccessPage();

          return CatalogPage(api: api, authStore: authStore);
        },
      ),
      GoRoute(
        path: '/office/catalog/new',
        builder: (context, state) {
          final roles = _roles(authStore);
          if (!Roles.canManageCatalog(roles)) return _noAccessPage();

          return CatalogFormPage(api: api, authStore: authStore);
        },
      ),
      GoRoute(
        path: '/office/catalog/:id/edit',
        builder: (context, state) {
          final roles = _roles(authStore);
          if (!Roles.canManageCatalog(roles)) return _noAccessPage();

          return CatalogFormPage(
            api: api,
            authStore: authStore,
            itemId: state.pathParameters['id']!,
          );
        },
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

  _appRouter = router;

  // IMPORTANT: must be after _appRouter is set
  setPushTapHandler((data) => routeNotificationClick(appRouter, data));

  return router;
}
