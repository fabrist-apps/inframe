import 'dart:io';

import 'package:conflux/effect.dart';
import 'package:conflux/option.dart';
import 'package:conflux/result.dart';
import 'package:runnel/runnel.dart';

/// Uses a local or disposable endpoint; writes the example user's name and visits.
Future<void> main() async {
  final endpoint = Platform.environment['RUNNEL_URL'] ?? 'redis://localhost:6379';
  final program = Effect.build<Option<String>, RunnelError>(($) async {
    final redis = await $.acquireRelease(
      Runnel.connect(endpoint),
      release: (redis, _) => redis.close(),
    );
    await $(redis.set('example:user:42:name', 'Bhaswanth'));

    final batch = redis.pipeline();
    final name = batch.add(Get('example:user:42:name'));
    final visits = batch.add(Incr('example:user:42:visits'));
    final results = await $(batch.exec());
    final savedName = $.sync(results.outcome(name));
    stdout.writeln('Visits: ${$.sync(results.outcome(visits))}');

    final ping = RedisCommand<bool>(
      [RedisArgument.text('PING')],
      (reply) => switch (reply) {
        RespSimpleString(value: 'PONG') => const Success(true),
        _ => const Failure(RunnelDecodingError('Expected PONG.')),
      },
    );
    stdout.writeln('Healthy: ${await $(redis.execute(ping))}');
    return savedName;
  });

  // This is the explicit Future boundary. Scope cleanup finishes before the exit.
  switch (await program.runFutureExit()) {
    case Succeeded<Option<String>, RunnelError>(:final value):
      stdout.writeln(switch (value) {
        Some(:final value) => 'Name: $value',
        None() => 'Name is absent.',
      });
    case Failed<Option<String>, RunnelError>(:final cause):
      stderr.writeln('Example failed: $cause');
      exitCode = 1;
  }
}
