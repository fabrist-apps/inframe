import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/protocols.dart';
import 'package:artificer_core/transport.dart';
import 'package:conflux/conflux.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

void main() {
  group('ProviderHttpClient SSE', () {
    test('decodes fragmented UTF-8, line splits, and multiple frames per chunk', () async {
      var requests = 0;
      final payload = utf8.encode(
        'event: delta\nid: one\ndata: café\n\n'
        'data: first\ndata: second\nretry: 25\n\n',
      );
      final client = ProviderHttpClient(
        baseUrl: Uri.parse('https://example.test/'),
        client: _ResponseClient(() {
          requests++;
          return http.StreamedResponse(
            Stream.fromIterable(payload.map((byte) => [byte])),
            200,
            headers: {'x-request-id': 'request-1'},
          );
        }),
      );
      addTearDown(client.close);
      final operation = client.sendSse<SseEvent>(
        ProviderHttpRequest(method: 'POST', path: 'stream'),
        createProtocol: _PassthroughProtocol.new,
      );

      final first = await operation.runCollect().runFuture();
      final second = await operation.runCollect().runFuture();
      final concurrent = await Future.wait([
        operation.runCollect().runFuture(),
        operation.runCollect().runFuture(),
      ]);

      expect(requests, 4);
      expect(first.map((event) => event.data), ['café', 'first\nsecond']);
      expect(first.first.event, 'delta');
      expect(first.first.id, 'one');
      expect(first.last.retry, const Duration(milliseconds: 25));
      expect(second.map((event) => event.data), ['café', 'first\nsecond']);
      expect(concurrent, everyElement(hasLength(2)));
    });

    test('dispatches a final event terminated by a bare carriage-return line', () async {
      final client = ProviderHttpClient(
        baseUrl: Uri.parse('https://example.test/'),
        client: _ResponseClient(
          () => http.StreamedResponse(
            Stream.value(utf8.encode('data: final\n\r')),
            200,
          ),
        ),
      );
      addTearDown(client.close);

      final events = await client
          .sendSse<SseEvent>(
            ProviderHttpRequest(method: 'GET', path: 'stream'),
            createProtocol: _PassthroughProtocol.new,
          )
          .runCollect()
          .runFuture();

      expect(events.map((event) => event.data), ['final']);
    });

    test('enforces independent exact event and response byte limits', () async {
      Future<Object> run(String body, {required int eventLimit, required int streamLimit}) async {
        final client = ProviderHttpClient(
          baseUrl: Uri.parse('https://example.test/'),
          client: _ResponseClient(
            () => http.StreamedResponse(Stream.value(utf8.encode(body)), 200),
          ),
        );
        addTearDown(client.close);
        return client
            .sendSse<SseEvent>(
              ProviderHttpRequest(method: 'GET', path: 'stream'),
              createProtocol: _PassthroughProtocol.new,
              maxEventBytes: eventLimit,
              maxStreamBytes: streamLimit,
            )
            .runCollect()
            .runFutureExit();
      }

      const exact = 'data: x\n\n';
      expect(
        await run(exact, eventLimit: exact.length, streamLimit: exact.length),
        isA<Succeeded<List<SseEvent>, AiError>>(),
      );
      expect(
        await run(exact, eventLimit: exact.length - 1, streamLimit: exact.length),
        _failedWith<ResponseLimitError>(),
      );
      expect(
        await run(exact, eventLimit: exact.length, streamLimit: exact.length - 1),
        _failedWith<ResponseLimitError>(),
      );
      expect(
        () =>
            ProviderHttpClient(
              baseUrl: Uri.parse('https://example.test/'),
              client: _ResponseClient(
                () => http.StreamedResponse(const Stream.empty(), 200),
              ),
            ).sendSse<SseEvent>(
              ProviderHttpRequest(method: 'GET', path: 'stream'),
              createProtocol: _PassthroughProtocol.new,
              decodedEventCapacity: 0,
            ),
        throwsArgumentError,
      );
    });

    test('stops decoding a large chunk when bounded output backpressures', () async {
      final firstDelivered = Completer<void>();
      final release = Completer<void>();
      final protocol = _CountingProtocol();
      var upstreamPauses = 0;
      var upstreamResumes = 0;
      final source = StreamController<List<int>>(
        sync: true,
        onListen: () {},
        onPause: () => upstreamPauses++,
        onResume: () => upstreamResumes++,
      );
      final client = ProviderHttpClient(
        baseUrl: Uri.parse('https://example.test/'),
        client: _ResponseClient(() => http.StreamedResponse(source.stream, 200)),
      );
      addTearDown(client.close);
      final consumed = client
          .sendSse<int>(
            ProviderHttpRequest(method: 'GET', path: 'stream'),
            createProtocol: () => protocol,
            decodedEventCapacity: 2,
          )
          .runForEach(
            (value) => Effect.tryFuture<void, AiError>(
              () async {
                if (!firstDelivered.isCompleted) {
                  firstDelivered.complete();
                  await release.future;
                }
              },
              onError: (error, _) => TransportError(
                '$error',
                deliveryState: RequestDeliveryState.responseStarted,
              ),
            ),
          )
          .runFutureExit();
      await _waitForListener(source);
      source.add(utf8.encode(List.generate(100, (index) => 'data: $index\n\n').join()));
      await firstDelivered.future;
      await Future<void>.delayed(Duration.zero);

      expect(upstreamPauses, greaterThan(0));
      expect(protocol.decoded, lessThanOrEqualTo(3));

      release.complete();
      await source.close().timeout(
        const Duration(seconds: 2),
        onTimeout: () => throw StateError(
          'source stayed paused: decoded=${protocol.decoded}, pauses=$upstreamPauses, '
          'resumes=$upstreamResumes',
        ),
      );
      final exit = await consumed.timeout(const Duration(seconds: 2));
      if (exit case Failed<void, AiError>(cause: Defect(:final error, :final stackTrace))) {
        Error.throwWithStackTrace(error, stackTrace);
      }
      expect(exit, isA<Succeeded<void, AiError>>());
      expect(protocol.decoded, 100);
    });

    test('cleans transport before emitting a terminal value', () async {
      var sourceCancelled = false;
      final source = StreamController<List<int>>(
        onListen: () {},
        onCancel: () => sourceCancelled = true,
      );
      final protocol = _TerminalProtocol(() => sourceCancelled);
      final client = ProviderHttpClient(
        baseUrl: Uri.parse('https://example.test/'),
        client: _ResponseClient(() => http.StreamedResponse(source.stream, 200)),
      );
      addTearDown(client.close);
      final collected = client
          .sendSse<String>(
            ProviderHttpRequest(method: 'GET', path: 'stream'),
            createProtocol: () => protocol,
          )
          .runCollect()
          .runFuture();
      await _waitForListener(source);
      source.add(utf8.encode('data: done\n\n'));

      expect(await collected.timeout(const Duration(seconds: 2)), ['final']);
      expect(protocol.cleanupObserved, isTrue);
      expect(sourceCancelled, isTrue);
    });

    test('fails premature EOF without fabricating a terminal value', () async {
      final client = ProviderHttpClient(
        baseUrl: Uri.parse('https://example.test/'),
        client: _ResponseClient(
          () => http.StreamedResponse(Stream.value(utf8.encode('data: partial\n\n')), 200),
        ),
      );
      addTearDown(client.close);

      final exit = await client
          .sendSse<String>(
            ProviderHttpRequest(method: 'GET', path: 'stream'),
            createProtocol: _RequiresTerminalProtocol.new,
          )
          .runCollect()
          .runFutureExit();

      expect(exit, _failedWith<ProtocolError>());
    });

    test('early consumers and parent interruption clean loopback bodies and allow reuse', () async {
      var streamRequests = 0;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        if (request.uri.path == '/next') {
          request.response.write('{}');
          await request.response.close();
          return;
        }
        streamRequests++;
        request.response.bufferOutput = false;
        request.response
          ..headers.contentType = ContentType('text', 'event-stream')
          ..write('data: value\n\n');
        await request.response.flush();
      });
      final client = ProviderHttpClient(
        baseUrl: Uri.parse('http://${server.address.address}:${server.port}/'),
      );
      addTearDown(client.close);
      Flow<String, AiError> stream([void Function()? decoded]) => client.sendSse<String>(
        ProviderHttpRequest(method: 'GET', path: 'stream'),
        createProtocol: () => _NotifyingProtocol(decoded),
      );

      expect(
        await stream().runFirst().runFuture().timeout(
          const Duration(seconds: 2),
          onTimeout: () => throw StateError('runFirst cleanup did not complete'),
        ),
        isA<Some<String>>(),
      );

      final subscribed = Completer<void>();
      final subscription = stream().subscribe((_) {
        subscribed.complete();
        return Effect.succeed(null);
      });
      await subscribed.future;
      await subscription.cancel().timeout(const Duration(seconds: 2));

      final decoded = Completer<void>();
      final runtime = Runtime();
      addTearDown(runtime.close);
      final fiber = runtime.fork(stream(decoded.complete).runDrain());
      await decoded.future;
      final interrupted = await fiber
          .interrupt('parent stopped')
          .timeout(
            const Duration(seconds: 2),
          );

      final next = await client
          .sendJson(
            ProviderHttpRequest(method: 'GET', path: 'next'),
            providerId: 'fixture',
            api: 'responses',
            modelId: 'model-1',
          )
          .runFuture()
          .timeout(const Duration(seconds: 2));
      expect((interrupted as Failed<void, AiError>).cause.containsInterruption, isTrue);
      expect(streamRequests, 3);
      expect(next.metadata.statusCode, 200);
    });

    test('provider close releases a backpressured stream and preserves interruption', () async {
      final firstDelivered = Completer<void>();
      final releaseConsumer = Completer<void>();
      final listening = Completer<void>();
      var bodyCancelled = false;
      final protocol = _BurstProtocol(100);
      final body = StreamController<List<int>>(
        sync: true,
        onListen: listening.complete,
        onCancel: () => bodyCancelled = true,
      );
      final client = ProviderHttpClient(
        baseUrl: Uri.parse('https://example.test/'),
        client: _ResponseClient(() => http.StreamedResponse(body.stream, 200)),
      );
      final runtime = Runtime();
      addTearDown(runtime.close);
      final fiber = runtime.fork(
        client
            .sendSse<int>(
              ProviderHttpRequest(method: 'GET', path: 'stream'),
              createProtocol: () => protocol,
              decodedEventCapacity: 1,
            )
            .runForEach(
              (_) => Effect.build(($) async {
                if (!firstDelivered.isCompleted) {
                  firstDelivered.complete();
                  await releaseConsumer.future;
                }
              }),
            ),
      );
      await listening.future;
      body.add(utf8.encode('data: burst\n\n'));
      await firstDelivered.future;
      await Future<void>.delayed(Duration.zero);

      expect(protocol.produced, lessThanOrEqualTo(3));

      await client.close().timeout(const Duration(seconds: 2));
      releaseConsumer.complete();
      final exit = await fiber.join();

      expect((exit as Failed<void, AiError>).cause.containsInterruption, isTrue);
      expect(bodyCancelled, isTrue);
    });

    test('keeps unexpected protocol exceptions as defects', () async {
      Future<Exit<List<String>, AiError>> run(_DefectPhase phase) {
        final client = ProviderHttpClient(
          baseUrl: Uri.parse('https://example.test/'),
          client: _ResponseClient(
            () => http.StreamedResponse(
              Stream.value(utf8.encode('data: value\n\n')),
              200,
            ),
          ),
        );
        addTearDown(client.close);
        return client
            .sendSse<String>(
              ProviderHttpRequest(method: 'GET', path: 'stream'),
              createProtocol: () => _DefectProtocol(phase),
            )
            .runCollect()
            .runFutureExit();
      }

      for (final phase in _DefectPhase.values) {
        final exit = await run(phase);
        final cause = (exit as Failed<List<String>, AiError>).cause;
        expect(cause.containsFatal, isTrue, reason: phase.name);
        expect(cause.expectedErrors, isEmpty, reason: phase.name);
      }
    });

    test('releases an acquired body when protocol start is defective', () async {
      var bodyCancelled = false;
      final body = StreamController<List<int>>(
        sync: true,
        onListen: () {},
        onCancel: () => bodyCancelled = true,
      );
      final client = ProviderHttpClient(
        baseUrl: Uri.parse('https://example.test/'),
        client: _ResponseClient(() => http.StreamedResponse(body.stream, 200)),
      );

      final exit = await client
          .sendSse<String>(
            ProviderHttpRequest(method: 'GET', path: 'stream'),
            createProtocol: () => _DefectProtocol(_DefectPhase.start),
          )
          .runCollect()
          .runFutureExit();
      await client.close();

      expect((exit as Failed<List<String>, AiError>).cause.containsFatal, isTrue);
      expect(bodyCancelled, isTrue);
    });

    test('retains a cleanup defect after early successful observation', () async {
      final body = StreamController<List<int>>(
        onListen: () {},
        onCancel: () => throw StateError('cleanup failed'),
      );
      final client = ProviderHttpClient(
        baseUrl: Uri.parse('https://example.test/'),
        client: _ResponseClient(() => http.StreamedResponse(body.stream, 200)),
      );
      addTearDown(client.close);
      final first = client
          .sendSse<String>(
            ProviderHttpRequest(method: 'GET', path: 'stream'),
            createProtocol: _RequiresTerminalProtocol.new,
          )
          .runFirst()
          .runFutureExit();
      await _waitForListener(body);
      body.add(utf8.encode('data: observed\n\n'));

      final exit = await first;

      expect((exit as Failed<Object?, AiError>).cause.containsFatal, isTrue);
    });
  });
}

Matcher _failedWith<E extends AiError>() => isA<Failed<Object?, AiError>>().having(
  (failure) => failure.cause.expectedErrors,
  'expected errors',
  contains(isA<E>()),
);

Future<void> _waitForListener(StreamController<Object?> controller) async {
  while (!controller.hasListener) {
    await Future<void>.delayed(Duration.zero);
  }
}

final class _ResponseClient extends http.BaseClient {
  _ResponseClient(this.response);

  final http.StreamedResponse Function() response;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async => response();
}

final class _PassthroughProtocol implements SseProtocol<SseEvent> {
  @override
  bool get isTerminal => false;

  @override
  Object? get partialOutput => null;

  @override
  Iterable<SseEvent> start(ResponseMetadata metadata) => const [];

  @override
  Iterable<SseEvent> decode(SseEvent event) => [event];

  @override
  Iterable<SseEvent> finish() => const [];
}

final class _CountingProtocol implements SseProtocol<int> {
  int decoded = 0;

  @override
  bool get isTerminal => false;

  @override
  Object? get partialOutput => null;

  @override
  Iterable<int> start(ResponseMetadata metadata) => const [];

  @override
  Iterable<int> decode(SseEvent event) => [++decoded];

  @override
  Iterable<int> finish() => const [];
}

final class _BurstProtocol implements SseProtocol<int> {
  _BurstProtocol(this.count);

  final int count;
  int produced = 0;

  @override
  bool get isTerminal => false;

  @override
  Object? get partialOutput => null;

  @override
  Iterable<int> start(ResponseMetadata metadata) => const [];

  @override
  Iterable<int> decode(SseEvent event) sync* {
    for (var index = 0; index < count; index++) {
      produced++;
      yield index;
    }
  }

  @override
  Iterable<int> finish() => const [];
}

enum _DefectPhase { start, decode, finish }

final class _DefectProtocol implements SseProtocol<String> {
  _DefectProtocol(this.phase);

  final _DefectPhase phase;

  @override
  bool get isTerminal => phase == _DefectPhase.finish;

  @override
  Object? get partialOutput => null;

  @override
  Iterable<String> start(ResponseMetadata metadata) {
    if (phase == _DefectPhase.start) throw StateError('start defect');
    return const [];
  }

  @override
  Iterable<String> decode(SseEvent event) {
    if (phase == _DefectPhase.decode) throw StateError('decode defect');
    return const [];
  }

  @override
  Iterable<String> finish() {
    if (phase == _DefectPhase.finish) throw StateError('finish defect');
    return const [];
  }
}

final class _TerminalProtocol implements SseProtocol<String> {
  _TerminalProtocol(this.isClean);

  final bool Function() isClean;
  bool terminal = false;
  bool cleanupObserved = false;

  @override
  bool get isTerminal => terminal;

  @override
  Object? get partialOutput => null;

  @override
  Iterable<String> start(ResponseMetadata metadata) => const [];

  @override
  Iterable<String> decode(SseEvent event) {
    terminal = event.data == 'done';
    return const [];
  }

  @override
  Iterable<String> finish() {
    cleanupObserved = isClean();
    return const ['final'];
  }
}

final class _RequiresTerminalProtocol implements SseProtocol<String> {
  @override
  bool get isTerminal => false;

  @override
  Object? get partialOutput => 'partial';

  @override
  Iterable<String> start(ResponseMetadata metadata) => const [];

  @override
  Iterable<String> decode(SseEvent event) => [event.data];

  @override
  Iterable<String> finish() => throw const ProtocolError(
    'The response ended before a recognized terminal event.',
    partialOutput: 'partial',
  );
}

final class _NotifyingProtocol implements SseProtocol<String> {
  _NotifyingProtocol(this.notify);

  final void Function()? notify;

  @override
  bool get isTerminal => false;

  @override
  Object? get partialOutput => null;

  @override
  Iterable<String> start(ResponseMetadata metadata) => const [];

  @override
  Iterable<String> decode(SseEvent event) {
    notify?.call();
    return [event.data];
  }

  @override
  Iterable<String> finish() => throw const ProtocolError('unexpected EOF');
}
