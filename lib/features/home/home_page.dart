import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../api/api_client.dart';
import '../../auth/auth_store.dart';
import '../../common/format.dart';
import '../../common/widgets/app_scaffold.dart';
import '../../models/dtos.dart';
import '../../auth/roles.dart';
import '../../app/route_observer.dart';

class HomePage extends StatefulWidget {
  final ApiClient api;
  final AuthStore authStore;

  const HomePage({super.key, required this.api, required this.authStore});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with RouteAware {
  ConventPeriodDto? _activePeriod;
  UserBalanceDto? _balance;
  List<LiveEventDto> _liveEvents = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      routeObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPopNext() {
    // Wenn man zurück auf Home navigiert: automatisch neu laden
    _load();
  }

  Future<void> _load() async {
    if (_loading) return;
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

  String _formatBalanceForHome(UserBalanceDto? balance) {
    final cents = balance?.balanceCents ?? 0;
    if (cents == 0) return Format.centsToEur(0);

    final absText = Format.centsToEur(cents.abs());
    return '-$absText';
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

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => GoRouter.of(context).push('/my-fines'),
      child: Card(
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
                    'Aktueller Beihängungssaldo',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                _formatBalanceForHome(_balance),
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
      ),
    );
  }

  Widget _buildLiveEventsCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => GoRouter.of(context).push('/live-events'),
      child: Card(
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
                    'Wo geht was?',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Spacer(),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
              const SizedBox(height: 10),
              if (_liveEvents.isEmpty)
                Text(
                  'Gerade geht leider nichts :(',
                  style: Theme.of(context).textTheme.bodyMedium,
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final e in _liveEvents)
                      SizedBox(
                        width: double.infinity,
                        child: Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          color: cs.surfaceContainerHighest,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: _LiveEventPreviewTile(e: e),
                          ),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    final roles = Roles.fromAccessToken(widget.authStore.accessToken);
    final canSeeAll = Roles.canSeeAllFines(roles);
    final canOfficial = Roles.canCreateOfficialFine(roles);

    return Column(
      children: [
        if (canSeeAll) ...[
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => GoRouter.of(context).push('/fines'),
              icon: const Icon(Icons.list_alt_rounded),
              label: const Text('Alle Beihängungen anzeigen'),
            ),
          ),
          const SizedBox(height: 12),
        ],
        Row(
          children: [
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: () => GoRouter.of(context).push('/suggestions/new'),
                icon: const Icon(Icons.add_comment_rounded),
                label: const Text('Beihängung vorschlagen'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: canOfficial ? () => GoRouter.of(context).push('/fines/new') : null,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Beihängen'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _LiveEventPreviewTile extends StatelessWidget {
  final LiveEventDto e;

  const _LiveEventPreviewTile({required this.e});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(e.title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(e.place, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 4),
        Text(e.description, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
