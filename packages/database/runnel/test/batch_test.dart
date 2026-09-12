import 'package:runnel/runnel.dart';
import 'package:test/test.dart';

void main() {
  RedisCommand<T> command<T>(String name, T value) => RedisCommand<T>(
    [RedisArgument.text(name)],
    (_) => value,
  );

  test('a batch retains heterogeneous values and individual failures', () async {
    final batch = RedisBatch.internal(
      maxCommands: 3,
      maxBytes: 1024,
      reservedCommands: 0,
      reservedBytes: 0,
      defaultTimeout: const Duration(seconds: 1),
      executor: (commands, timeout) async => [
        const BatchSuccess<Object?>('Ada'),
        const BatchSuccess<Object?>(4),
        BatchFailure<Object?>(StateError('bad command'), StackTrace.current),
      ],
    );
    final name = batch.add(command('GET', 'Ada'));
    final count = batch.add(command('INCR', 4));
    final failed = batch.add(command<void>('GET', null));

    final results = await batch.exec();

    expect(results.value(name), 'Ada');
    expect(results.value(count), 4);
    expect(results.outcome(failed), isA<BatchFailure<void>>());
    expect(() => results.value(failed), throwsStateError);
  });

  test('the documented typed command objects compose in a pipeline', () async {
    final batch = RedisBatch.internal(
      maxCommands: 2,
      maxBytes: 1024,
      reservedCommands: 0,
      reservedBytes: 0,
      defaultTimeout: const Duration(seconds: 1),
      executor: (commands, timeout) async => const [
        BatchSuccess<Object?>('Ada'),
        BatchSuccess<Object?>(3),
      ],
    );
    final name = batch.add(Get('user:42:name'));
    final visits = batch.add(Incr('user:42:visits'));

    final results = await batch.exec();

    expect(results.value(name), 'Ada');
    expect(results.value(visits), 3);
  });

  test('references belong to their originating batch', () async {
    Future<List<BatchOutcome<Object?>>> executor(
      List<RedisCommand<Object?>> commands,
      Duration timeout,
    ) async => const [BatchSuccess<Object?>(1)];

    RedisBatch makeBatch() => RedisBatch.internal(
      maxCommands: 2,
      maxBytes: 1024,
      reservedCommands: 0,
      reservedBytes: 0,
      defaultTimeout: const Duration(seconds: 1),
      executor: executor,
    );

    final first = makeBatch();
    final foreign = makeBatch().add(command('INCR', 1));
    first.add(command('INCR', 1));
    final results = await first.exec();

    expect(() => results.value(foreign), throwsArgumentError);
  });

  test('builder is single-use and performs no I/O before exec', () async {
    var executions = 0;
    final batch = RedisBatch.internal(
      maxCommands: 1,
      maxBytes: 1024,
      reservedCommands: 0,
      reservedBytes: 0,
      defaultTimeout: const Duration(seconds: 1),
      executor: (commands, timeout) async {
        executions++;
        return const [BatchSuccess<Object?>(true)];
      },
    );
    // A separate call keeps the pre-execution assertion explicit.
    // A later invocation verifies that the next entry is rejected.
    // ignore: cascade_invocations
    batch.add(command('PING', true));
    expect(executions, 0);

    await batch.exec();
    expect(executions, 1);
    await expectLater(batch.exec(), throwsStateError);
    expect(() => batch.add(command('PING', true)), throwsStateError);
  });

  test('builder enforces command and byte capacities before execution', () {
    final batch = RedisBatch.internal(
      maxCommands: 3,
      maxBytes: encodeCommand(command('PING', true) as RedisCommand<Object?>).length * 2,
      reservedCommands: 1,
      reservedBytes: 0,
      defaultTimeout: const Duration(seconds: 1),
      executor: (_, _) async => const [],
    );

    // The following call separately verifies rejection beyond the exact limit.
    // ignore: cascade_invocations
    batch
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
      executor: (_, _) async => const [],
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
          (_) => true,
        ),
      ),
      throwsArgumentError,
    );
  });
}
