import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/transport.dart';
import 'package:conflux/effect.dart';
import 'package:context/context.dart';
import 'package:test/test.dart';

void main() {
  test('one observed attempt includes normalization and excludes content and headers', () async {
    final observations = <ProviderObservation>[];
    final client = ProviderHttpClient(observer: observations.add);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var requests = 0;
    server.listen((request) async {
      requests++;
      request.response.headers.set('x-request-id', 'native-id');
      request.response.headers.set('secret-header', 'credentials');
      request.response.write(jsonEncode({'text': 'private-content'}));
      await request.response.close();
    });
    final runtime = Runtime(
      context: Context().withBinding(
        invocationContextKey.bind(
          const InvocationContext(operationId: 'operation', attemptId: 'attempt'),
        ),
      ),
    );
    addTearDown(() async {
      await client.close();
      await runtime.close();
      await server.close(force: true);
    });
    final program = client.observe(
      client
          .requestJson(url: Uri.parse('http://127.0.0.1:${server.port}'))
          .map((_, _) => const Usage(inputTokens: 2, outputTokens: 3)),
      providerId: 'fixture',
      api: 'text',
      modelId: 'model',
      usage: (value) => value,
      verdict: (_) => FinishReason.stop,
    );
    expect(observations, isEmpty);
    expect(await runtime.run(program), isA<Succeeded<Usage, AiError>>());
    expect(requests, 1);
    expect(observations.map((e) => e.kind), [
      ProviderObservationKind.started,
      ProviderObservationKind.response,
      ProviderObservationKind.usage,
      ProviderObservationKind.verdict,
      ProviderObservationKind.finished,
    ]);
    expect(observations.last.outcome, ProviderOutcome.succeeded);
    expect(
      observations.every(
        (e) =>
            e.operationId == 'operation' && e.attemptId == 'attempt' && e.providerId == 'fixture',
      ),
      isTrue,
    );
    expect(observations[1].requestId, 'native-id');
    final encoded = observations.map((e) => e.toJson()).join();
    expect(encoded, isNot(contains('private-content')));
    expect(encoded, isNot(contains('credentials')));
    expect(encoded, isNot(contains('secret-header')));
    expect(
      ProviderObservation.fromJson(observations.last.toJson()).outcome,
      ProviderOutcome.succeeded,
    );
  });

  test('observer failure is a defect with cleanup and exactly one terminal record', () async {
    final observations = <ProviderObservation>[];
    final client = ProviderHttpClient(
      observer: (event) {
        observations.add(event);
        if (event.kind == ProviderObservationKind.response) throw StateError('observer failed');
      },
    );
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.write('{}');
      await request.response.close();
    });
    final runtime = Runtime();
    addTearDown(() async {
      await client.close();
      await runtime.close();
      await server.close(force: true);
    });
    final exit = await runtime.run(
      client.requestJson(url: Uri.parse('http://127.0.0.1:${server.port}')),
    );
    expect((exit as Failed).cause, isA<Defect<AiError>>());
    expect(
      observations.where((e) => e.kind == ProviderObservationKind.finished).single.outcome,
      ProviderOutcome.defect,
    );
  });

  test(
    'interrupted body emits one interrupted outcome and no observations on preflight failure',
    () async {
      final observations = <ProviderObservation>[];
      final client = ProviderHttpClient(observer: observations.add);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final headers = Completer<void>();
      server.listen((request) async {
        request.response.write('{');
        await request.response.flush();
        headers.complete();
      });
      final runtime = Runtime();
      addTearDown(() async {
        await client.close();
        await runtime.close();
        await server.close(force: true);
      });
      await runtime.run(client.requestJson(url: Uri.parse('invalid')));
      expect(observations, isEmpty);
      final fiber = runtime.fork(
        client.requestJson(url: Uri.parse('http://127.0.0.1:${server.port}')),
      );
      await headers.future;
      await fiber.interrupt('test');
      expect(
        observations.where((e) => e.kind == ProviderObservationKind.finished).single.outcome,
        ProviderOutcome.interrupted,
      );
    },
  );
  test('early stream consumption records interruption and keeps the client usable', () async {
    final observations = <ProviderObservation>[];
    final client = ProviderHttpClient(observer: observations.add);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.headers.contentType = ContentType('text', 'event-stream');
      request.response.write('data: first\n\ndata: second\n\n');
      await request.response.close();
    });
    final runtime = Runtime();
    addTearDown(() async {
      await client.close();
      await runtime.close();
      await server.close(force: true);
    });
    final flow = client.withSse<String>(
      url: Uri.parse('http://127.0.0.1:${server.port}'),
      consume: (_, events) => events.map((event, _) => event.data),
    );
    final early = await runtime.run(flow.take(1).runCollect());
    expect(early, isA<Succeeded<List<String>, AiError>>());
    expect(observations.last.outcome, ProviderOutcome.interrupted);
    expect(await runtime.run(flow.runCollect()), isA<Succeeded<List<String>, AiError>>());
    expect(observations.last.outcome, ProviderOutcome.succeeded);
    final starts = observations.where((e) => e.kind == ProviderObservationKind.started).toList();
    expect(starts, hasLength(2));
    expect(starts.first.attemptId, isNot(starts.last.attemptId));
    expect(observations.where((e) => e.kind == ProviderObservationKind.finished), hasLength(2));
  });

  test(
    'native HTTP diagnostics keep status code message details identity and Retry-After',
    () async {
      final client = ProviderHttpClient();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        request.response.statusCode = 429;
        request.response.headers.set('retry-after', '17');
        request.response.headers.set('x-request-id', 'error-request');
        request.response.write(
          '{"error":{"message":"native message","code":"new_code","future":[1]}}',
        );
        await request.response.close();
      });
      final runtime = Runtime();
      addTearDown(() async {
        await client.close();
        await runtime.close();
        await server.close(force: true);
      });
      final exit = await runtime.run(
        client.requestJson(url: Uri.parse('http://127.0.0.1:${server.port}')),
      );
      final error = (exit as Failed).cause.expectedErrors.single as ProviderError;
      expect(error.statusCode, 429);
      expect(error.code, 'new_code');
      expect(error.message, 'native message');
      expect(error.requestId, 'error-request');
      expect(error.retryAfterDelay, const Duration(seconds: 17));
      expect((error.details! as Map)['error']['future'], [1]);
    },
  );
}
