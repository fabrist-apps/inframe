import 'dart:async';
import 'dart:collection';

import 'package:conflux/option.dart';
import 'package:conflux/src/effect/cause.dart';
import 'package:conflux/src/effect/effect.dart';
import 'package:conflux/src/effect/execution.dart';
import 'package:conflux/src/effect/exit.dart';
import 'package:context/context.dart';

/// Selects how long successful Cache values remain ready.
final class CacheExpiry<K, A> {
  const CacheExpiry._(this._durationFor);

  /// Uses one [duration] for every successful value.
  static CacheExpiry<K, A> fixed<K, A>(Duration duration) {
    _requireNonNegativeExpiry(duration);
    return CacheExpiry._((_, _, _) => duration);
  }

  /// Computes each successful value's lifetime in the Cache owner's Context.
  static CacheExpiry<K, A> byValue<K, A>(
    Duration Function(K key, A value, Context context) expiry,
  ) => CacheExpiry._(expiry);

  final Duration Function(K key, A value, Context context) _durationFor;
}

/// A scoped loading cache that retains successful lookup results.
///
/// Acquire a Cache inside the Effect scope that should own its lookup work.
/// The Cache captures that scope's Context and Clock, so later callers cannot
/// change lookup dependencies or expiry by running operations elsewhere.
/// Request-dependent lookups need a request-scoped Cache or keys that include
/// the dependency context that distinguishes their results.
///
/// Only successful values are retained. Values are borrowed references:
/// eviction, invalidation, and scope closure never dispose them. Cache state
/// and lookup coordination stay within the isolate where it was acquired.
final class Cache<K, A, E> {
  Cache._({
    required this.capacity,
    required this.concurrency,
    required this._expiry,
    required this._lookup,
    required this._ownerExecution,
  });

  /// Acquires a Cache owned by the current Effect scope.
  ///
  /// [capacity] and [concurrency] must both be positive. Lookups for the same
  /// key share one execution, and cancelling one caller does not cancel work
  /// still awaited by other callers. Expiry durations must be non-negative.
  /// [lookup] receives this Cache's captured owner Context.
  /// A thrown value-dependent expiry callback or negative returned duration is
  /// reported as a defect to the lookup or set operation that evaluates it.
  static Effect<Cache<K, A, E>, Never> make<K, A, E>({
    required int capacity,
    required int concurrency,
    required CacheExpiry<K, A> expiry,
    required Effect<A, E> Function(K key, Context context) lookup,
  }) => EffectAccess.create((execution) async {
    if (capacity <= 0) {
      throw ArgumentError.value(capacity, 'capacity', 'Must be positive.');
    }
    if (concurrency <= 0) {
      throw ArgumentError.value(concurrency, 'concurrency', 'Must be positive.');
    }

    final ownerExecution = EffectExecution(
      context: execution.context,
      scope: execution.scope,
      clock: execution.clock,
      cancellation: execution.cancellation,
    );
    final cache = Cache<K, A, E>._(
      capacity: capacity,
      concurrency: concurrency,
      expiry: expiry,
      lookup: lookup,
      ownerExecution: ownerExecution,
    );
    final registered = ScopeAccess.addFinalizer(
      execution.scope,
      Effect.sync((_) => cache._close()),
      execution.context,
      execution.clock,
    );
    if (!registered) {
      cache._close();
      throw StateError('Cannot acquire a Cache in a closed Scope.');
    }
    return Succeeded(cache);
  });

  /// The maximum number of successful values retained by this Cache.
  final int capacity;

  /// The maximum number of lookups this Cache may run concurrently.
  final int concurrency;

  final CacheExpiry<K, A> _expiry;
  final Effect<A, E> Function(K key, Context context) _lookup;
  final EffectExecution _ownerExecution;

  // Ready entries are ordered from least to most recently used. Only the load
  // registered in _currentLoads may retain a result. Invalidated loads remain
  // in _loads until completion so their existing waiters still receive it.
  final LinkedHashMap<K, _CacheEntry<A>> _entries = LinkedHashMap();
  final Map<K, _CacheLoad<K, A, E>> _currentLoads = {};
  final Set<_CacheLoad<K, A, E>> _loads = {};
  final ListQueue<_CacheLoad<K, A, E>> _pendingLoads = ListQueue();
  var _activeLoads = 0;
  var _closed = false;

  /// Returns a retained success, joins a current load, or starts the lookup.
  Effect<A, E> get(K key) => EffectAccess.create((caller) {
    _ensureOpen();
    final ready = _readyEntry(key, touch: true);
    if (ready != null) return Future.value(Succeeded(ready.value));

    return _awaitLoad(_currentLoad(key), caller);
  });

  /// Loads [key] again while leaving an unexpired value readable.
  ///
  /// Concurrent refreshes and a current-generation miss share one load. A
  /// failed refresh leaves the previous unexpired value and deadline intact.
  Effect<A, E> refresh(K key) => EffectAccess.create((caller) {
    _ensureOpen();
    return _awaitLoad(_currentLoad(key), caller);
  });

  /// Inspects a ready value without starting or awaiting a lookup.
  Effect<Option<A>, Never> getOption(K key) => EffectAccess.create((_) async {
    _ensureOpen();
    final entry = _readyEntry(key, touch: true);
    return Succeeded(entry == null ? const None() : Some(entry.value));
  });

  /// Reports ready unexpired membership without starting a lookup.
  Effect<bool, Never> containsKey(K key) => EffectAccess.create((_) async {
    _ensureOpen();
    return Succeeded(_readyEntry(key, touch: false) != null);
  });

  /// Replaces [key] with a successful [value] under a new generation.
  Effect<void, Never> set(K key, A value) => EffectAccess.create((_) async {
    _ensureOpen();
    _invalidate(key);
    _retain(key, value);
    return const Succeeded(null);
  });

  /// Removes [key] and prevents older loads from repopulating it.
  Effect<void, Never> invalidate(K key) => EffectAccess.create((_) async {
    _ensureOpen();
    _invalidate(key);
    return const Succeeded(null);
  });

  /// Removes every ready value and invalidates every known pending generation.
  Effect<void, Never> invalidateAll() => EffectAccess.create((_) async {
    _ensureOpen();
    _entries.clear();
    _currentLoads.clear();
    return const Succeeded(null);
  });

  /// Invalidates ready entries matching [predicate] in the caller's Context,
  /// without inspecting loads.
  Effect<void, Never> invalidateWhere(
    bool Function(K key, A value, Context context) predicate,
  ) => EffectAccess.create((caller) async {
    _ensureOpen();
    _removeExpiredEntries();
    _entries.entries
        .where(
          (entry) => predicate(
            entry.key,
            entry.value.value,
            caller.context,
          ),
        )
        .map((entry) => entry.key)
        .toList()
        .forEach(_invalidate);
    return const Succeeded(null);
  });

  /// The number of ready unexpired entries.
  int get size {
    _ensureOpen();
    _removeExpiredEntries();
    return _entries.length;
  }

  /// A snapshot of ready unexpired keys in LRU order.
  List<K> get keys {
    _ensureOpen();
    _removeExpiredEntries();
    return List.unmodifiable(_entries.keys);
  }

  /// A snapshot of ready unexpired values in LRU order.
  List<A> get values {
    _ensureOpen();
    _removeExpiredEntries();
    return List.unmodifiable(_entries.values.map((entry) => entry.value));
  }

  /// A snapshot of ready unexpired key/value pairs in LRU order.
  List<MapEntry<K, A>> get entries {
    _ensureOpen();
    _removeExpiredEntries();
    return List.unmodifiable(
      _entries.entries.map((entry) => MapEntry(entry.key, entry.value.value)),
    );
  }

  _CacheLoad<K, A, E> _currentLoad(K key) {
    return _currentLoads[key] ?? _startLoad(key);
  }

  _CacheLoad<K, A, E> _startLoad(K key) {
    final load = _CacheLoad<K, A, E>(key);
    _currentLoads[key] = load;
    _loads.add(load);
    if (_activeLoads < concurrency) {
      _runLoad(load);
    } else {
      _pendingLoads.addLast(load);
    }
    return load;
  }

  void _runLoad(_CacheLoad<K, A, E> load) {
    _activeLoads += 1;
    final fiber = ScopeAccess.fork(
      _ownerExecution.scope,
      Effect.defer((context) => _lookup(load.key, context)),
      _ownerExecution,
    );
    unawaited(
      fiber.join().then((exit) {
        _activeLoads -= 1;
        _loads.remove(load);
        final isCurrent = identical(_currentLoads[load.key], load);
        if (isCurrent) _currentLoads.remove(load.key);

        var delivered = exit;
        try {
          if (exit case Succeeded<A, E>(:final value)) {
            if (!_isClosed && isCurrent) {
              _retain(load.key, value);
            }
          }
        } on Object catch (error, stackTrace) {
          delivered = Failed(Defect(error, stackTrace));
        }
        load.complete(delivered);
        _drainPendingLoads();
      }),
    );
  }

  Future<Exit<A, E>> _awaitLoad(
    _CacheLoad<K, A, E> load,
    EffectExecution caller,
  ) {
    if (caller.cancellation.isCancelled) {
      return Future.value(
        Failed(Interrupted(caller.cancellation.reason)),
      );
    }

    final completion = Completer<Exit<A, E>>();
    var settled = false;
    late final void Function() stopListening;

    void complete(Exit<A, E> exit) {
      if (settled) return;
      settled = true;
      stopListening();
      completion.complete(exit);
    }

    stopListening = caller.cancellation.listen(
      (reason) => complete(Failed(Interrupted(reason))),
    );
    unawaited(load.exit.then(complete));
    return completion.future;
  }

  void _retain(K key, A value) {
    final duration = _expiry._durationFor(
      key,
      value,
      _ownerExecution.context,
    );
    _requireNonNegativeExpiry(duration);
    _removeExpiredEntries();
    final entry = _CacheEntry(
      value,
      _ownerExecution.clock.monotonic() + duration,
    );
    _entries.remove(key);
    _entries[key] = entry;
    while (_entries.length > capacity) {
      _entries.remove(_entries.keys.first);
    }
  }

  _CacheEntry<A>? _readyEntry(K key, {required bool touch}) {
    final entry = _entries[key];
    if (entry == null) return null;
    if (_ownerExecution.clock.monotonic() >= entry.expiresAt) {
      _entries.remove(key);
      return null;
    }
    if (touch) {
      _entries.remove(key);
      _entries[key] = entry;
    }
    return entry;
  }

  void _removeExpiredEntries() {
    final now = _ownerExecution.clock.monotonic();
    _entries.removeWhere((_, entry) => now >= entry.expiresAt);
  }

  void _invalidate(K key) {
    _currentLoads.remove(key);
    _entries.remove(key);
  }

  void _drainPendingLoads() {
    if (_isClosed) {
      while (_pendingLoads.isNotEmpty) {
        _pendingLoads.removeFirst().complete(
          const Failed(Interrupted(ScopeClosed())),
        );
      }
      return;
    }
    while (_pendingLoads.isNotEmpty && _activeLoads < concurrency) {
      _runLoad(_pendingLoads.removeFirst());
    }
  }

  bool get _isClosed => _closed || _ownerExecution.scope.isClosed;

  void _ensureOpen() {
    if (_isClosed) throw StateError('Cache is closed.');
  }

  void _close() {
    if (_closed) return;
    _closed = true;
    for (final load in _loads) {
      load.complete(const Failed(Interrupted(ScopeClosed())));
    }
    _entries.clear();
    _currentLoads.clear();
    _loads.clear();
    _pendingLoads.clear();
  }
}

final class _CacheEntry<A> {
  const _CacheEntry(this.value, this.expiresAt);

  final A value;
  final Duration expiresAt;
}

final class _CacheLoad<K, A, E> {
  _CacheLoad(this.key);

  final K key;
  final Completer<Exit<A, E>> _completion = Completer();

  Future<Exit<A, E>> get exit => _completion.future;

  void complete(Exit<A, E> exit) {
    if (!_completion.isCompleted) _completion.complete(exit);
  }
}

void _requireNonNegativeExpiry(Duration duration) {
  if (duration.isNegative) {
    throw ArgumentError.value(duration, 'duration', 'Must not be negative.');
  }
}
