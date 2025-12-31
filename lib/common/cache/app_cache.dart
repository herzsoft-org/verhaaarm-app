import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

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
  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  CacheEntry<T>? entry<T>(String key) {
    final e = _map[key];
    if (e == null) return null;

    final v = e.value;
    if (v is! T) return null;

    return CacheEntry<T>(v as T, e.fetchedAt);
  }

  T? get<T>(String key) => entry<T>(key)?.value;

  void set<T>(String key, T value) {
    _map[key] = CacheEntry<Object>(value as Object, DateTime.now());
  }

  Future<CacheEntry<T>?> entryOrLoadPersisted<T>(
      String key, {
        required T Function(Object json) decode,
      }) async {
    final inMem = entry<T>(key);
    if (inMem != null) return inMem;

    final prefs = _prefs;
    if (prefs == null) return null;

    final raw = prefs.getString(_pkey(key));
    if (raw == null) return null;

    final obj = jsonDecode(raw);
    if (obj is! Map) return null;

    final fetchedAtRaw = obj['fetchedAt'];
    final data = obj['data'];
    if (fetchedAtRaw is! String) return null;
    if (data == null) return null;

    final fetchedAt = DateTime.tryParse(fetchedAtRaw);
    if (fetchedAt == null) return null;

    final value = decode(data as Object);
    final e = CacheEntry<T>(value, fetchedAt);

    _map[key] = CacheEntry<Object>(e.value as Object, e.fetchedAt);
    return e;
  }

  Future<void> setPersisted<T>(
      String key,
      T value, {
        required Object Function(T value) encode,
      }) async {
    set<T>(key, value);

    final prefs = _prefs;
    if (prefs == null) return;

    final payload = <String, Object?>{
      'fetchedAt': DateTime.now().toIso8601String(),
      'data': encode(value),
    };
    await prefs.setString(_pkey(key), jsonEncode(payload));
  }

  Future<void> removePersisted(String key) async {
    remove(key);
    final prefs = _prefs;
    if (prefs == null) return;
    await prefs.remove(_pkey(key));
  }

  void remove(String key) => _map.remove(key);

  Future<void> clearPersisted({String? prefix}) async {
    clear();
    final prefs = _prefs;
    if (prefs == null) return;

    final keys = prefs.getKeys().where((k) {
      if (!k.startsWith('appcache.')) return false;
      if (prefix == null) return true;
      return k.startsWith('appcache.$prefix');
    }).toList();

    for (final k in keys) {
      await prefs.remove(k);
    }
  }

  void clear() => _map.clear();

  String _pkey(String key) => 'appcache.$key';
}
