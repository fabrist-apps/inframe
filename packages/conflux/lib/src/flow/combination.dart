import 'dart:async';

import 'package:conflux/effect.dart';
import 'package:conflux/option.dart';
import 'package:conflux/src/effect/cause.dart' show CauseGroup, CauseRuntimeOperations;
import 'package:conflux/src/effect/effect.dart' show EffectAccess;
import 'package:conflux/src/effect/execution.dart' show ScopeAccess;
import 'package:conflux/src/flow/concurrent.dart';
import 'package:conflux/src/flow/flow_buffer.dart';
import 'package:conflux/src/flow/protocol.dart';

/// Opens cursors that combine multiple Flow sources.
abstract final class CombinationFlowSource {
  /// Opens every source for position-based concurrent pulls.
  static Effect<FlowSourceCursor<List<A>, E>, E> openZip<A, E>(
    Iterable<OpenFlowCursor<A, E>> sources,
  ) => Effect.build(($) async {
    final cursors = <FlowSourceCursor<A, E>>[];
    for (final source in sources) {
      cursors.add(await $(Effect.defer(source)));
    }
    return _ZipCursor(cursors);
  });

  /// Opens indexed source events for latest-value combination.
  static Effect<FlowSourceCursor<List<A>, E>, E> openCombineLatest<A, E>(
    Iterable<OpenFlowCursor<A, E>> sources, {
    required int capacity,
    required FlowOverflowPolicy overflow,
    required E Function(FlowBufferOverflow overflow)? onOverflow,
  }) => EffectAccess.create((execution) async {
    final sourceList = List<OpenFlowCursor<A, E>>.of(sources);
    final opened = await EffectAccess.evaluate(
      ConcurrentFlowSource.openMerge(
        sourceList.indexed.map(
          (entry) =>
              () => Effect.defer(entry.$2).map(
                (cursor) => _IndexedCursor(cursor, entry.$1),
              ),
        ),
        capacity: capacity,
        overflow: overflow,
        onOverflow: onOverflow,
      ),
      execution,
    );
    return switch (opened) {
      Succeeded<FlowSourceCursor<_IndexedEvent<A>, E>, E>(:final value) => Succeeded(
        _CombineLatestCursor(value, sourceList.length),
      ),
      Failed<FlowSourceCursor<_IndexedEvent<A>, E>, E>(:final cause) => Failed(cause),
    };
  });

  /// Opens primary and secondary events for trigger-based combination.
  static Effect<FlowSourceCursor<C, E>, E> openWithLatestFrom<A, B, C, E>(
    OpenFlowCursor<A, E> primary,
    OpenFlowCursor<B, E> secondary,
    C Function(A primary, B latest) combine, {
    required int capacity,
    required FlowOverflowPolicy overflow,
    required E Function(FlowBufferOverflow overflow)? onOverflow,
  }) => EffectAccess.create((execution) async {
    final sources = <OpenFlowCursor<_WithLatestEvent<A, B>, E>>[
      () => Effect.defer(primary).map(_PrimaryCursor<A, B, E>.new),
      () => Effect.defer(secondary).map(_SecondaryCursor<A, B, E>.new),
    ];
    final opened = await EffectAccess.evaluate(
      ConcurrentFlowSource.openMerge(
        sources,
        capacity: capacity,
        overflow: overflow,
        onOverflow: onOverflow,
      ),
      execution,
    );
    return switch (opened) {
      Succeeded<FlowSourceCursor<_WithLatestEvent<A, B>, E>, E>(:final value) => Succeeded(
        _WithLatestCursor(value, combine),
      ),
      Failed<FlowSourceCursor<_WithLatestEvent<A, B>, E>, E>(:final cause) => Failed(cause),
    };
  });
}

final class _ZipCursor<A, E> implements FlowSourceCursor<List<A>, E> {
  const _ZipCursor(this._sources);

  final List<FlowSourceCursor<A, E>> _sources;

  @override
  Effect<Option<List<A>>, E> next() => EffectAccess.create((execution) async {
    if (_sources.isEmpty) return const Succeeded(None());
    final pending = <int, Fiber<Option<A>, E>>{
      for (final entry in _sources.indexed)
        entry.$1: ScopeAccess.fork(
          execution.scope,
          entry.$2.next(),
          execution,
        ),
    };
    final results = List<Option<A>?>.filled(_sources.length, null);

    while (pending.isNotEmpty) {
      final completed = await Future.any(
        pending.entries.map(
          (entry) => entry.value.exit.then(
            (exit) => (index: entry.key, exit: exit),
          ),
        ),
      );
      pending.remove(completed.index);
      switch (completed.exit) {
        case Failed<Option<A>, E>(:final cause):
          final cleanup = await _interruptZipPulls(pending.values);
          return Failed(CauseGroup.sequential([cause, ?cleanup])!);
        case Succeeded<Option<A>, E>(value: None()):
          final cleanup = await _interruptZipPulls(pending.values);
          return cleanup == null ? const Succeeded(None()) : Failed(cleanup);
        case Succeeded<Option<A>, E>(:final value):
          results[completed.index] = value;
      }
    }

    final values = <A>[];
    for (final result in results) {
      switch (result) {
        case Some<A>(:final value):
          values.add(value);
        case None() || null:
          return Failed(
            Defect(
              StateError('Zip completed without one value from each source.'),
              StackTrace.current,
            ),
          );
      }
    }
    return Succeeded(Some(List.unmodifiable(values)));
  });
}

Future<Cause<E>?> _interruptZipPulls<E>(
  Iterable<Fiber<Option<Object?>, E>> pulls,
) async {
  final exits = await Future.wait(
    pulls.map((fiber) => fiber.interrupt(const FlowZipFinished())),
  );
  return CauseGroup.parallel(
    exits
        .whereType<Failed<Option<Object?>, E>>()
        .map((exit) => exit.cause.defectsOnly)
        .whereType<Cause<Never>>()
        .map((cause) => cause.mapExpected<E>(_widenNever)),
  );
}

sealed class _IndexedEvent<A> {
  const _IndexedEvent(this.index);

  final int index;
}

final class _IndexedValue<A> extends _IndexedEvent<A> {
  const _IndexedValue(super.index, this.value);

  final A value;
}

final class _IndexedDone<A> extends _IndexedEvent<A> {
  const _IndexedDone(super.index);
}

final class _IndexedCursor<A, E> implements FlowSourceCursor<_IndexedEvent<A>, E> {
  _IndexedCursor(this._upstream, this._index);

  final FlowSourceCursor<A, E> _upstream;
  final int _index;
  var _sentDone = false;

  @override
  Effect<Option<_IndexedEvent<A>>, E> next() {
    if (_sentDone) return Effect.succeed(const None());
    return _upstream.next().map((option) {
      return switch (option) {
        Some<A>(:final value) => Some(_IndexedValue(_index, value)),
        None() => () {
          _sentDone = true;
          return Some(_IndexedDone<A>(_index));
        }(),
      };
    });
  }
}

final class _CombineLatestCursor<A, E> implements FlowSourceCursor<List<A>, E> {
  _CombineLatestCursor(this._events, int sourceCount)
    : _latest = List<Option<A>>.filled(sourceCount, const None()),
      _active = sourceCount;

  final FlowSourceCursor<_IndexedEvent<A>, E> _events;
  final List<Option<A>> _latest;
  int _active;

  @override
  Effect<Option<List<A>>, E> next() => Effect.build(($) async {
    if (_active == 0) return const None();
    while (true) {
      switch (await $(_events.next())) {
        case Some<_IndexedEvent<A>>(value: _IndexedValue<A>(:final index, :final value)):
          _latest[index] = Some(value);
          if (_latest.every((value) => value is Some<A>)) {
            return Some(
              List.unmodifiable([
                for (final latest in _latest)
                  switch (latest) {
                    Some<A>(:final value) => value,
                    None() => throw StateError('Missing latest Flow value.'),
                  },
              ]),
            );
          }
        case Some<_IndexedEvent<A>>(value: _IndexedDone<A>(:final index)):
          if (_latest[index] case None()) return const None();
          _active -= 1;
          if (_active == 0) return const None();
        case None():
          return const None();
      }
    }
  });
}

sealed class _WithLatestEvent<A, B> {
  const _WithLatestEvent();
}

final class _PrimaryValue<A, B> extends _WithLatestEvent<A, B> {
  const _PrimaryValue(this.value);

  final A value;
}

final class _PrimaryDone<A, B> extends _WithLatestEvent<A, B> {
  const _PrimaryDone();
}

final class _SecondaryValue<A, B> extends _WithLatestEvent<A, B> {
  const _SecondaryValue(this.value);

  final B value;
}

final class _SecondaryDone<A, B> extends _WithLatestEvent<A, B> {
  const _SecondaryDone();
}

final class _PrimaryCursor<A, B, E> implements FlowSourceCursor<_WithLatestEvent<A, B>, E> {
  _PrimaryCursor(this._upstream);

  final FlowSourceCursor<A, E> _upstream;
  var _sentDone = false;

  @override
  Effect<Option<_WithLatestEvent<A, B>>, E> next() {
    if (_sentDone) return Effect.succeed(const None());
    return _upstream.next().map((option) {
      return switch (option) {
        Some<A>(:final value) => Some(_PrimaryValue<A, B>(value)),
        None() => () {
          _sentDone = true;
          return Some(_PrimaryDone<A, B>());
        }(),
      };
    });
  }
}

final class _SecondaryCursor<A, B, E> implements FlowSourceCursor<_WithLatestEvent<A, B>, E> {
  _SecondaryCursor(this._upstream);

  final FlowSourceCursor<B, E> _upstream;
  var _sentDone = false;

  @override
  Effect<Option<_WithLatestEvent<A, B>>, E> next() {
    if (_sentDone) return Effect.succeed(const None());
    return _upstream.next().map((option) {
      return switch (option) {
        Some<B>(:final value) => Some(_SecondaryValue<A, B>(value)),
        None() => () {
          _sentDone = true;
          return Some(_SecondaryDone<A, B>());
        }(),
      };
    });
  }
}

final class _WithLatestCursor<A, B, C, E> implements FlowSourceCursor<C, E> {
  _WithLatestCursor(this._events, this._combine);

  final FlowSourceCursor<_WithLatestEvent<A, B>, E> _events;
  final C Function(A primary, B latest) _combine;
  Option<B> _latest = const None();

  @override
  Effect<Option<C>, E> next() => Effect.build(($) async {
    while (true) {
      switch (await $(_events.next())) {
        case Some<_WithLatestEvent<A, B>>(value: _SecondaryValue<A, B>(:final value)):
          _latest = Some(value);
        case Some<_WithLatestEvent<A, B>>(value: _SecondaryDone<A, B>()) when _latest is None:
          return const None();
        case Some<_WithLatestEvent<A, B>>(value: _SecondaryDone<A, B>()):
          continue;
        case Some<_WithLatestEvent<A, B>>(value: _PrimaryValue<A, B>(:final value)):
          switch (_latest) {
            case Some<B>(value: final latest):
              return Some(_combine(value, latest));
            case None():
              continue;
          }
        case Some<_WithLatestEvent<A, B>>(value: _PrimaryDone<A, B>()) || None():
          return const None();
      }
    }
  });
}

E _widenNever<E>(Never error) => error;

/// Why Zip interrupted unused pulls after a source completed or failed.
final class FlowZipFinished {
  /// Creates the stable zip-finished interruption reason.
  const FlowZipFinished();

  @override
  String toString() => 'Flow zip finished';
}
