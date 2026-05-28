import '../models/dtos.dart';

class LiveEventReactionDedupe {
  static final Map<String, DateTime> _recent = <String, DateTime>{};
  static const Duration _ttl = Duration(seconds: 12);

  static bool reserve({
    required String liveEventId,
    required LiveEventReactionType type,
  }) {
    final now = DateTime.now();
    _recent.removeWhere((_, at) => now.difference(at) > _ttl);

    final key = '$liveEventId:${type.apiValue}';
    if (_recent.containsKey(key)) return false;

    _recent[key] = now;
    return true;
  }
}
