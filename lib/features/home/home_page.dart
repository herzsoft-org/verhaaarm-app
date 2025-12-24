import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../auth/auth_store.dart';
import '../../common/format.dart';
import '../../common/widgets/app_scaffold.dart';
import '../../models/dtos.dart';

class HomePage extends StatefulWidget {
  final ApiClient api;
  final AuthStore authStore;

  const HomePage({super.key, required this.api, required this.authStore});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  ConventPeriodDto? _activePeriod;
  UserBalanceDto? _balance;
  List<LiveEventDto> _liveEvents = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final period = await widget.api.getActivePeriod();
      final balance = await widget.api.getMyBalance(periodId: period.id);
      final live = await widget.api.listLiveEvents();

      if (!mounted) return;
      setState(() {
        _activePeriod = period;
        _balance = balance;
        _liveEvents = live;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Laden fehlgeschlagen: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Übersicht',
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
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildBalanceCard(context),
            const SizedBox(height: 12),
            _buildLiveEventsCard(context),
            const SizedBox(height: 12),
            _buildQuickActions(context),
          ],
        ),
      ),
    );
  }

  Widget _buildBalanceCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final period = _activePeriod;
    final balance = _balance;

    return Card(
      color: cs.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.account_balance_wallet_rounded, color: cs.primary),
                const SizedBox(width: 10),
                Text(
                  'Aktueller Saldo',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              balance?.balanceFormatted ?? Format.centsToEur(0),
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              period == null ? 'Keine aktive Conventsperiode' : 'Periode: ${period.semester}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLiveEventsCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      color: cs.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.groups_2_rounded, color: cs.primary),
                const SizedBox(width: 10),
                Text(
                  'Gerade zusammen',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (_liveEvents.isEmpty)
              Text(
                'Keine Live-Events gerade.',
                style: Theme.of(context).textTheme.bodyMedium,
              )
            else
              ..._liveEvents.map(
                    (e) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(e.title),
                    subtitle: Text('${e.place}\n${e.description}'),
                    isThreeLine: true,
                    trailing: Text(
                      'bis\n${Format.dateTimeShort(e.expiresAt)}',
                      textAlign: TextAlign.right,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    // Rollen-Logik kommt später. Fürs Erste: Button nur als Platzhalter.
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Noch nicht implementiert: Strafen / Vorschläge')),
              );
            },
            icon: const Icon(Icons.add_rounded),
            label: const Text('Strafe hinzufügen / vorschlagen'),
          ),
        ),
      ],
    );
  }
}
