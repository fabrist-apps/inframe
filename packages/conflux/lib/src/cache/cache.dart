import 'dart:async';

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
  final Map<K, A> _values = {};
  final Map<K, int> _generations = {};
  final Map<(K, int), _CacheLoad<A, E>> _loads = {};
  var _closed = false;

  /// Returns a retained success, joins a current load, or starts the lookup.
  Effect<A, E> get(K key) => EffectAccess.create((caller) {
    _ensureOpen();
    if (_values.containsKey(key)) {
      return Future.value(Succeeded(_values[key] as A));
    }

    final generation = _generations[key] ?? 0;
    final loadKey = (key, generation);
    final load = _loads[loadKey] ?? _startLoad(key, generation);
    return _awaitLoad(load, caller);
  });

  _CacheLoad<A, E> _startLoad(K key, int generation) {
    final loadKey = (key, generation);
    final load = _CacheLoad<A, E>();
    _loads[loadKey] = load;
    final fiber = ScopeAccess.fork(
      _ownerExecution.scope,
      Effect.defer(() => _lookup(key)),
      _ownerExecution,
    );
    unawaited(
      fiber.join().then((exit) {
        _loads.remove(loadKey);
        if (exit case Succeeded<A, E>(:final value)) {
          if (!_isClosed && (_generations[key] ?? 0) == generation) {
            _values[key] = value;
          }
        }
        load.complete(exit);
      }),
    );
    return load;
  }

  Future<Exit<A, E>> _awaitLoad(
    _CacheLoad<A, E> load,
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
  }
}

final class _CacheLoad<A, E> {
  final Completer<Exit<A, E>> _completion = Completer();

  Future<Exit<A, E>> get exit => _completion.future;

  void complete(Exit<A, E> exit) {
    if (!_completion.isCompleted) _completion.complete(exit);
  }
}
