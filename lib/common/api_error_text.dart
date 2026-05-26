import 'package:dio/dio.dart';

class StructuredApiError {
  final String error;
  final String? code;
  final String? role;
  final String? suggestedAction;
  final Map<String, dynamic> raw;

  const StructuredApiError({
    required this.error,
    required this.raw,
    this.code,
    this.role,
    this.suggestedAction,
  });

  factory StructuredApiError.fromJson(Map<String, dynamic> json) {
    return StructuredApiError(
      error: (json['error'] ?? '').toString(),
      code: json['code']?.toString(),
      role: json['role']?.toString(),
      suggestedAction: json['suggestedAction']?.toString(),
      raw: json,
    );
  }

  static StructuredApiError? tryParse(Object? data) {
    if (data is Map) {
      final json = data.cast<String, dynamic>();
      final message = (json['error'] ?? '').toString().trim();
      final code = (json['code'] ?? '').toString().trim();
      if (message.isNotEmpty || code.isNotEmpty) {
        return StructuredApiError.fromJson(json);
      }
    }
    return null;
  }
}

StructuredApiError? structuredApiError(Object error) {
  if (error is DioException) {
    return StructuredApiError.tryParse(error.response?.data);
  }
  return null;
}

String userFriendlyApiError(
  Object error, {
  String fallback = 'Ein Fehler ist aufgetreten.',
}) {
  if (error is DioException) {
    final structured = StructuredApiError.tryParse(error.response?.data);
    final structuredMessage = structured?.error.trim() ?? '';
    if (structuredMessage.isNotEmpty) return structuredMessage;

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
