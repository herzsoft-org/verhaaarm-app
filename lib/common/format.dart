import 'package:intl/intl.dart';

class Format {
  static final _eur = NumberFormat.currency(locale: 'de_DE', symbol: '€');

  static String centsToEur(int cents) {
    final value = cents / 100.0;
    return _eur.format(value);
  }

  static String dateTimeShort(String iso) {
    final dt = DateTime.parse(iso).toLocal();
    final f = DateFormat('dd.MM.yyyy HH:mm', 'de_DE');
    return f.format(dt);
  }
}
