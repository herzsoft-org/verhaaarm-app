import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:verhaaarm/common/format.dart';
import 'package:verhaaarm/models/dtos.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('de_DE');
  });

  group('Format.eurTextToCents', () {
    test('parses common German and decimal input', () {
      expect(Format.eurTextToCents('1,50'), 150);
      expect(Format.eurTextToCents('1.50'), 150);
      expect(Format.eurTextToCents('0,5'), 50);
      expect(Format.eurTextToCents('2 €'), 200);
    });

    test('returns null for empty or malformed input', () {
      expect(Format.eurTextToCents(''), isNull);
      expect(Format.eurTextToCents('abc'), isNull);
      expect(Format.eurTextToCents('1,2,3'), isNull);
    });

    test('truncates fractional cents beyond two digits', () {
      expect(Format.eurTextToCents('1,239'), 123);
    });
  });

  group('date helpers', () {
    test('parses date-only values as local midnight', () {
      final date = Format.parseIsoDate('2026-05-25');

      expect(date.year, 2026);
      expect(date.month, 5);
      expect(date.day, 25);
      expect(date.hour, 0);
      expect(date.isUtc, isFalse);
    });

    test('formats date-only values in German short format', () {
      expect(Format.dateOnlyShort('2026-05-25'), '25.05.2026');
      expect(Format.dateShort('2026-05-25'), '25.05.2026');
    });
  });

  group('period lookup', () {
    final periods = [
      ConventPeriodDto(
        id: 'ws-2025',
        semester: 'WS 2025',
        startAt: '2025-10-01',
        endAt: '2026-03-31',
        active: false,
        locked: false,
      ),
      ConventPeriodDto(
        id: 'ss-2026',
        semester: 'SS 2026',
        startAt: '2026-04-01',
        endAt: '2026-09-30',
        active: true,
        locked: false,
      ),
    ];

    test('finds periods inclusively by fine date', () {
      expect(
        Format.findPeriodForFineDate(
          fineDate: '2026-04-01',
          periods: periods,
        )?.id,
        'ss-2026',
      );
      expect(
        Format.findPeriodForFineDate(
          fineDate: '2026-09-30',
          periods: periods,
        )?.id,
        'ss-2026',
      );
    });

    test('returns null when no period contains the date', () {
      expect(
        Format.findPeriodForFineDate(fineDate: '2026-10-01', periods: periods),
        isNull,
      );
    });
  });
}
