import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../api/api_client.dart';
import '../../auth/auth_store.dart';
import '../../auth/roles.dart';
import '../../common/widgets/app_scaffold.dart';

class OfficePage extends StatelessWidget {
  final ApiClient api;
  final AuthStore authStore;

  const OfficePage({super.key, required this.api, required this.authStore});

  @override
  Widget build(BuildContext context) {
    final roles = Roles.fromAccessToken(authStore.accessToken);

    final canUsers = Roles.canManageUsers(roles);
    final canCatalog = Roles.canManageCatalog(roles);
    final canPeriods = Roles.canManagePeriods(roles);

    // Annahme: Vorschläge akzeptieren dürfen Senior/Housekeeping/Admin.
    // Falls du eine explizite Helper-Funktion hast (z.B. Roles.canAcceptFineSuggestions),
    // ersetze diese Zeile entsprechend.
    final canAcceptSuggestions = Roles.canAcceptFineSuggestions(roles);

    return AppScaffold(
      title: 'Amtsausführung',
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _Section(
            title: 'Beihängungen',
            children: [
              ListTile(
                leading: const Icon(Icons.list_alt_rounded),
                title: const Text('Alle Beihängungen'),
                subtitle: const Text('Alle Nutzer, alle Perioden (nach Backend-Rechten)'),
                onTap: () => context.push('/fines'),
              ),
              if (canAcceptSuggestions)
                ListTile(
                  leading: const Icon(Icons.inbox_rounded),
                  title: const Text('Vorgeschlagene Beihängungen'),
                  subtitle: const Text('Ansehen, akzeptieren oder ablehnen'),
                  onTap: () => context.push('/office/fine-suggestions'),
                ),
              ListTile(
                leading: const Icon(Icons.download_rounded),
                title: const Text('CSV Export'),
                subtitle: const Text('Export der Beihängungen (teilen/speichern)'),
                onTap: () => _exportCsv(context),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (canPeriods)
            _Section(
              title: 'Semester & Perioden',
              children: [
                ListTile(
                  leading: const Icon(Icons.date_range_rounded),
                  title: const Text('Semester / Conventsperioden verwalten'),
                  subtitle: const Text('Erstellen, ändern, aktivieren, locken'),
                  onTap: () => context.push('/office/periods'),
                ),
              ],
            ),
          if (canPeriods) const SizedBox(height: 12),

          if (canUsers)
            _Section(
              title: 'Nutzerverwaltung',
              children: [
                ListTile(
                  leading: const Icon(Icons.people_rounded),
                  title: const Text('Nutzer verwalten'),
                  subtitle: const Text('Erstellen, Rollen, deaktivieren, Passwort setzen'),
                  onTap: () => context.push('/office/users'),
                ),
              ],
            ),
          if (canUsers) const SizedBox(height: 12),

          if (canCatalog)
            _Section(
              title: 'Beihängungskatalog',
              children: [
                ListTile(
                  leading: const Icon(Icons.rule_rounded),
                  title: const Text('Katalog verwalten'),
                  subtitle: const Text('Gründe + Default Beträge'),
                  onTap: () => context.push('/office/catalog'),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _exportCsv(BuildContext context) async {
    try {
      final r = await api.exportFinesCsv();
      final data = r.data;

      if (data is! List<int>) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('CSV Export: unerwartetes Response-Format')),
          );
        }
        return;
      }

      if (kIsWeb) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('CSV Export Teilen/Speichern ist im Web UI noch nicht implementiert.')),
          );
        }
        return;
      }

      final dir = await getTemporaryDirectory();
      final ts = DateTime.now().toIso8601String().replaceAll(':', '-');
      final path = '${dir.path}/verhaarm-fines-$ts.csv';

      final f = File(path);
      await f.writeAsBytes(data, flush: true);

      await SharePlus.instance.share(
        ShareParams(
          text: 'Verhåårm – Beihängungen Export',
          files: [XFile(path, mimeType: 'text/csv')],
        ),
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('CSV Export bereit zum Teilen.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('CSV Export fehlgeschlagen: $e')),
        );
      }
    }
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            ...children,
          ],
        ),
      ),
    );
  }
}
