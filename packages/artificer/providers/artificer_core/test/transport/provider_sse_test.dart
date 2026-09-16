import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:artificer_core/src/errors.dart';
import 'package:artificer_core/transport.dart';
import 'package:conflux/effect.dart';
import 'package:conflux/flow.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:test/test.dart';

void main() {
  group('ProviderHttpClient SSE', () {
    late HttpServer server;
    late Runtime runtime;
    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      runtime = Runtime();
    });
    tearDown(() async {
      await server.close(force: true);
      await runtime.close();
    });
    Uri endpoint([String path = '/']) => Uri.parse('http://127.0.0.1:${server.port}$path');

    test(
      'should join early take cleanup before emitting a trailing result and reuse Dio',
      () async {
        server.listen((request) async {
          if (request.uri.path == '/reuse') {
            request.response.write('{}');
            await request.response.close();
            return;
          }
          request.response.bufferOutput = false;
          request.response.write('data: first\n\n${': padding${'x' * 4096}'}\n');
          await request.response.flush();
        });
        late _ObservedAdapter adapter;
        final dio = Dio()
          ..httpClientAdapter = ProviderDioAdapter(
            createAdapter: (factory) => adapter = _ObservedAdapter(factory, gateCancellation: true),
          );
        addTearDown(() => dio.close(force: true));
        final client = ProviderHttpClient(dio: dio);
        addTearDown(client.close);
        var trailing = false;
        final flow = client
            .withSse<String>(
              url: endpoint(),
              consume: (_, events) => events.map((event, _) => event.data).take(1),
            )
            .concat(
              Effect.sync((_) {
                trailing = true;
                return 'finished';
              }).mapError<AiError>((error, _) => throw StateError('unreachable')).asFlow(),
            );
        final pending = runtime.run(flow.runCollect());
        await adapter.cancelStarted.future;
        expect(trailing, isFalse);
        adapter.cancelRelease.complete();
        final exit = await pending;
        expect((exit as Succeeded<List<String>, AiError>).value, ['first', 'finished']);
        expect(
          await runtime.run(client.requestJson(url: endpoint('/reuse'))),
          isA<Succeeded<ProviderJsonResponse, AiError>>(),
        );
      },
    );

    test('should preserve provider interruption while waiting for the next SSE frame', () async {
      server.listen((request) async {
        request.response.bufferOutput = false;
        request.response.write('data: first\n\n: ${'x' * 4096}\n');
        await request.response.flush();
      });
      final client = ProviderHttpClient();
      final first = Completer<void>();
      final flow = client.withSse<SseEvent>(
        url: endpoint(),
        consume: (_, events) => events.tap(
          (_, _) => Effect.sync((_) {
            if (!first.isCompleted) first.complete();
          }),
        ),
      );
      final pending = runtime.run(flow.runDrain());
      await first.future;
      await client.close();
      final exit = await pending;
      expect((exit as Failed<void, AiError>).cause.containsInterruption, isTrue);
    });

    test('should close owned transport without waiting for a caller callback', () async {
      server.listen((request) async {
        request.response.bufferOutput = false;
        request.response.write('data: first\n\n: ${'x' * 4096}\n');
        await request.response.flush();
      });
      final client = ProviderHttpClient();
      final consuming = Completer<void>();
      final releaseConsumer = Completer<void>();
      final flow = client.withSse<SseEvent>(url: endpoint(), consume: (_, events) => events);
      final pending = runtime.run(
        flow.runForEach(
          (_, _) => Effect.tryFuture((_) async {
            if (!consuming.isCompleted) consuming.complete();
            await releaseConsumer.future;
          }, onError: (error, stack, _) => Error.throwWithStackTrace(error, stack)),
        ),
      );
      await consuming.future;
      var closed = false;
      final closing = client.close();
      unawaited(closing.then((_) => closed = true));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final closedBeforeCallerReturned = closed;
      releaseConsumer.complete();
      await closing;
      final exit = await pending;
      expect(closedBeforeCallerReturned, isTrue);
      expect((exit as Failed<void, AiError>).cause.containsInterruption, isTrue);
    });

    test('should preserve caller interruption and release a stalled stream', () async {
      server.listen((request) async {
        request.response.bufferOutput = false;
        request.response.write('data: first\n\n: ${'x' * 4096}\n');
        await request.response.flush();
      });
      final client = ProviderHttpClient();
      addTearDown(client.close);
      final first = Completer<void>();
      final flow = client.withSse<SseEvent>(
        url: endpoint(),
        consume: (_, events) => events.tap(
          (_, _) => Effect.sync((_) {
            if (!first.isCompleted) first.complete();
          }),
        ),
      );
      final fiber = runtime.fork(flow.runDrain());
      await first.future;
      final exit = await fiber.interrupt('test');
      expect((exit as Failed<void, AiError>).cause.containsInterruption, isTrue);
    });

    test('should bound frames within one chunk and pause upstream for a slow consumer', () async {
      server.listen((request) async {
        request.response.bufferOutput = false;
        request.response.add([
          ...utf8.encode(List.generate(3, (i) => 'data: $i\n\n').join()),
          ...[100, 97, 116, 97, 58, 255, 10, 10],
        ]);
        await request.response.flush();
      });
      late _ObservedAdapter adapter;
      final dio = Dio()
        ..httpClientAdapter = ProviderDioAdapter(
          createAdapter: (factory) => adapter = _ObservedAdapter(factory),
        );
      addTearDown(() => dio.close(force: true));
      final client = ProviderHttpClient(dio: dio);
      addTearDown(client.close);
      final first = Completer<void>();
      final consumeMore = Completer<void>();
      final seen = <String>[];
      final flow = client.withSse<SseEvent>(
        url: endpoint(),
        eventCapacity: 2,
        consume: (_, events) => events,
      );
      final pending = runtime.run(
        flow.runForEach(
          (event, _) => Effect.tryFuture((_) async {
            seen.add(event.data);
            if (!first.isCompleted) {
              first.complete();
              await consumeMore.future;
            }
          }, onError: (error, stack, _) => Error.throwWithStackTrace(error, stack)),
        ),
      );
      await first.future;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(adapter.pauses, greaterThan(0));
      expect(
        adapter.cancelStarted.isCompleted,
        isFalse,
        reason: 'The parser must not decode the malformed tail while its capacity is full.',
      );
      expect(seen, ['0']);
      consumeMore.complete();
      final exit = await pending;
      expect(seen.length, 3);
      expect((exit as Failed<void, AiError>).cause.expectedErrors.single, isA<ProtocolError>());
    });

    test('should resume response reads and open a fresh request per consumption', () async {
      var requests = 0;
      server.listen((request) async {
        requests++;
        request.response.bufferOutput = false;
        request.response.write('data: first\n\n');
        await request.response.flush();
        await Future<void>.delayed(const Duration(milliseconds: 10));
        request.response.write('data: second\n\n');
        await request.response.close();
      });
      late _ObservedAdapter adapter;
      final dio = Dio()
        ..httpClientAdapter = ProviderDioAdapter(
          createAdapter: (factory) => adapter = _ObservedAdapter(factory),
        );
      addTearDown(() => dio.close(force: true));
      final client = ProviderHttpClient(dio: dio);
      addTearDown(client.close);
      final flow = client.withSse<String>(
        url: endpoint(),
        eventCapacity: 1,
        consume: (_, events) => events.map((event, _) => event.data),
      );
      expect(requests, 0);
      for (var i = 0; i < 2; i++) {
        final exit = await runtime.run(flow.runCollect());
        expect((exit as Succeeded<List<String>, AiError>).value, ['first', 'second']);
      }
      expect(requests, 2);
      expect(adapter.pauses, greaterThan(0));
      expect(adapter.resumes, greaterThan(0));
    });

    test('should retain native event failure when stream cleanup also fails', () async {
      server.listen((request) async {
        request.response.bufferOutput = false;
        request.response.write('data: error\n\n: ${'x' * 4096}\n');
        await request.response.flush();
      });
      final cleanupError = StateError('SSE cancellation failure');
      final dio = Dio()
        ..httpClientAdapter = ProviderDioAdapter(
          createAdapter: (factory) => _ObservedAdapter(factory, cleanupError: cleanupError),
        );
      addTearDown(() => dio.close(force: true));
      final client = ProviderHttpClient(dio: dio);
      addTearDown(client.close);
      final flow = client.withSse<SseEvent>(
        url: endpoint(),
        consume: (_, events) =>
            events.mapEffect((_, _) => Effect.fail(const ProtocolError('Native stream error.'))),
      );
      final exit = await runtime.run(flow.runDrain());
      final cause = (exit as Failed<void, AiError>).cause;
      expect(cause.expectedErrors, contains(isA<ProtocolError>()));
      expect(cause.containsFatal, isTrue);
      expect(cause, isA<Sequential<AiError>>());
    });

    test(
      'should retain bounded unsuccessful native JSON and reject oversized SSE events',
      () async {
        server.listen((request) async {
          if (request.uri.path == '/error') {
            request.response.statusCode = 429;
            request.response.write('{"unknown":true}');
          } else {
            request.response.write('data: too long\n\n');
          }
          await request.response.close();
        });
        final client = ProviderHttpClient();
        addTearDown(client.close);
        final error = await runtime.run(
          client
              .withSse<SseEvent>(url: endpoint('/error'), consume: (_, events) => events)
              .runDrain(),
        );
        expect(
          ((error as Failed<void, AiError>).cause.expectedErrors.single as ProviderError).details,
          {'unknown': true},
        );
        final limited = await runtime.run(
          client
              .withSse<SseEvent>(url: endpoint(), maxEventBytes: 8, consume: (_, events) => events)
              .runDrain(),
        );
        expect(
          (limited as Failed<void, AiError>).cause.expectedErrors.single,
          isA<ResponseLimitError>(),
        );
      },
    );
  });
}

class _ObservedAdapter extends IOHttpClientAdapter {
  _ObservedAdapter(
    HttpClient Function() factory, {
    this.gateCancellation = false,
    this.cleanupError,
  }) : super(createHttpClient: factory);
  final bool gateCancellation;
  final Object? cleanupError;
  final cancelStarted = Completer<void>();
  final cancelRelease = Completer<void>();
  int pauses = 0;
  int resumes = 0;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final response = await super.fetch(options, requestStream, cancelFuture);
    if (options.uri.path == '/reuse') return response;
    final source = response.stream;
    late StreamController<Uint8List> controller;
    late StreamSubscription<Uint8List> subscription;
    controller = StreamController<Uint8List>(
      onListen: () {
        subscription = source.listen(
          controller.add,
          onError: controller.addError,
          onDone: controller.close,
        );
      },
      onPause: () {
        pauses++;
        subscription.pause();
      },
      onResume: () {
        resumes++;
        subscription.resume();
      },
      onCancel: () async {
        if (!cancelStarted.isCompleted) cancelStarted.complete();
        await subscription.cancel();
        if (gateCancellation) await cancelRelease.future;
        if (cleanupError != null) throw cleanupError!;
      },
    );
    response.stream = controller.stream;
    return response;
  }
}
