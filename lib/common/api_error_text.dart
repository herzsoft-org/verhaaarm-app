import 'package:dio/dio.dart';

String userFriendlyApiError(
    Object error, {
      String fallback = 'Ein Fehler ist aufgetreten.',
    }) {
  if (error is DioException) {
    final status = error.response?.statusCode;

    switch (status) {
      case 400:
        return 'Ungültige Anfrage.';
      case 401:
        return 'Nicht angemeldet oder Zugangsdaten falsch.';
      case 403:
        return 'Keine Berechtigung.';
      case 404:
        return 'Nicht gefunden.';
      case 409:
        return 'Konflikt mit vorhandenen Daten.';
      case 413:
        return 'Datei ist zu groß.';
      case 500:
        return 'Interner Serverfehler.';
      default:
        return fallback;
    }
  }

  return fallback;
}