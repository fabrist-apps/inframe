import 'package:conflux/effect.dart';
import 'package:conflux/option.dart';
import 'package:conflux/result.dart';
import 'package:runnel/runnel.dart';
import 'package:test/test.dart';

void main() {
  RedisCommand<T> command<T>(String name, T value) => RedisCommand<T>(
    [RedisArgument.text(name)],
    (_) => Success(value),
  );

  group('RedisBatch', () {
    test('a batch retains heterogeneous values and individual failures', () async {
      final batch = RedisBatch.internal(
        maxCommands: 3,
        maxBytes: 1024,
        reservedCommands: 0,
        reservedBytes: 0,
        defaultTimeout: const Duration(seconds: 1),
        executor: (commands, timeout, operation) async => [
          const Success<Object?, RunnelError>('Ada'),
          const Success<Object?, RunnelError>(4),
          const Failure<Object?, RunnelError>(RunnelServerError('bad command', code: 'ERR')),
        ],
      );
      final name = batch.add(command('GET', 'Ada'));
      final count = batch.add(command('INCR', 4));
      final failed = batch.add(command<void>('GET', null));

      final results = await batch.exec().runFuture();

      expect(results.outcome(name).getOrThrowWith((error) => error), 'Ada');
      expect(results.outcome(count).getOrThrowWith((error) => error), 4);
      expect(
        results.outcome(failed),
        isA<Failure<void, RunnelError>>().having(
          (result) => result.error,
          'error',
          isA<RunnelServerError>().having((error) => error.code, 'code', 'ERR'),
        ),
      );
    });

    test('the documented typed command objects compose in a pipeline', () async {
      final batch = RedisBatch.internal(
        maxCommands: 2,
        maxBytes: 1024,
        reservedCommands: 0,
        reservedBytes: 0,
        defaultTimeout: const Duration(seconds: 1),
        executor: (commands, timeout, operation) async => const [
          Success<Object?, RunnelError>(Some('Ada')),
          Success<Object?, RunnelError>(3),
        ],
      );
      final name = batch.add(Get('user:42:name'));
      final visits = batch.add(Incr('user:42:visits'));

      final results = await batch.exec().runFuture();

      expect(
        results.outcome(name).getOrThrowWith((error) => error),
        isA<Some<String>>().having((value) => value.value, 'value', 'Ada'),
      );
      expect(results.outcome(visits).getOrThrowWith((error) => error), 3);
    });

    test('references belong to their originating batch', () async {
      RedisBatch makeBatch() => RedisBatch.internal(
        maxCommands: 2,
        maxBytes: 1024,
        reservedCommands: 0,
        reservedBytes: 0,
        defaultTimeout: const Duration(seconds: 1),
        executor: (_, _, _) async => const [Success<Object?, RunnelError>(1)],
      );

      final first = makeBatch();
      final foreign = makeBatch().add(command('INCR', 1));
      first.add(command('INCR', 1));
      final results = await first.exec().runFuture();

      expect(() => results.outcome(foreign).getOrThrowWith((error) => error), throwsArgumentError);
    });

    test('builder is single-use and performs no I/O before exec', () async {
      var executions = 0;
      final batch = RedisBatch.internal(
        maxCommands: 1,
        maxBytes: 1024,
        reservedCommands: 0,
        reservedBytes: 0,
        defaultTimeout: const Duration(seconds: 1),
        executor: (commands, timeout, operation) async {
          executions++;
          return const [Success<Object?, RunnelError>(true)];
        },
      )..add(command('PING', true));
      expect(executions, 0);

      await batch.exec().runFuture();
      expect(executions, 1);
      await expectLater(
        batch.exec().runFuture(),
        throwsA(
          isA<EffectException<RunnelError>>().having(
            (error) => error.cause.expectedErrors.single,
            'error',
            isA<RunnelUsageError>(),
          ),
        ),
      );
      expect(() => batch.add(command('PING', true)), throwsStateError);
    });

    test('builder enforces command and byte capacities before execution', () {
      final batch =
          RedisBatch.internal(
              maxCommands: 3,
              maxBytes: encodeCommand(command('PING', true) as RedisCommand<Object?>).length * 2,
              reservedCommands: 1,
              reservedBytes: 0,
              defaultTimeout: const Duration(seconds: 1),
              executor: (_, _, _) async => const [],
            )
            ..add(command('PING', true))
            ..add(command('PING', true));
      expect(() => batch.add(command('PING', true)), throwsStateError);
    });

    test('reserved and blocking commands are rejected', () {
      RedisBatch batch() => RedisBatch.internal(
        maxCommands: 10,
        maxBytes: 1024,
        reservedCommands: 0,
        reservedBytes: 0,
        defaultTimeout: const Duration(seconds: 1),
        executor: (_, _, _) async => const [],
      );

      expect(() => batch().add(command('MULTI', true)), throwsArgumentError);
      expect(
        () => batch().add(
          RedisCommand<bool>(
            [
              RedisArgument.text('XREAD'),
              RedisArgument.text('BLOCK'),
              RedisArgument.text('10'),
            ],
            (_) => const Success(true),
          ),
        ),
        throwsArgumentError,
      );
    });
  });
}
