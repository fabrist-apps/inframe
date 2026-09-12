import 'dart:async';

import 'package:conflux/conflux.dart';
import 'package:context/context.dart';
import 'package:test/test.dart';

void main() {
  group('Effect resource cleanup', () {
    test('should release acquired resources once in reverse order', () async {
      final events = <String>[];
      final program = Effect.build<void, String>(($) async {
        await $.acquireRelease(
          Effect.succeed<String, String>('first'),
          release: (resource) => Effect.sync((_) => events.add(resource)),
        );
        await $.acquireRelease(
          Effect.succeed<String, String>('second'),
          release: (resource) => Effect.sync((_) => events.add(resource)),
        );
      });

      final exit = await Runtime().run(program);

      expect(exit, isA<Succeeded<void, String>>());
      expect(events, ['second', 'first']);
    });

    test('should preserve execution and cleanup failures sequentially', () async {
      final program = Effect.build<void, String>(($) {
        $
          ..addFinalizer(Effect.sync((_) => throw StateError('cleanup')))
          ..sync<void>(const Failure('operation'));
      });

      final exit = await Runtime().run(program);
      final cause = (exit as Failed<void, String>).cause;

      expect(cause, isA<Sequential<String>>());
      final causes = (cause as Sequential<String>).causes;
      expect(causes[0], isA<Expected<String>>());
      expect(causes[1], isA<Defect<String>>());
    });

    test('should finish a using scope before returning to its parent', () async {
      var released = false;
      final child = Effect.using(
        Effect.build<int, Never>(($) async {
          return $.acquireRelease(
            Effect.succeed<int, Never>(42),
            release: (_) => Effect.sync((_) => released = true),
          );
        }),
      );
      final parent = Effect.build<bool, Never>(($) async {
        await $(child);
        return released;
      });

      final exit = await Runtime().run(parent);

      expect((exit as Succeeded<bool, Never>).value, isTrue);
    });

    test('should run ensuring and onExit for success and failure', () async {
      final seen = <String>[];
      final success = Effect.succeed<int, String>(1)
          .onExit((exit) => Effect.sync((_) => seen.add('$exit')));
      final failure = Effect.fail<int, String>('no')
          .ensuring(Effect.sync((_) => seen.add('failure')));

      await Runtime().run(success);
      await Runtime().run(failure);

      expect(seen, hasLength(2));
      expect(seen.last, 'failure');
    });

    test('should run onCancel only for interruption', () async {
      final started = Completer<void>();
      final pending = Completer<void>();
      var cancellations = 0;
      final runtime = Runtime();
      final fiber = runtime.fork(
        Effect.tryFuture<void, String>(
          () {
            started.complete();
            return pending.future;
          },
          onError: (error, _) => '$error',
        ).onCancel(Effect.sync((_) => cancellations += 1)),
      );
      await started.future;

      await fiber.interrupt('test');
      await Runtime().run(
        Effect.succeed<void, String>(null).onCancel(Effect.sync((_) => cancellations += 1)),
      );
      await Runtime().run(
        Effect.fail<void, String>('no').onCancel(Effect.sync((_) => cancellations += 1)),
      );

      expect(cancellations, 1);
    });

    test('should borrow Context values and release only acquired resources', () async {
      final key = ContextKey<_Service>('service');
      final service = _Service();
      final runtime = Runtime(
        context: Context().withBinding(key.bind(service)),
      );
      final program = Effect.build<int, Never>(($) async {
        final borrowed = $.context.require(key);
        final connection = await $.acquireRelease(
          Effect.succeed<_Connection, Never>(borrowed.connect()),
          release: (value) => Effect.sync((_) => value.close()),
        );
        return connection.value;
      });

      final exit = await runtime.run(program);

      expect((exit as Succeeded<int, Never>).value, 42);
      expect(service.closed, isFalse);
      expect(service.connection.closed, isTrue);
    });

    test('should register release before cancellation can abandon the resource', () async {
      final acquireStarted = Completer<void>();
      final acquired = Completer<_Connection>();
      final registered = Completer<void>();
      final pending = Completer<void>();
      final connection = _Connection();
      final runtime = Runtime();
      final fiber = runtime.fork(
        Effect.build<void, String>(($) async {
          await $.acquireRelease(
            Effect.tryFuture<_Connection, String>(
              () {
                acquireStarted.complete();
                return acquired.future;
              },
              onError: (error, _) => '$error',
            ),
            release: (resource) => Effect.sync((_) => resource.close()),
          );
          registered.complete();
          await $(
            Effect.tryFuture<void, String>(
              () => pending.future,
              onError: (error, _) => '$error',
            ),
          );
        }),
      );
      await acquireStarted.future;

      acquired.complete(connection);
      await registered.future;
      await fiber.interrupt('test');

      expect(connection.closed, isTrue);
    });

    test('should release a resource acquired after its builder scope closes', () async {
      final acquired = Completer<_Connection>();
      final connection = _Connection();
      late Future<_Connection> acquisition;
      final program = Effect.build<void, String>(($) {
        acquisition = $.acquireRelease(
          Effect.tryFuture<_Connection, String>(
            () => acquired.future,
            onError: (error, _) => '$error',
          ),
          release: (resource) => Effect.sync((_) => resource.close()),
        );
      });

      final exit = await Runtime().run(program);
      acquired.complete(connection);

      expect(exit, isA<Succeeded<void, String>>());
      await expectLater(acquisition, throwsStateError);
      expect(connection.closed, isTrue);
    });

    test('should protect finalization from repeated cancellation', () async {
      final bodyStarted = Completer<void>();
      final bodyPending = Completer<void>();
      final releaseStarted = Completer<void>();
      final releaseGate = Completer<void>();
      final runtime = Runtime();
      final fiber = runtime.fork(
        Effect.build<void, String>(($) async {
          await $.acquireRelease(
            Effect.succeed<void, String>(null),
            release: (_) => Effect.tryFuture<void, Never>(
              () {
                releaseStarted.complete();
                return releaseGate.future;
              },
              onError: (error, _) => throw StateError('$error'),
            ),
          );
          bodyStarted.complete();
          await $(
            Effect.tryFuture<void, String>(
              () => bodyPending.future,
              onError: (error, _) => '$error',
            ),
          );
        }),
      );
      await bodyStarted.future;

      final interrupted = fiber.interrupt('first');
      await releaseStarted.future;
      var finished = false;
      unawaited(interrupted.whenComplete(() => finished = true));
      await fiber
          .interrupt('second')
          .timeout(
            const Duration(milliseconds: 10),
            onTimeout: () => const Failed<void, String>(Interrupted('timeout')),
          );
      expect(finished, isFalse);
      releaseGate.complete();

      await interrupted;
      expect(finished, isTrue);
    });

    test('should keep multiple cleanup failures in reverse order', () async {
      final program = Effect.build<void, String>(($) {
        $
          ..addFinalizer(Effect.sync((_) => throw StateError('first')))
          ..addFinalizer(Effect.sync((_) => throw StateError('second')))
          ..sync<void>(const Failure('operation'));
      });

      final cause = (await Runtime().run(program) as Failed<void, String>).cause;
      final outer = (cause as Sequential<String>).causes;
      final cleanup = (outer[1] as Sequential<String>).causes;

      expect((cleanup[0] as Defect<String>).error.toString(), contains('second'));
      expect((cleanup[1] as Defect<String>).error.toString(), contains('first'));
    });

    test('should finish child cleanup before releasing parent resources', () async {
      final events = <String>[];
      final childStarted = Completer<void>();
      final childPending = Completer<int>();
      final program = Effect.build<void, String>(($) async {
        await $.acquireRelease(
          Effect.succeed<void, String>(null),
          release: (_) => Effect.sync((_) => events.add('release')),
        );
        await $(
          Effect.all<int, String>([
            Effect.tryFuture<int, String>(
              () async {
                await childStarted.future;
                throw StateError('failed');
              },
              onError: (_, _) => 'failed',
            ),
            Effect.tryFuture<int, String>(
              () {
                childStarted.complete();
                return childPending.future;
              },
              onError: (error, _) => '$error',
              onCancel: () async {
                await Future<void>.delayed(Duration.zero);
                events.add('child');
              },
            ),
          ], concurrency: 2),
        );
      });

      await Runtime().run(program);

      expect(events, ['child', 'release']);
    });
  });
}

final class _Service {
  bool closed = false;
  final connection = _Connection();

  _Connection connect() => connection;
}

final class _Connection {
  final int value = 42;
  bool closed = false;

  void close() => closed = true;
}
