import 'package:intl/intl.dart';

import '../models/dtos.dart';

class Format {
  static final _eur = NumberFormat.currency(locale: 'de_DE', symbol: '€');

  static String centsToEur(int cents) {
    final value = cents / 100.0;
    return _eur.format(value);
  }

  static int? eurTextToCents(String input) {
    // akzeptiert: "1,50" "1.50" "1" "0,5"
    final s = input.trim();
    if (s.isEmpty) return null;

    final normalized = s.replaceAll('€', '').replaceAll(' ', '').replaceAll('.', ',');
    final parts = normalized.split(',');
    if (parts.length > 2) return null;

    final eurosPart = parts[0].isEmpty ? '0' : parts[0];
    final euros = int.tryParse(eurosPart);
    if (euros == null) return null;

    int cents = 0;
    if (parts.length == 2) {
      final c = parts[1];
      if (c.length == 1) {
        cents = int.tryParse('${c}0') ?? -1;
      } else if (c.length == 2) {
        cents = int.tryParse(c) ?? -1;
      } else if (c.isEmpty) {
        cents = 0;
      } else {
        // mehr als 2 Stellen: cut
        cents = int.tryParse(c.substring(0, 2)) ?? -1;
      }
      if (cents < 0) return null;
    }
    return euros * 100 + cents;
  }

  // ------------------------
  // ISO parsing helpers
  // ------------------------

  /// Date-time ISO string -> local DateTime.
  /// Use this only for real timestamps like "2025-12-31T20:15:00Z".
  static DateTime parseIsoToLocal(String isoDateTime) => DateTime.parse(isoDateTime).toLocal();

  static bool _isDateOnly(String s) => RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s.trim());

  /// Parses date-only "YYYY-MM-DD" as a *local* date at 00:00 (no timezone shift).
  static DateTime parseIsoDate(String yyyymmdd) {
    final s = yyyymmdd.trim();
    final parts = s.split('-');
    if (parts.length != 3) throw FormatException('Invalid date-only value: $yyyymmdd');
    final y = int.parse(parts[0]);
    final m = int.parse(parts[1]);
    final d = int.parse(parts[2]);
    return DateTime(y, m, d);
  }

  /// ISO date-time -> local day part at 00:00.
  static DateTime dateOnlyFromIsoDateTimeLocal(String iso) {
    final dt = DateTime.parse(iso).toLocal();
    return DateTime(dt.year, dt.month, dt.day);
  }

  /// Converts either date-only or date-time to a local day (00:00).
  static DateTime dateOnlyFromIsoFlexible(String iso) {
    final s = iso.trim();
    if (_isDateOnly(s)) return parseIsoDate(s);
    return dateOnlyFromIsoDateTimeLocal(s);
  }

  // ------------------------
  // Formatting
  // ------------------------

  static String dateTimeShort(String isoDateTime) {
    final dt = DateTime.parse(isoDateTime).toLocal();
    final f = DateFormat('dd.MM.yyyy HH:mm', 'de_DE');
    return f.format(dt);
  }

  static String dateShort(String isoDateOrDateTime) {
    final dt = dateOnlyFromIsoFlexible(isoDateOrDateTime);
    final f = DateFormat('dd.MM.yyyy', 'de_DE');
    return f.format(dt);
  }

  static String timeShort(String isoDateTime) {
    final dt = DateTime.parse(isoDateTime).toLocal();
    final f = DateFormat('HH:mm', 'de_DE');
    return f.format(dt);
  }

  static String dateOnlyShort(String yyyymmdd) {
    final dt = parseIsoDate(yyyymmdd);
    final f = DateFormat('dd.MM.yyyy', 'de_DE');
    return f.format(dt);
  }

  // ------------------------
  // Period membership helpers (date-only inclusive)
  // ------------------------

  static bool isDateWithinPeriodInclusive({
    required DateTime dateLocalMidnight,
    required ConventPeriodDto period,
  }) {
    final d = DateTime(dateLocalMidnight.year, dateLocalMidnight.month, dateLocalMidnight.day);
    final start = period.startDateLocal; // safe local date
    final end = period.endDateLocal; // safe local date

    final afterOrEqStart = d.isAtSameMomentAs(start) || d.isAfter(start);
    final beforeOrEqEnd = d.isAtSameMomentAs(end) || d.isBefore(end);
    return afterOrEqStart && beforeOrEqEnd;
  }

  /// Find the ConventPeriod that contains the fineDate (inclusive bounds).
  static ConventPeriodDto? findPeriodForFineDate({
    required String fineDate, // YYYY-MM-DD
    required List<ConventPeriodDto> periods,
  }) {
    final d = parseIsoDate(fineDate);

    for (final p in periods) {
      if (isDateWithinPeriodInclusive(dateLocalMidnight: d, period: p)) return p;
    }
    return null;
  }

  /// Find the ConventPeriod that contains a timestamp (event.startsAt etc), by comparing only the local day.
  static ConventPeriodDto? findPeriodForIsoDateTime({
    required String isoDateTime,
    required List<ConventPeriodDto> periods,
  }) {
    final d = dateOnlyFromIsoDateTimeLocal(isoDateTime);

    for (final p in periods) {
      if (isDateWithinPeriodInclusive(dateLocalMidnight: d, period: p)) return p;
    }
    return null;
  }
}
