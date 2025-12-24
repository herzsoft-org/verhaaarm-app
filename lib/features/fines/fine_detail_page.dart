import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../common/format.dart';
import '../../common/widgets/app_scaffold.dart';
import '../../models/dtos.dart';

class FineDetailPage extends StatefulWidget {
  final ApiClient api;
  final String fineId;

  const FineDetailPage({super.key, required this.api, required this.fineId});

  @override
  State<FineDetailPage> createState() => _FineDetailPageState();
}

class _FineDetailPageState extends State<FineDetailPage> {
  bool _loading = true;
  FineDto? _fine;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final fine = await widget.api.getFine(widget.fineId);
      if (!mounted) return;
      setState(() => _fine = fine);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Beihängung laden fehlgeschlagen: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fine = _fine;

    return AppScaffold(
      title: 'Beihängung',
      actions: [
        IconButton(
          tooltip: 'Neu laden',
          icon: const Icon(Icons.refresh_rounded),
          onPressed: _loading ? null : _load,
        ),
      ],
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (fine == null)
          ? const Center(child: Text('Nicht gefunden'))
          : ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fine.type == FineType.catalog ? 'Katalogstrafe' : 'Custom-Strafe',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 10),
                  _kv('Betrag', Format.centsToEur(fine.amountCents ?? 0)),
                  _kv('Datum', Format.dateTimeShort(fine.createdAt)),
                  _kv('Periode', fine.periodId),
                  _kv('Creator', fine.creatorUserId),
                  if (fine.catalogItemId != null) _kv('Katalog-ID', fine.catalogItemId!),
                  if (fine.reason != null && fine.reason!.trim().isNotEmpty)
                    _kv('Grund', fine.reason!.trim()),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ziele (${fine.targetUserIds.length})',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 10),
                  ...fine.targetUserIds.map(
                        (id) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          const Icon(Icons.person_outline_rounded, size: 18),
                          const SizedBox(width: 8),
                          Expanded(child: Text(id)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Hinweis: Namen-Resolving kommt als nächstes (User-Mapping).',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 92, child: Text(k, style: const TextStyle(fontWeight: FontWeight.w600))),
          const SizedBox(width: 10),
          Expanded(child: SelectableText(v)),
        ],
      ),
    );
  }
}
