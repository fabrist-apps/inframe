import 'package:conflux/effect.dart';
import 'package:conflux/option.dart';
import 'package:conflux/src/effect/effect.dart' show EffectAccess;
import 'package:conflux/src/effect/execution.dart' show ScopeAccess;
import 'package:conflux/src/validation.dart';
import 'package:context/context.dart';

/// Scoped storage populated explicitly through [set].
///
/// Reads update LRU order. Values are borrowed references: eviction,
/// invalidation, and closure never dispose them.
final class Cache<K, A> {
  Cache._(this.capacity, this.timeToLive, this._clock, this._scope);

  /// Acquires a cache owned by the current Effect scope.
  ///
  /// Capacity must be positive and TTL non-negative. Expiry uses the captured
  /// Clock even when another runtime reads or writes the cache.
  static Effect<Cache<K, A>, Never> make<K, A>({
    required int capacity,
    required Duration timeToLive,
  }) => EffectAccess.create((execution) async {
    checkPositive(capacity, 'capacity');
    checkDuration(timeToLive, 'timeToLive');

    final cache = Cache<K, A>._(capacity, timeToLive, execution.clock, execution.scope);
    final registered = ScopeAccess.addFinalizer(
      execution.scope,
      Effect.sync((_) => cache._entries.clear()),
      execution.context,
      execution.clock,
    );
    if (!registered) throw StateError('Cannot acquire a Cache in a closed Scope.');

    return Succeeded(cache);
  });

  /// The maximum number of retained values.
  final int capacity;

  /// How long a value remains available after each [set].
  final Duration timeToLive;

  final Clock _clock;
  final Scope _scope;
  // Iteration order runs from least to most recently used.
  final _entries = <K, _CacheEntry<A>>{};

  /// Returns an unexpired value and marks it most recently used.
  ///
  /// Missing and expired entries return None; a stored null returns Some(null).
  Effect<Option<A>, Never> get(K key) => Effect.sync((_) {
    _ensureOpen();
    final entry = _entries.remove(key);
    if (entry == null || _clock.monotonic() >= entry.expiresAt) return const None();

    _entries[key] = entry;
    return Some(entry.value);
  });

  /// Inserts or replaces a value, restarting its TTL and marking it most recent.
  Effect<void, Never> set(K key, A value) => Effect.sync((_) {
    _ensureOpen();
    _removeExpiredEntries();
    _entries.remove(key);
    if (timeToLive == Duration.zero) return;

    _entries[key] = _CacheEntry(value, _clock.monotonic() + timeToLive);
    if (_entries.length > capacity) _entries.remove(_entries.keys.first);
  });

  /// Removes the value stored under [key].
  Effect<void, Never> invalidate(K key) => Effect.sync((_) {
    _ensureOpen();
    _entries.remove(key);
  });

  /// Removes all retained values.
  Effect<void, Never> invalidateAll() => Effect.sync((_) {
    _ensureOpen();
    _entries.clear();
  });

  /// Removes unexpired entries matching [predicate] in the caller's Context.
  ///
  /// Predicates are evaluated before removing matches. A thrown predicate
  /// becomes a defect without applying the selected invalidations.
  Effect<void, Never> invalidateWhere(
    bool Function(K key, A value, Context context) predicate,
  ) => Effect.sync((context) {
    _ensureOpen();
    _removeExpiredEntries();
    final keys = <K>[];
    for (final entry in _entries.entries) {
      if (predicate(entry.key, entry.value.value, context)) keys.add(entry.key);
    }
    keys.forEach(_entries.remove);
  });

  void _removeExpiredEntries() {
    final now = _clock.monotonic();
    _entries.removeWhere((_, entry) => now >= entry.expiresAt);
  }

  void _ensureOpen() {
    if (_scope.isClosed) throw StateError('Cache is closed.');
  }
}

final class _CacheEntry<A> {
  const _CacheEntry(this.value, this.expiresAt);

  final A value;
  final Duration expiresAt;
}
