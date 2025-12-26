class CacheEntry<T> {
  final T value;
  final DateTime fetchedAt;

  CacheEntry(this.value, this.fetchedAt);

  bool isFresh(Duration ttl) => DateTime.now().difference(fetchedAt) <= ttl;
}

class AppCache {
  AppCache._();
  static final AppCache I = AppCache._();

  final Map<String, CacheEntry<Object>> _map = {};

  CacheEntry<T>? entry<T>(String key) {
    final e = _map[key];
    if (e == null) return null;

    final v = e.value;
    if (v is! T) return null;

    // Cast is now safe due to the runtime check above.
    return CacheEntry<T>(v as T, e.fetchedAt);
  }

  T? get<T>(String key) => entry<T>(key)?.value;

  void set<T>(String key, T value) {
    _map[key] = CacheEntry<Object>(value as Object, DateTime.now());
  }

  void remove(String key) => _map.remove(key);
  void clear() => _map.clear();
}
