import 'package:intl/intl.dart';

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
        // mehr als 2 Stellen: cut (einfach halten)
        cents = int.tryParse(c.substring(0, 2)) ?? -1;
      }
      if (cents < 0) return null;
    }
    return euros * 100 + cents;
  }

  static String dateTimeShort(String iso) {
    final dt = DateTime.parse(iso).toLocal();
    final f = DateFormat('dd.MM.yyyy HH:mm', 'de_DE');
    return f.format(dt);
  }
}
