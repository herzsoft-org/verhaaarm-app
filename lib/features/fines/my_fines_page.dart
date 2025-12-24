import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../api/api_client.dart';
import '../../common/format.dart';
import '../../common/widgets/app_scaffold.dart';
import '../../models/dtos.dart';

class MyFinesPage extends StatefulWidget {
  final ApiClient api;

  const MyFinesPage({super.key, required this.api});

  @override
  State<MyFinesPage> createState() => _MyFinesPageState();
}

class _MyFinesPageState extends State<MyFinesPage> {
  bool _loading = true;

  String? _myUserId;
  ConventPeriodDto? _activePeriod;

  List<FineDto> _mine = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final period = await widget.api.getActivePeriod();
      final bal = await widget.api.getMyBalance(periodId: period.id);
      final fines = await widget.api.listFines();

      final mine = fines.where((f) => f.targetUserIds.contains(bal.userId)).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

      if (!mounted) return;
      setState(() {
        _activePeriod = period;
        _myUserId = bal.userId;
        _mine = mine;
      });
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
      title: 'Meine Beihängungen',
      actions: [
        IconButton(
          tooltip: 'Neu laden',
          icon: const Icon(Icons.refresh_rounded),
          onPressed: _loading ? null : _load,
        ),
      ],
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (_activePeriod != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
              child: Text(
                'Periode: ${_activePeriod!.semester}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          if (_myUserId == null)
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text('Fehler: userId unbekannt.'),
            ),
          if (_mine.isEmpty)
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text('Keine Beihängungen gefunden.'),
            ),
          ..._mine.map((f) {
            final amount = f.amountCents ?? 0;
            final title = (f.type == FineType.catalog)
                ? 'Katalogbeihängung'
                : (f.reason?.trim().isEmpty ?? true) ? 'Beihängung' : f.reason!.trim();

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Card(
                child: ListTile(
                  leading: const Icon(Icons.gavel_rounded),
                  title: Text(title),
                  subtitle: Text(
                    'Betrag: ${Format.centsToEur(amount)}\n'
                        'Datum: ${Format.dateTimeShort(f.createdAt)}',
                  ),
                  isThreeLine: true,
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push('/fines/${f.id}'),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
