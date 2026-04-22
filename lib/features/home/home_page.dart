import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../api/api_client.dart';
import '../../app/route_observer.dart';
import '../../auth/auth_store.dart';
import '../../auth/roles.dart';
import '../../common/cache/app_cache.dart';
import '../../common/format.dart';
import '../../common/widgets/app_scaffold.dart';
import '../../common/widgets/quote_of_the_day_card.dart';
import '../../models/dtos.dart';

// OTA update (android)
import '../../update/ota_update.dart';
import '../../update/ota_update_banner.dart';

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
  static const _kHomeQuote = 'home.quote';
  static const _kHomeTasksUnsolved = 'home.tasks.unsolved';

  static const _quoteUrl = 'https://verhaarmapi.herz.moe/public/quotes';

  ConventPeriodDto? _activePeriod;
  UserBalanceDto? _balance;
  List<LiveEventDto> _liveEvents = const [];
  EventDto? _nextEvent;
  QuoteDto? _quote;

  int _unsolvedTasks = 0;

  bool _loading = true;
  bool _refreshing = false;

  Timer? _liveTimer;
  bool _liveRefreshInFlight = false;

  // OTA
  late final OtaUpdateController _ota;

  bool get _isAndroidApp =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  // Dedicated lightweight client for quotes
  late final Dio _quoteDio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 6),
      receiveTimeout: const Duration(seconds: 6),
      sendTimeout: const Duration(seconds: 6),
      responseType: ResponseType.plain,
      headers: const {'Accept': 'application/json'},
    ),
  );

  bool _isNoActivePeriodError(Object e) {
    if (e is DioException) {
      final code = e.response?.statusCode;
      return code == 404;
    }
    return false;
  }

  void _checkOtaIfAndroid() {
    if (_isAndroidApp) _ota.checkNow();
  }

  @override
  void initState() {
    super.initState();

    // IMPORTANT: init OTA controller BEFORE calling _load()
    _ota = OtaUpdateController();

    _load();
    _loadQuote();
    _startLiveTimer();

    if (_isAndroidApp) {
      Future.delayed(const Duration(seconds: 2), () {
        if (!mounted) return;
        _ota.checkNow();
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) routeObserver.subscribe(this, route);
  }

  @override
  void dispose() {
    _ota.stop();
    _stopLiveTimer();
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPopNext() {
    _load();
    _loadQuote();
    _startLiveTimer();
    if (_isAndroidApp) _ota.checkNow();
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
    'id': b.userId, // legacy callers
    'balanceCents': b.balanceCents,
    'balanceFormatted': b.balanceFormatted,
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
    'eventKind': e.eventKind == EventKind.secondary ? 'SECONDARY' : 'MAIN',
    'creatorUserId': e.creatorUserId,
    'ownerType': e.ownerType.name,
    'createdAt': e.createdAt,
  };

  EventDto _decodeEvent(Object json) =>
      EventDto.fromJson((json as Map).cast<String, dynamic>());

  QuoteDto _decodeQuote(Object json) =>
      QuoteDto.fromJson((json as Map).cast<String, dynamic>());

  int _decodeInt(Object json) {
    if (json is int) return json;
    if (json is num) return json.toInt();
    return int.tryParse(json.toString()) ?? 0;
  }

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
      decode: (json) => (json as List)
          .map((e) => _decodeLive(e as Object))
          .toList(growable: false),
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

  Future<void> _loadQuote({bool force = false}) async {
    final cached = await AppCache.I.entryOrLoadPersisted<QuoteDto>(
      _kHomeQuote,
      decode: _decodeQuote,
    );

    if (!force && cached != null && cached.isFresh(_ttlHomeBase)) {
      if (mounted) setState(() => _quote = cached.value);
      return;
    }

    try {
      final resp = await _quoteDio.get(_quoteUrl);
      final text = (resp.data ?? '').toString();

      final decoded = jsonDecode(text);
      final List<dynamic> rawList = switch (decoded) {
        List<dynamic>() => decoded,
        Map<String, dynamic>() =>
        (decoded['quotes'] as List<dynamic>? ?? const <dynamic>[]),
        _ => const <dynamic>[],
      };

      final quotes = rawList
          .whereType<Map>()
          .map((m) => QuoteDto.fromJson(m.cast<String, dynamic>()))
          .where((q) => q.text.trim().isNotEmpty)
          .toList(growable: false);

      if (quotes.isEmpty) return;

      final picked = quotes[Random().nextInt(quotes.length)];

      await AppCache.I.setPersisted<QuoteDto>(
        _kHomeQuote,
        picked,
        encode: (q) => q.toJson(),
      );

      if (mounted) setState(() => _quote = picked);
    } catch (_) {
      // silent by design
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
        decode: (json) => (json as List)
            .map((e) => _decodeLive(e as Object))
            .toList(growable: false),
      );
      final cEvents = await AppCache.I.entryOrLoadPersisted<List<EventDto>>(
        _kHomeEvents,
        decode: (json) => (json as List)
            .map((e) => _decodeEvent(e as Object))
            .toList(growable: false),
      );
      final cTasks = await AppCache.I.entryOrLoadPersisted<int>(
        _kHomeTasksUnsolved,
        decode: _decodeInt,
      );

      final hasAnyCache = (cPeriod != null) ||
          (cBalance != null) ||
          (cLive != null) ||
          (cEvents != null) ||
          (cTasks != null);

      if (hasAnyCache && mounted) {
        final events = List<EventDto>.from(cEvents?.value ?? const <EventDto>[]);
        final next = _pickNextEvent(events, period: cPeriod?.value);

        setState(() {
          _activePeriod = cPeriod?.value;
          _balance = cBalance?.value;
          _liveEvents =
          List<LiveEventDto>.unmodifiable(cLive?.value ?? const <LiveEventDto>[]);
          _nextEvent = next;
          _unsolvedTasks = cTasks?.value ?? 0;
          _loading = false;
        });
      }

      final baseFresh = (cPeriod != null && cPeriod.isFresh(_ttlHomeBase)) &&
          (cBalance != null && cBalance.isFresh(_ttlHomeBase)) &&
          (cEvents != null && cEvents.isFresh(_ttlHomeBase)) &&
          (cTasks != null && cTasks.isFresh(_ttlHomeBase));

      final liveFresh = (cLive != null && cLive.isFresh(_ttlHomeLive));

      if (!force && baseFresh && liveFresh) return;

      _checkOtaIfAndroid();
      unawaited(_loadQuote(force: force));

      final showFullSpinner = !hasAnyCache;
      if (mounted) {
        setState(() {
          _loading = showFullSpinner;
          _refreshing = !showFullSpinner;
        });
      }

      try {
        // If only live events are stale, refresh just those.
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

        // --- Active period (can be 404 if none) ---
        ConventPeriodDto? period;
        try {
          period = await widget.api.getActivePeriod();
        } catch (e) {
          // If no active period exists, that's OK.
          if (_isNoActivePeriodError(e)) {
            period = null;
          } else {
            period = null;
          }
        }

        // --- Balance (can be 404 if no active period today) ---
        UserBalanceDto? balance;
        try {
          // Backend resolves by today if periodId omitted; keep it omitted to match semantics.
          balance = await widget.api.getMyBalance();
        } catch (e) {
          if (_isNoActivePeriodError(e)) {
            balance = null;
          } else {
            rethrow;
          }
        }

        final live = await widget.api.listLiveEvents();
        final events = await widget.api.listEvents();
        final next = _pickNextEvent(events, period: period);

        final tasks = await widget.api.listMyTasks();
        final unsolved = tasks.where((t) => !t.solved).length;

        final frozenLive = List<LiveEventDto>.unmodifiable(live);
        final frozenEvents = List<EventDto>.unmodifiable(events);

        if (period != null) {
          await AppCache.I.setPersisted<ConventPeriodDto>(
            _kHomeActivePeriod,
            period,
            encode: _encodePeriod,
          );
        } else {
          await AppCache.I.removePersisted(_kHomeActivePeriod);
        }

        if (balance != null) {
          await AppCache.I.setPersisted<UserBalanceDto>(
            _kHomeBalance,
            balance,
            encode: _encodeBalance,
          );
        } else {
          await AppCache.I.removePersisted(_kHomeBalance);
        }

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
        await AppCache.I.setPersisted<int>(
          _kHomeTasksUnsolved,
          unsolved,
          encode: (v) => v,
        );

        if (!mounted) return;
        setState(() {
          _activePeriod = period;
          _balance = balance;
          _liveEvents = frozenLive;
          _nextEvent = next;
          _unsolvedTasks = unsolved;
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

  int _eventPriority(EventDto e) {
    if (e.mandatory) {
      return switch (e.eventKind) {
        EventKind.main => 0,
        EventKind.secondary => 1,
      };
    }

    return switch (e.eventKind) {
      EventKind.main => 2,
      EventKind.secondary => 3,
    };
  }

  IconData _iconForEvent(EventDto e) {
    if (!e.mandatory) {
      return Icons.sports_bar_rounded;
    }

    return switch (e.eventKind) {
      EventKind.main => Icons.event_rounded,
      EventKind.secondary => Icons.event_note_rounded,
    };
  }

  Color _colorForEvent(BuildContext context, EventDto e) {
    final scheme = Theme.of(context).colorScheme;

    if (!e.mandatory) {
      return scheme.secondary;
    }

    return switch (e.eventKind) {
      EventKind.main => scheme.primary,
      EventKind.secondary => scheme.tertiary,
    };
  }

  Color _cardColorForEvent(BuildContext context, EventDto e) {
    final scheme = Theme.of(context).colorScheme;

    if (!e.mandatory) {
      return scheme.secondaryContainer.withValues(alpha: 0.45);
    }

    return switch (e.eventKind) {
      EventKind.main => scheme.surfaceContainerHighest,
      EventKind.secondary => scheme.tertiaryContainer.withValues(alpha: 0.45),
    };
  }

  EventDto? _pickNextEvent(List<EventDto> events, {ConventPeriodDto? period}) {
    final now = DateTime.now();

    bool inActivePeriod(EventDto e) {
      if (period == null) return true;
      final d = Format.dateOnlyFromIsoDateTimeLocal(e.startsAt);
      return Format.isDateWithinPeriodInclusive(
        dateLocalMidnight: d,
        period: period,
      );
    }

    final upcoming = events.where((e) {
      final dt = Format.parseIsoToLocal(e.startsAt);
      return !dt.isBefore(now) && inActivePeriod(e);
    }).toList();

    int compareEvents(EventDto a, EventDto b) {
      final timeCmp = a.startsAt.compareTo(b.startsAt);
      if (timeCmp != 0) return timeCmp;

      final priorityCmp = _eventPriority(a).compareTo(_eventPriority(b));
      if (priorityCmp != 0) return priorityCmp;

      return 0;
    }

    if (upcoming.isEmpty) {
      if (period != null) {
        final anyUpcoming = events.where((e) {
          final dt = Format.parseIsoToLocal(e.startsAt);
          return !dt.isBefore(now);
        }).toList();

        if (anyUpcoming.isEmpty) return null;

        anyUpcoming.sort(compareEvents);
        return anyUpcoming.first;
      }
      return null;
    }

    upcoming.sort(compareEvents);
    return upcoming.first;
  }

  String _formatBalanceForHome(UserBalanceDto? balance) {
    // New backend already provides a formatted string; use it directly.
    final s = (balance?.balanceFormatted ?? '').trim();
    if (s.isNotEmpty) return s;

    final cents = balance?.balanceCents ?? 0;
    return Format.centsToEur(cents);
  }

  String _formatPayableBalanceForHome(UserBalanceDto? balance) {
    final s = _formatBalanceForHome(balance).trim();
    if (s.isEmpty) return s;

    final cents = balance?.balanceCents ?? 0;
    if (cents == 0) return s;

    return s.startsWith('-') ? s : '-$s';
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Verhåårm',
      titleWidget: Builder(
        builder: (context) {
          final titleStyle = Theme.of(context).appBarTheme.titleTextStyle ??
              Theme.of(context).textTheme.titleLarge;

          final titleColor =
              titleStyle?.color ?? Theme.of(context).colorScheme.onSurface;

          final titleHeight = titleStyle?.fontSize ?? 22;

          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SvgPicture.asset(
                'assets/zirkel.svg',
                height: titleHeight,
                colorFilter: ColorFilter.mode(titleColor, BlendMode.srcIn),
              ),
              const SizedBox(width: 8),
              Text(
                'Verhåårm',
                style: titleStyle,
              ),
            ],
          );
        },
      ),
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
            if (_isAndroidApp) ...[
              OtaUpdateBanner(controller: _ota),
              const SizedBox(height: 12),
            ],
            _buildLiveEventsCard(context),
            const SizedBox(height: 12),
            _buildBalanceCard(context),
            const SizedBox(height: 12),
            _buildNextEventCard(context),
            const SizedBox(height: 12),
            _buildTasksCard(context),
            const SizedBox(height: 12),
            _buildQuickActions(context),
            if (_quote != null) ...[
              const SizedBox(height: 12),
              QuoteOfTheDayCard(quote: _quote!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTasksCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final n = _unsolvedTasks;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => GoRouter.of(context).push('/tasks'),
      child: Card(
        color: cs.surfaceContainerLow,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.assignment_rounded, color: cs.primary),
              const SizedBox(width: 10),
              Text(
                'Arbeitsaufträge',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              if (n > 0)
                Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$n',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: cs.onPrimaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBalanceCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final period = _activePeriod;
    final isZeroBalance = (_balance?.balanceCents ?? 0) == 0;

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
              Row(
                children: [
                  if (!isZeroBalance) ...[
                    Icon(
                      Icons.sentiment_dissatisfied_rounded,
                      color: cs.onSurfaceVariant,
                      size: 32,
                    ),
                    const SizedBox(width: 10),
                  ],
                  Text(
                    _formatPayableBalanceForHome(_balance),
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                period == null
                    ? 'Keine aktive Conventsperiode'
                    : 'Conventsperiode: ${Format.dateOnlyShort(period.startAt)} – ${Format.dateOnlyShort(period.endAt)}',
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

    final hasLiveEvents = _liveEvents.isNotEmpty;
    final liveCardColor = hasLiveEvents
        ? cs.tertiaryContainer.withValues(alpha: 0.45)
        : cs.surfaceContainerLow;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => GoRouter.of(context).push('/live-events'),
      child: Card(
        color: liveCardColor,
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

    final cardColor = e == null ? cs.surfaceContainerLow : _cardColorForEvent(context, e);
    final iconColor = e == null ? cs.primary : _colorForEvent(context, e);
    final iconData = e == null ? Icons.event_rounded : _iconForEvent(e);

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => GoRouter.of(context).push('/events'),
      child: Card(
        color: cardColor,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(iconData, color: iconColor),
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
                    Text(
                      e.title,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${Format.dateShort(e.startsAt)} · ${Format.timeShort(e.startsAt)}${e.mandatory ? ' · Pflicht' : ''}',
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

        // CHANGED: make both buttons same height by letting the Row take the max height
        // and stretching the other child to match.
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: () =>
                      GoRouter.of(context).push('/suggestions/new'),
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.add_comment_rounded),
                      SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'Beihängung vorschlagen',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: canOfficial
                      ? () => GoRouter.of(context).push('/fines/new')
                      : null,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Beihängen'),
                ),
              ),
            ],
          ),
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
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.campaign_rounded, size: 18, color: cs.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                e.title,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if ((e.place ?? '').trim().isNotEmpty)
          Row(
            children: [
              Icon(Icons.place_rounded, size: 18, color: cs.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  e.place ?? '',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        if ((e.description ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            e.description ?? '',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}