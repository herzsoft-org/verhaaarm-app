import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../api/api_client.dart';
import '../../app/route_observer.dart';
import '../../auth/auth_store.dart';
import '../../auth/roles.dart';
import '../../common/cache/app_cache.dart';
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

class _HomePageState extends State<HomePage> with RouteAware {
  static const _ttlHomeBase = Duration(minutes: 2);
  static const _ttlHomeLive = Duration(seconds: 20);
  static const _livePollInterval = Duration(seconds: 20);

  static const _kHomeActivePeriod = 'home.activePeriod';
  static const _kHomeBalance = 'home.balance';
  static const _kHomeLiveEvents = 'home.liveEvents';
  static const _kHomeEvents = 'home.events';

  ConventPeriodDto? _activePeriod;
  UserBalanceDto? _balance;
  List<LiveEventDto> _liveEvents = const [];
  EventDto? _nextEvent;

  bool _loading = true;
  bool _refreshing = false;

  Timer? _liveTimer;
  bool _liveRefreshInFlight = false;

  @override
  void initState() {
    super.initState();
    _load();
    _startLiveTimer();
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
    _stopLiveTimer();
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPopNext() {
    _load();
    _startLiveTimer();
  }

  @override
  void didPushNext() {
    _stopLiveTimer();
  }

  Map<String, dynamic> _encodePeriod(ConventPeriodDto p) => {
    'id': p.id,
    'semester': p.semester,
    'startAt': p.startAt,
    'endAt': p.endAt,
    'active': p.active,
    'locked': p.locked,
  };

  ConventPeriodDto _decodePeriod(Object json) =>
      ConventPeriodDto.fromJson((json as Map).cast<String, dynamic>());

  Map<String, dynamic> _encodeBalance(UserBalanceDto b) => {
    'userId': b.userId,
    'balanceCents': b.balanceCents,
  };

  UserBalanceDto _decodeBalance(Object json) =>
      UserBalanceDto.fromJson((json as Map).cast<String, dynamic>());

  Map<String, dynamic> _encodeLive(LiveEventDto e) => {
    'id': e.id,
    'title': e.title,
    'place': e.place,
    'description': e.description,
    'createdAt': e.createdAt,
    'expiresAt': e.expiresAt,
    'createdByUserId': e.createdByUserId,
  };

  LiveEventDto _decodeLive(Object json) =>
      LiveEventDto.fromJson((json as Map).cast<String, dynamic>());

  Map<String, dynamic> _encodeEvent(EventDto e) => {
    'id': e.id,
    'title': e.title,
    'startsAt': e.startsAt,
    'mandatory': e.mandatory,
    'creatorUserId': e.creatorUserId,
    'ownerType': e.ownerType.name,
  };

  EventDto _decodeEvent(Object json) =>
      EventDto.fromJson((json as Map).cast<String, dynamic>());

  void _startLiveTimer() {
    _liveTimer?.cancel();
    _liveTimer = Timer.periodic(_livePollInterval, (_) async {
      if (!mounted) return;
      await _refreshLiveEventsIfNeeded();
    });
  }

  void _stopLiveTimer() {
    _liveTimer?.cancel();
    _liveTimer = null;
  }

  Future<void> _refreshLiveEventsIfNeeded() async {
    if (_liveRefreshInFlight) return;

    final cLive = await AppCache.I.entryOrLoadPersisted<List<LiveEventDto>>(
      _kHomeLiveEvents,
      decode: (json) => (json as List).map((e) => _decodeLive(e as Object)).toList(growable: false),
    );
    if (cLive != null && cLive.isFresh(_ttlHomeLive)) return;

    _liveRefreshInFlight = true;
    try {
      final live = await widget.api.listLiveEvents();
      final frozen = List<LiveEventDto>.unmodifiable(live);

      await AppCache.I.setPersisted<List<LiveEventDto>>(
        _kHomeLiveEvents,
        frozen,
        encode: (v) => v.map(_encodeLive).toList(growable: false),
      );

      if (!mounted) return;
      setState(() => _liveEvents = frozen);
    } catch (_) {
      // silent
    } finally {
      _liveRefreshInFlight = false;
    }
  }

  Future<void> _load({bool force = false}) async {
    try {
      final cPeriod = await AppCache.I.entryOrLoadPersisted<ConventPeriodDto>(
        _kHomeActivePeriod,
        decode: _decodePeriod,
      );
      final cBalance = await AppCache.I.entryOrLoadPersisted<UserBalanceDto>(
        _kHomeBalance,
        decode: _decodeBalance,
      );
      final cLive = await AppCache.I.entryOrLoadPersisted<List<LiveEventDto>>(
        _kHomeLiveEvents,
        decode: (json) =>
            (json as List).map((e) => _decodeLive(e as Object)).toList(growable: false),
      );
      final cEvents = await AppCache.I.entryOrLoadPersisted<List<EventDto>>(
        _kHomeEvents,
        decode: (json) =>
            (json as List).map((e) => _decodeEvent(e as Object)).toList(growable: false),
      );

      final hasAnyCache =
          (cPeriod != null) || (cBalance != null) || (cLive != null) || (cEvents != null);

      if (hasAnyCache && mounted) {
        final events = List<EventDto>.from(cEvents?.value ?? const <EventDto>[]);
        final next = _pickNextEvent(events);

        setState(() {
          _activePeriod = cPeriod?.value;
          _balance = cBalance?.value;
          _liveEvents = List<LiveEventDto>.unmodifiable(cLive?.value ?? const <LiveEventDto>[]);
          _nextEvent = next;
          _loading = false;
        });
      }

      final baseFresh = (cPeriod != null && cPeriod.isFresh(_ttlHomeBase)) &&
          (cBalance != null && cBalance.isFresh(_ttlHomeBase)) &&
          (cEvents != null && cEvents.isFresh(_ttlHomeBase));

      final liveFresh = (cLive != null && cLive.isFresh(_ttlHomeLive));

      if (!force && baseFresh && liveFresh) return;

      final showFullSpinner = !hasAnyCache;
      if (mounted) {
        setState(() {
          _loading = showFullSpinner;
          _refreshing = !showFullSpinner;
        });
      }

      try {
        if (!force && baseFresh && !liveFresh) {
          final live = await widget.api.listLiveEvents();
          final frozenLive = List<LiveEventDto>.unmodifiable(live);

          await AppCache.I.setPersisted<List<LiveEventDto>>(
            _kHomeLiveEvents,
            frozenLive,
            encode: (v) => v.map(_encodeLive).toList(growable: false),
          );

          if (!mounted) return;
          setState(() => _liveEvents = frozenLive);
          return;
        }

        final period = await widget.api.getActivePeriod();
        final balance = await widget.api.getMyBalance(periodId: period.id);

        final live = await widget.api.listLiveEvents();
        final events = await widget.api.listEvents();
        final next = _pickNextEvent(events);

        final frozenLive = List<LiveEventDto>.unmodifiable(live);
        final frozenEvents = List<EventDto>.unmodifiable(events);

        await AppCache.I.setPersisted<ConventPeriodDto>(
          _kHomeActivePeriod,
          period,
          encode: _encodePeriod,
        );
        await AppCache.I.setPersisted<UserBalanceDto>(
          _kHomeBalance,
          balance,
          encode: _encodeBalance,
        );
        await AppCache.I.setPersisted<List<LiveEventDto>>(
          _kHomeLiveEvents,
          frozenLive,
          encode: (v) => v.map(_encodeLive).toList(growable: false),
        );
        await AppCache.I.setPersisted<List<EventDto>>(
          _kHomeEvents,
          frozenEvents,
          encode: (v) => v.map(_encodeEvent).toList(growable: false),
        );

        if (!mounted) return;
        setState(() {
          _activePeriod = period;
          _balance = balance;
          _liveEvents = frozenLive;
          _nextEvent = next;
        });
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Laden fehlgeschlagen: $e')),
        );
      } finally {
        if (mounted) {
          setState(() {
            _loading = false;
            _refreshing = false;
          });
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _refreshing = false;
        });
      }
    }
  }

  EventDto? _pickNextEvent(List<EventDto> events) {
    final now = DateTime.now();

    final upcoming = events.where((e) {
      final dt = Format.parseIsoToLocal(e.startsAt);
      return !dt.isBefore(now);
    }).toList();

    if (upcoming.isEmpty) return null;

    upcoming.sort((a, b) => a.startsAt.compareTo(b.startsAt));
    return upcoming.first;
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
      title: 'Verhåårm',
      actions: [
        IconButton(
          tooltip: 'Neu laden',
          icon: const Icon(Icons.refresh_rounded),
          onPressed: _loading ? null : () => _load(force: true),
        ),
      ],
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
        onRefresh: () => _load(force: true),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_refreshing)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: LinearProgressIndicator(),
              ),
            _buildLiveEventsCard(context),
            const SizedBox(height: 12),
            _buildBalanceCard(context),
            const SizedBox(height: 12),
            _buildNextEventCard(context),
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
                  const Spacer(),
                  const Icon(Icons.chevron_right_rounded),
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
                period == null
                    ? 'Keine aktive Conventsperiode'
                    : 'Conventsperiode: ${Format.dateShort(period.startAt)} – ${Format.dateShort(period.endAt)}',
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

  Widget _buildNextEventCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final e = _nextEvent;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => GoRouter.of(context).push('/events'),
      child: Card(
        color: cs.surfaceContainerLow,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.event_rounded, color: cs.primary),
                  const SizedBox(width: 10),
                  Text(
                    'Nächster Termin',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Spacer(),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
              const SizedBox(height: 10),
              if (e == null)
                Text(
                  'Keine zukünftigen Termine.',
                  style: Theme.of(context).textTheme.bodyMedium,
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(e.title, style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 6),
                    Text(
                      '${Format.dateShort(e.startsAt)} · ${Format.timeShort(e.startsAt)}'
                          '${e.mandatory ? ' · Pflicht' : ''}',
                      style: Theme.of(context).textTheme.bodyMedium,
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

    final canOffice = Roles.canAccessOffice(roles);
    final canOfficial = Roles.canCreateOfficialFine(roles);

    return Column(
      children: [
        if (canOffice) ...[
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => GoRouter.of(context).push('/office'),
              icon: const Icon(Icons.badge_rounded),
              label: const Text('Amtsausführung'),
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
        Text(e.place ?? '', style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 4),
        Text(e.description ?? '', style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
