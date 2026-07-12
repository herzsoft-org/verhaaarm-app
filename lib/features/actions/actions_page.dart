import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../api/api_client.dart';
import '../../auth/auth_store.dart';
import '../../auth/roles.dart';
import '../../common/widgets/app_scaffold.dart';
import '../../models/member_status.dart';

class ActionsPage extends StatelessWidget {
  final ApiClient api;
  final AuthStore authStore;
  final bool showBottomNavigationBar;
  final String? locationOverride;

  const ActionsPage({
    super.key,
    required this.api,
    required this.authStore,
    this.showBottomNavigationBar = true,
    this.locationOverride,
  });

  @override
  Widget build(BuildContext context) {
    final roles = authStore.currentRoles;
    final canOffice = Roles.canAccessOffice(roles);
    final canOfficialFine = Roles.canCreateOfficialFine(roles);
    final isPhilister = MemberStatuses.isPhilister(
      authStore.currentUser?.memberStatus,
    );

    return AppScaffold(
      title: 'Aktionen',
      showBottomNavigationBar: showBottomNavigationBar,
      locationOverride: locationOverride,
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _Section(
            title: 'Spaß',
            children: [
              ListTile(
                leading: const Icon(Icons.ac_unit_rounded),
                title: const Text('Slushy Rezepte'),
                trailing: const Icon(Icons.chevron_right_rounded),
                titleAlignment: ListTileTitleAlignment.center,
                onTap: () => context.push('/slushy-recipes'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _Section(
            title: 'Allgemein',
            children: [
              ListTile(
                leading: const Icon(Icons.assignment_rounded),
                title: const Text('Arbeitsaufträge'),
                trailing: const Icon(Icons.chevron_right_rounded),
                titleAlignment: ListTileTitleAlignment.center,
                onTap: () => context.push('/tasks'),
              ),
              ListTile(
                leading: const Icon(Icons.add_comment_rounded),
                title: const Text('Beihängung vorschlagen'),
                trailing: const Icon(Icons.chevron_right_rounded),
                titleAlignment: ListTileTitleAlignment.center,
                onTap: () => context.push('/my-fine-suggestions'),
              ),
              if (canOfficialFine)
                ListTile(
                  leading: const Icon(Icons.add_rounded),
                  title: const Text('Beihängen'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  titleAlignment: ListTileTitleAlignment.center,
                  onTap: () => context.push('/fines/new'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _Section(
            title: 'Paukstunden',
            children: [
              ListTile(
                leading: const Icon(Symbols.swords),
                title: const Text('Paukstunde eintragen'),
                trailing: const Icon(Icons.chevron_right_rounded),
                titleAlignment: ListTileTitleAlignment.center,
                onTap: () => context.push('/paukstunden/new'),
              ),
              ListTile(
                leading: const Icon(Icons.list_alt_rounded),
                title: const Text('Meine Paukstunden'),
                trailing: const Icon(Icons.chevron_right_rounded),
                titleAlignment: ListTileTitleAlignment.center,
                onTap: () => context.push('/paukstunden/me'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _Section(
            title: 'Dokumente',
            children: [
              ListTile(
                leading: const Icon(Icons.groups_rounded),
                title: const Text('Aktivenstände'),
                trailing: const Icon(Icons.chevron_right_rounded),
                titleAlignment: ListTileTitleAlignment.center,
                onTap: () => context.push('/office/active-member-stats'),
              ),
              if (!isPhilister)
                ListTile(
                  leading: const Icon(Icons.picture_as_pdf_rounded),
                  title: const Text('Conventsprotokolle'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  titleAlignment: ListTileTitleAlignment.center,
                  onTap: () => context.push('/convent-protocols'),
                ),
              ListTile(
                leading: const Icon(Icons.menu_book_rounded),
                title: const Text('Rechtsgrundlagen'),
                trailing: const Icon(Icons.chevron_right_rounded),
                titleAlignment: ListTileTitleAlignment.center,
                onTap: () => context.push('/legal-documents'),
              ),
            ],
          ),
          if (canOffice) ...[
            const SizedBox(height: 12),
            _Section(
              title: 'Office / Verwaltung',
              children: [
                ListTile(
                  leading: const Icon(Icons.badge_rounded),
                  title: const Text('Amtsausführung'),
                  subtitle: const Text('Alle Verwaltungsfunktionen'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  titleAlignment: ListTileTitleAlignment.center,
                  onTap: () => context.push('/office'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          ...children,
        ],
      ),
    );
  }
}
