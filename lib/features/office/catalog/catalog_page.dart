import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../api/api_client.dart';
import '../../../auth/auth_store.dart';
import '../../../auth/roles.dart';
import '../../../common/format.dart';
import '../../../common/widgets/app_scaffold.dart';
import '../../../models/dtos.dart';

class CatalogPage extends StatefulWidget {
  final ApiClient api;
  final AuthStore authStore;

  const CatalogPage({super.key, required this.api, required this.authStore});

  @override
  State<CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends State<CatalogPage> {
  bool _loading = true;
  List<FineCatalogItemDto> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final items = await widget.api.listFineCatalog(active: null);
      items.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

      if (!mounted) return;
      setState(() => _items = items);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Katalog laden fehlgeschlagen: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final roles = Roles.fromAccessToken(widget.authStore.accessToken);
    final can = Roles.canManageCatalog(roles);

    return AppScaffold(
      title: 'Feinkatalog',
      actions: [
        IconButton(
          tooltip: 'Neu laden',
          icon: const Icon(Icons.refresh_rounded),
          onPressed: _loading ? null : _load,
        ),
        if (can)
          IconButton(
            tooltip: 'Neuer Eintrag',
            icon: const Icon(Icons.add_rounded),
            onPressed: () => context.push('/office/catalog/new'),
          ),
      ],
      body: !can
          ? const Center(child: Text('Keine Berechtigung.'))
          : _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (_items.isEmpty)
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text('Keine Katalogeinträge gefunden.'),
            ),
          for (final it in _items)
            Card(
              child: ListTile(
                leading: Icon(it.active ? Icons.check_circle_rounded : Icons.remove_circle_rounded),
                title: Text(it.title),
                subtitle: Text(
                  'Default: ${Format.centsToEur(it.defaultAmountCents ?? 0)}'
                      '${it.active ? '' : '\nInaktiv'}',
                ),
                isThreeLine: !it.active,
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push('/office/catalog/${it.id}/edit'),
              ),
            ),
        ],
      ),
    );
  }
}
