import 'dart:async';
import 'dart:collection';

import 'package:conflux/src/effect/cause.dart';
import 'package:conflux/src/effect/effect.dart';
import 'package:conflux/src/effect/execution.dart';
import 'package:conflux/src/effect/exit.dart';

/// A scoped loading cache that retains successful lookup results.
///
/// Acquire a Cache inside the Effect scope that should own its lookup work.
/// The Cache captures that scope's Context and Clock, so later callers cannot
/// change lookup dependencies by running [get] with a different Context.
final class Cache<K, A, E> {
  Cache._({
    required this.capacity,
    required this.concurrency,
    required this._lookup,
    required this._ownerExecution,
  });

  /// Acquires a Cache owned by the current Effect scope.
  ///
  /// [capacity] and [concurrency] must both be positive. Lookups for the same
  /// key share one execution, and cancelling one caller does not cancel work
  /// still awaited by other callers.
  static Effect<Cache<K, A, E>, Never> make<K, A, E>({
    required int capacity,
    required int concurrency,
    required Effect<A, E> Function(K key) lookup,
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
      lookup: lookup,
      ownerExecution: ownerExecution,
    );
    final registered = ScopeAccess.addFinalizer(
      execution.scope,
      Effect.sync(cache._close),
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

  final Effect<A, E> Function(K key) _lookup;
  final EffectExecution _ownerExecution;
  final LinkedHashMap<K, A> _values = LinkedHashMap();
  final Map<K, int> _generations = {};
  final Map<(K, int), _CacheLoad<K, A, E>> _loads = {};
  final ListQueue<_CacheLoad<K, A, E>> _pendingLoads = ListQueue();
  var _activeLoads = 0;
  var _closed = false;

  /// Returns a retained success, joins a current load, or starts the lookup.
  Effect<A, E> get(K key) => EffectAccess.create((caller) {
    _ensureOpen();
    if (_values.containsKey(key)) {
      return Future.value(Succeeded(_touch(key)));
    }

    final generation = _generations[key] ?? 0;
    final loadKey = (key, generation);
    final load = _loads[loadKey] ?? _startLoad(key, generation);
    return _awaitLoad(load, caller);
  });

  _CacheLoad<K, A, E> _startLoad(K key, int generation) {
    final loadKey = (key, generation);
    final load = _CacheLoad<K, A, E>(key, generation);
    _loads[loadKey] = load;
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
      Effect.defer(() => _lookup(load.key)),
      _ownerExecution,
    );
    unawaited(
      fiber.join().then((exit) {
        _activeLoads -= 1;
        final loadKey = (load.key, load.generation);
        if (identical(_loads[loadKey], load)) _loads.remove(loadKey);
        if (exit case Succeeded<A, E>(:final value)) {
          if (!_isClosed && (_generations[load.key] ?? 0) == load.generation) {
            _retain(load.key, value);
          }
        }
        load.complete(exit);
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

  A _touch(K key) {
    final value = _values.remove(key) as A;
    _values[key] = value;
    return value;
  }

  void _retain(K key, A value) {
    _values.remove(key);
    _values[key] = value;
    while (_values.length > capacity) {
      _values.remove(_values.keys.first);
    }
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
    for (final load in _loads.values) {
      load.complete(const Failed(Interrupted(ScopeClosed())));
    }
    _values.clear();
    _loads.clear();
    _pendingLoads.clear();
  }
}

final class _CacheLoad<K, A, E> {
  _CacheLoad(this.key, this.generation);

  final K key;
  final int generation;
  final Completer<Exit<A, E>> _completion = Completer();

  Future<Exit<A, E>> get exit => _completion.future;

  void complete(Exit<A, E> exit) {
    if (!_completion.isCompleted) _completion.complete(exit);
  }
}
