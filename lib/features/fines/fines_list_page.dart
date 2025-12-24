import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../api/api_client.dart';
import '../../common/format.dart';
import '../../common/widgets/app_scaffold.dart';
import '../../models/dtos.dart';

class FinesListPage extends StatefulWidget {
  final ApiClient api;

  const FinesListPage({super.key, required this.api});

  @override
  State<FinesListPage> createState() => _FinesListPageState();
}

class _FinesListPageState extends State<FinesListPage> {
  bool _loading = true;
  List<FineDto> _fines = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await widget.api.listFines();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      if (!mounted) return;
      setState(() => _fines = list);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Beihängungen laden fehlgeschlagen: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Beihängungen',
      actions: [
        IconButton(
          tooltip: 'Neu laden',
          icon: const Icon(Icons.refresh_rounded),
          onPressed: _loading ? null : _load,
        ),
      ],
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
        onRefresh: _load,
        child: ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: _fines.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final f = _fines[i];
            final amount = f.amountCents ?? 0;
            final title = (f.type == FineType.catalog)
                ? 'Katalogbeihängung'
                : (f.reason?.trim().isEmpty ?? true) ? 'Strafe' : f.reason!.trim();

            return Card(
              child: ListTile(
                leading: const Icon(Icons.gavel_rounded),
                title: Text(title),
                subtitle: Text(
                  'Betrag: ${Format.centsToEur(amount)} · Ziele: ${f.targetUserIds.length}\n'
                      'Datum: ${Format.dateTimeShort(f.createdAt)}',
                ),
                isThreeLine: true,
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push('/fines/${f.id}'),
              ),
            );
          },
        ),
      ),
    );
  }
}
