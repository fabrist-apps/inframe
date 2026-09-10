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
          release: (resource) => Effect.sync(() => events.add(resource)),
        );
        await $.acquireRelease(
          Effect.succeed<String, String>('second'),
          release: (resource) => Effect.sync(() => events.add(resource)),
        );
      });

      final exit = await Runtime().run(program);

      expect(exit, isA<Succeeded<void, String>>());
      expect(events, ['second', 'first']);
    });

    test('should preserve execution and cleanup failures sequentially', () async {
      final program = Effect.build<void, String>(($) {
        $
          ..addFinalizer(Effect.sync(() => throw StateError('cleanup')))
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
            release: (_) => Effect.sync(() => released = true),
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
          .onExit((exit) => Effect.sync(() => seen.add('$exit')));
      final failure = Effect.fail<int, String>('no')
          .ensuring(Effect.sync(() => seen.add('failure')));

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
        ).onCancel(Effect.sync(() => cancellations += 1)),
      );
      await started.future;

      await fiber.interrupt('test');
      await Runtime().run(
        Effect.succeed<void, String>(null).onCancel(Effect.sync(() => cancellations += 1)),
      );
      await Runtime().run(
        Effect.fail<void, String>('no').onCancel(Effect.sync(() => cancellations += 1)),
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
          release: (value) => Effect.sync(value.close),
        );
        return connection.value;
      });

      final exit = await runtime.run(program);

      expect((exit as Succeeded<int, Never>).value, 42);
      expect(service.closed, isFalse);
      expect(service.connection.closed, isTrue);
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
