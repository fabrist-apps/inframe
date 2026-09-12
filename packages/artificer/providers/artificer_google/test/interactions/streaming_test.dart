import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/transport.dart';
import 'package:artificer_google/src/interactions/interaction_events.dart';
import 'package:artificer_google/src/interactions/interaction_models.dart';
import 'package:artificer_google/src/interactions/interactions_resource.dart';
import 'package:conflux/conflux.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

void main() {
  group('Google Interactions streaming', () {
    test('streams create events from one fresh POST per run', () async {
      final requests = <_Request>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        requests.add(await _record(request));
        request.response
          ..bufferOutput = false
          ..headers.contentType = ContentType('text', 'event-stream');
        await _writeSplitEvents(request.response, [
          _created,
          _stepStart,
          _textDelta,
          _providerDelta,
          _unknown,
          _stepStop,
          _completed,
        ]);
        request.response.write('data: [DONE]\n\n');
        await request.response.close();
      });
      final client = _client(server);
      addTearDown(client.close);
      final operation = GoogleInteractionsResource(client).stream(
        GoogleInteractionRequest(
          model: 'gemini-future',
          input: GoogleInteractionInput.text('hello'),
          stream: false,
        ),
      );

      final first = await operation.runCollect().runFuture();
      final second = await operation.runCollect().runFuture();

      expect(requests, hasLength(2));
      expect(requests.map((request) => '${request.method} ${request.uri}'), [
        'POST /v1/interactions',
        'POST /v1/interactions',
      ]);
      expect(requests, everyElement(predicate<_Request>((value) => value.apiKey == 'secret')));
      expect(
        requests,
        everyElement(predicate<_Request>((value) => value.accept == 'text/event-stream')),
      );
      expect(requests.first.body, {
        'model': 'gemini-future',
        'input': 'hello',
        'stream': true,
      });
      expect(first, hasLength(7));
      expect(second, hasLength(7));
      expect(first[0], isA<GoogleInteractionCreatedEvent>());
      expect((first[0] as GoogleInteractionCreatedEvent).interaction.id, 'interaction-1');
      expect(first[1], isA<GoogleInteractionStepStartEvent>());
      expect((first[1] as GoogleInteractionStepStartEvent).step.owner, isNull);
      expect(first[2], isA<GoogleInteractionStepDeltaEvent>());
      expect((first[2] as GoogleInteractionStepDeltaEvent).delta.text, 'Hel');
      expect(first[3], isA<GoogleInteractionStepDeltaEvent>());
      expect(
        (first[3] as GoogleInteractionStepDeltaEvent).delta.owner,
        ToolExecutionOwner.provider,
      );
      expect(first[4], isA<GoogleUnknownInteractionEvent>());
      expect(first[4].extensions.toDart()['future'], {'keep': true});
      expect((first[5] as GoogleInteractionStepStopEvent).usage!.totalTokens, 4);
      expect(first.last, isA<GoogleInteractionCompletedEvent>());
      expect(first.last.eventId, 'event-7');
      expect(first.last.sseId, 'sse-event-7');
    });

    test('retrieves and resumes only from caller-supplied query cursors', () async {
      final requests = <_Request>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        requests.add(await _record(request));
        request.response.headers.contentType = ContentType('text', 'event-stream');
        _writeEvents(request.response, [_requiresAction]);
        request.response.write('data: [DONE]\n\n');
        await request.response.close();
      });
      final client = _client(server);
      addTearDown(client.close);
      final interactions = GoogleInteractionsResource(client);

      final initial = await interactions.streamRetrieve('job 1').runCollect().runFuture();
      final resumed = await interactions
          .streamRetrieve('job 1', lastEventId: 'event / 9')
          .runCollect()
          .runFuture();

      expect(initial.single, isA<GoogleInteractionStatusEvent>());
      expect(
        (initial.single as GoogleInteractionStatusEvent).status,
        GoogleInteractionStatus.requiresAction,
      );
      expect(resumed.single.eventId, 'event-8');
      expect(requests.map((request) => '${request.method} ${request.uri}'), [
        'GET /v1/interactions/job%201?stream=true',
        'GET /v1/interactions/job%201?stream=true&last_event_id=event+%2F+9',
      ]);
    });

    test('fails malformed, premature, oversized, and service-error streams', () async {
      Future<Object> run(String body, {int maxEventBytes = 1024}) async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        server.listen((request) async {
          await request.drain<void>();
          request.response
            ..headers.contentType = ContentType('text', 'event-stream')
            ..headers.set('x-request-id', 'interaction-stream-request')
            ..write(body);
          await request.response.close();
        });
        final client = _client(server);
        addTearDown(client.close);
        return GoogleInteractionsResource(client)
            .streamRetrieve('id', maxEventBytes: maxEventBytes)
            .runCollect()
            .runFutureExit();
      }

      expect(await run('data: {bad}\n\n'), _failedWith<ProtocolError>());
      final premature = await run('data: ${jsonEncode(_unknown)}\n\n');
      expect(premature, _failedWith<ProtocolError>());
      final prematureError = _expected(premature) as ProtocolError;
      expect(
        prematureError.partialOutput,
        isA<List<GoogleInteractionEvent>>().having(
          (events) => events.single,
          'unknown event',
          isA<GoogleUnknownInteractionEvent>(),
        ),
      );
      final service = await run(
        'data: ${jsonEncode(_created)}\n\n'
        'retry: 250\n'
        'data: ${jsonEncode(_error)}\n\n',
      );
      expect(service, _failedWith<ProviderError>());
      final serviceError = _expected(service) as ProviderError;
      expect(serviceError.statusCode, HttpStatus.ok);
      expect(serviceError.code, 'backend_error');
      expect(serviceError.requestId, 'interaction-stream-request');
      expect(serviceError.retryAfter, const Duration(milliseconds: 250));
      expect(serviceError.details!.toDart(), _error);
      expect(
        serviceError.partialOutput,
        isA<List<GoogleInteractionEvent>>().having(
          (events) => events.length,
          'event count',
          2,
        ),
      );
      expect(
        await run('data: ${jsonEncode(_completed)}\n\n', maxEventBytes: 20),
        _failedWith<ResponseLimitError>(),
      );
    });

    test('accepts every terminal status followed by DONE', () async {
      for (final status in [
        'completed',
        'failed',
        'cancelled',
        'requires_action',
        'incomplete',
      ]) {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        server.listen((request) async {
          await request.drain<void>();
          request.response.headers.contentType = ContentType('text', 'event-stream');
          _writeEvents(request.response, [
            {
              'event_type': 'interaction.status_update',
              'event_id': status,
              'interaction_id': 'interaction-1',
              'status': status,
            },
          ]);
          request.response.write('data: [DONE]\n\n');
          await request.response.close();
        });
        final client = _client(server);
        addTearDown(client.close);

        final events = await GoogleInteractionsResource(client)
            .streamRetrieve('interaction-1')
            .runCollect()
            .runFuture();

        expect(events.single, isA<GoogleInteractionStatusEvent>());
      }
    });

    test('rejects a terminal event without the documented DONE sentinel', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        await request.drain<void>();
        request.response.headers.contentType = ContentType('text', 'event-stream');
        _writeEvents(request.response, [
          {
            'event_type': 'interaction.status_update',
            'event_id': 'terminal',
            'interaction_id': 'interaction-1',
            'status': 'completed',
          },
        ]);
        await request.response.close();
      });
      final client = _client(server);
      addTearDown(client.close);

      final exit = await GoogleInteractionsResource(client)
          .streamRetrieve('interaction-1')
          .runCollect()
          .runFutureExit();

      expect(exit, _failedWith<ProtocolError>());
    });

    test('early stop and close cancel bodies without closing a borrowed client', () async {
      final streamStarted = Completer<void>();
      final secondStarted = Completer<void>();
      var streams = 0;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        if (request.uri.path == '/health') {
          request.response.write('ok');
          await request.response.close();
          return;
        }
        await request.drain<void>();
        streams++;
        request.response
          ..bufferOutput = false
          ..headers.contentType = ContentType('text', 'event-stream')
          ..write('data: ${jsonEncode(_created)}\n\n');
        await request.response.flush();
        (streams == 1 ? streamStarted : secondStarted).complete();
      });
      final borrowed = http.Client();
      addTearDown(borrowed.close);
      final client = ProviderHttpClient(
        baseUrl: _baseUrl(server),
        headers: {'x-goog-api-key': 'secret'},
        client: borrowed,
      );
      final interactions = GoogleInteractionsResource(client);
      final first = interactions.streamRetrieve('id').runFirst().runFuture();
      await streamStarted.future;
      expect(await first.timeout(const Duration(seconds: 2)), isA<Some<GoogleInteractionEvent>>());
      final runtime = Runtime();
      addTearDown(runtime.close);
      final active = runtime.fork(interactions.streamRetrieve('id').runDrain());
      await secondStarted.future;

      await client.close().timeout(const Duration(seconds: 2));
      final exit = await active.join().timeout(const Duration(seconds: 2));
      final health = await borrowed.get(_baseUrl(server).resolve('/health'));

      expect((exit as Failed<Object?, AiError>).cause.containsInterruption, isTrue);
      expect(health.body, 'ok');
      expect(streams, 2);
    });

    test('caller interruption before headers sends no recovery request', () async {
      final received = Completer<void>();
      var requests = 0;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        requests++;
        await request.drain<void>();
        received.complete();
      });
      final client = _client(server);
      addTearDown(client.close);
      final runtime = Runtime();
      addTearDown(runtime.close);
      final active = runtime.fork(
        GoogleInteractionsResource(client).streamRetrieve('id').runDrain(),
      );
      await received.future;

      final exit = await active
          .interrupt('caller stopped waiting')
          .timeout(const Duration(seconds: 2));

      expect((exit as Failed<Object?, AiError>).cause.containsInterruption, isTrue);
      expect(requests, 1);
    });
  });
}

AiError _expected(Object exit) =>
    ((exit as Failed<Object?, AiError>).cause as Expected<AiError>).error;

Matcher _failedWith<E extends AiError>() => isA<Failed<Object?, AiError>>().having(
  (failure) => failure.cause,
  'cause',
  isA<Expected<AiError>>().having((expected) => expected.error, 'error', isA<E>()),
);

ProviderHttpClient _client(HttpServer server) => ProviderHttpClient(
  baseUrl: _baseUrl(server),
  headers: {'x-goog-api-key': 'secret'},
);

Uri _baseUrl(HttpServer server) => Uri.parse('http://${server.address.address}:${server.port}');

Future<_Request> _record(HttpRequest request) async {
  final body = await utf8.decoder.bind(request).join();
  return _Request(
    request.method,
    request.uri.toString(),
    request.headers.value('x-goog-api-key'),
    request.headers.value('accept'),
    body.isEmpty ? null : jsonDecode(body) as Map<String, Object?>,
  );
}

void _writeEvents(HttpResponse response, Iterable<Map<String, Object?>> events) {
  for (final (index, event) in events.indexed) {
    response.write(
      'event: ${event['event_type']}\nid: sse-event-${index + 1}\n'
      'data: ${jsonEncode(event)}\n\n',
    );
  }
}

Future<void> _writeSplitEvents(
  HttpResponse response,
  Iterable<Map<String, Object?>> events,
) async {
  for (final (index, event) in events.indexed) {
    final bytes = utf8.encode(
      'event: ${event['event_type']}\nid: sse-event-${index + 1}\n'
      'data: ${jsonEncode(event)}\n\n',
    );
    final split = bytes.length ~/ 2;
    response.add(bytes.sublist(0, split));
    await response.flush();
    response.add(bytes.sublist(split));
    await response.flush();
  }
}

final class _Request {
  const _Request(this.method, this.uri, this.apiKey, this.accept, this.body);
  final String method;
  final String uri;
  final String? apiKey;
  final String? accept;
  final Map<String, Object?>? body;
}

const _created = <String, Object?>{
  'event_type': 'interaction.created',
  'event_id': 'event-1',
  'interaction': {
    'id': 'interaction-1',
    'model': 'gemini-future',
    'status': 'in_progress',
  },
};

const _stepStart = <String, Object?>{
  'event_type': 'step.start',
  'event_id': 'event-2',
  'index': 0,
  'step': {'type': 'model_output'},
};

const _textDelta = <String, Object?>{
  'event_type': 'step.delta',
  'event_id': 'event-3',
  'index': 0,
  'delta': {'type': 'text', 'text': 'Hel'},
};

const _providerDelta = <String, Object?>{
  'event_type': 'step.delta',
  'event_id': 'event-4',
  'index': 1,
  'delta': {
    'type': 'google_search_result',
    'result': [
      {'title': 'Result', 'url': 'https://example.com'},
    ],
    'future_delta': true,
  },
};

const _unknown = <String, Object?>{
  'event_type': 'future.event',
  'event_id': 'event-5',
  'future': {'keep': true},
};

const _stepStop = <String, Object?>{
  'event_type': 'step.stop',
  'event_id': 'event-6',
  'index': 0,
  'usage': {'total_tokens': 4},
};

const _completed = <String, Object?>{
  'event_type': 'interaction.completed',
  'event_id': 'event-7',
  'interaction': {
    'id': 'interaction-1',
    'model': 'gemini-future',
    'status': 'completed',
    'usage': {'total_tokens': 4},
  },
};

const _requiresAction = <String, Object?>{
  'event_type': 'interaction.status_update',
  'event_id': 'event-8',
  'interaction_id': 'interaction-1',
  'status': 'requires_action',
};

const _error = <String, Object?>{
  'event_type': 'error',
  'event_id': 'event-error',
  'error': {'code': 'backend_error', 'message': 'stream failed'},
};
