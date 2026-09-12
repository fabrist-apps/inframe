import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/json.dart';
import 'package:artificer_core/transport.dart';
import 'package:artificer_google/src/generate_content/generate_content_models.dart';
import 'package:artificer_google/src/interactions/interaction_models.dart';
import 'package:artificer_google/src/interactions/interactions_resource.dart';
import 'package:conflux/conflux.dart';
import 'package:test/test.dart';

void main() {
  group('GoogleInteractionsResource', () {
    test('performs one explicit request for each lifecycle operation', () async {
      final requests = <_RecordedRequest>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        final body = await utf8.decoder.bind(request).join();
        requests.add(
          _RecordedRequest(
            request.method,
            request.uri.toString(),
            request.headers.value('x-goog-api-key'),
            body.isEmpty ? null : jsonDecode(body) as Map<String, Object?>,
          ),
        );
        switch ((request.method, request.uri.path)) {
          case ('POST', '/v1/interactions'):
            _json(request, _requiresAction);
          case ('GET', '/v1/interactions/job%201'):
            _json(request, _failed);
          case ('POST', '/v1/interactions/job%201/cancel'):
            _json(request, _cancelled);
          case ('DELETE', '/v1/interactions/job%201'):
            request.response.statusCode = HttpStatus.ok;
          default:
            request.response.statusCode = HttpStatus.notFound;
        }
        await request.response.close();
      });
      final client = _client(server);
      addTearDown(client.close);
      final interactions = GoogleInteractionsResource(client);
      final createRequest = GoogleInteractionRequest(
        model: 'gemini-future',
        input: GoogleInteractionInput.text('Call the weather tool.'),
        generationConfig: GoogleInteractionGenerationConfig(
          maxOutputTokens: 200,
          thinkingLevel: 'low',
        ),
        previousInteractionId: 'previous-id',
        responseFormats: [
          GoogleInteractionResponseFormat(
            type: 'text',
            mimeType: 'application/json',
            schema: JsonObject({'type': 'object'}),
          ),
        ],
        safetySettings: [
          GoogleSafetySetting(
            category: 'HARM_CATEGORY_HARASSMENT',
            threshold: 'BLOCK_MEDIUM_AND_ABOVE',
          ),
        ],
        tools: [
          GoogleInteractionTool.function(
            name: 'weather',
            parameters: JsonObject({'type': 'object'}),
          ),
          GoogleInteractionTool.googleSearch(),
        ],
        extraBody: JsonObject({'future_request': true}),
      );

      final created = await interactions.create(createRequest).runFuture();
      final retrieved = await interactions.retrieve('job 1').runFuture();
      final cancelled = await interactions.cancel('job 1').runFuture();
      final deleted = await interactions.delete('job 1').runFuture();

      expect(created.value.status, GoogleInteractionStatus.requiresAction);
      expect(created.value.previousInteractionId, 'previous-id');
      expect(created.value.steps![0].owner, ToolExecutionOwner.caller);
      expect(created.value.steps![1].owner, ToolExecutionOwner.provider);
      expect(created.value.steps![2].owner, isNull);
      expect(created.value.steps![2], isA<GoogleUnknownInteractionStep>());
      expect(created.value.steps![2].extensions.toDart(), {'future': true});
      expect(created.value.extensions.toDart()['future_response'], {'keep': true});
      expect(retrieved.value.status, GoogleInteractionStatus.failed);
      expect(retrieved.value.errors!.single.code, 'backend_error');
      expect(cancelled.value.status, GoogleInteractionStatus.cancelled);
      expect(deleted.value, isA<GoogleInteractionDeleteResult>());
      expect(deleted.value.raw.toDart(), isEmpty);
      expect(deleted.metadata.statusCode, HttpStatus.ok);
      expect(requests, hasLength(4));
      expect(
        requests.map((request) => '${request.method} ${request.path}'),
        [
          'POST /v1/interactions',
          'GET /v1/interactions/job%201',
          'POST /v1/interactions/job%201/cancel',
          'DELETE /v1/interactions/job%201',
        ],
      );
      expect(requests, everyElement(predicate<_RecordedRequest>((r) => r.apiKey == 'secret')));
      expect(requests.first.body, {
        'future_request': true,
        'model': 'gemini-future',
        'input': 'Call the weather tool.',
        'generation_config': {'max_output_tokens': 200, 'thinking_level': 'low'},
        'previous_interaction_id': 'previous-id',
        'response_format': {
          'type': 'text',
          'mime_type': 'application/json',
          'schema': {'type': 'object'},
        },
        'safety_settings': [
          {
            'category': 'HARM_CATEGORY_HARASSMENT',
            'threshold': 'BLOCK_MEDIUM_AND_ABOVE',
          },
        ],
        'tools': [
          {
            'type': 'function',
            'name': 'weather',
            'parameters': {'type': 'object'},
          },
          {'type': 'google_search'},
        ],
      });
      final unknownTool = GoogleInteractionTool.fromJson(
        JsonObject({'type': 'future_tool', 'configuration': 1}),
      );
      expect(unknownTool, isA<GoogleUnknownInteractionTool>());
      expect(unknownTool.owner, isNull);
      expect(unknownTool.toJson().toDart(), {
        'type': 'future_tool',
        'configuration': 1,
      });
    });

    test('validates typed collisions and rejects streaming on create', () async {
      expect(
        () => GoogleInteractionRequest(
          model: 'model',
          input: GoogleInteractionInput.text('hello'),
          extraBody: JsonObject({'model': 'other'}),
        ),
        throwsArgumentError,
      );
      expect(
        () => GoogleInteractionTool.function(
          name: 'tool',
          extensions: JsonObject({'name': 'other'}),
        ),
        throwsArgumentError,
      );

      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      var requests = 0;
      server.listen((request) async {
        requests++;
        await request.drain<void>();
        _json(request, _requiresAction);
        await request.response.close();
      });
      final client = _client(server);
      addTearDown(client.close);
      final exit = await GoogleInteractionsResource(client)
          .create(
            GoogleInteractionRequest(
              model: 'model',
              input: GoogleInteractionInput.text('hello'),
              stream: true,
            ),
          )
          .runFutureExit();

      expect(exit, isA<Failed<NativeResponse<GoogleInteraction>, AiError>>());
      expect(
        (exit as Failed<NativeResponse<GoogleInteraction>, AiError>).cause.expectedErrors.single,
        isA<UnsupportedFeatureError>(),
      );
      expect(requests, 0);
    });

    test('keeps repeated and concurrent executions lazy and independent', () async {
      var requests = 0;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        requests++;
        await request.drain<void>();
        _json(request, _requiresAction);
        await request.response.close();
      });
      final client = _client(server);
      addTearDown(client.close);
      final interactions = GoogleInteractionsResource(client);
      final operation = interactions.create(
        GoogleInteractionRequest(
          model: 'gemini-future',
          input: GoogleInteractionInput.text('hello'),
        ),
      );

      expect(requests, 0);
      final results = await Future.wait([operation.runFuture(), operation.runFuture()]);

      expect(results, hasLength(2));
      expect(requests, 2);
    });

    test('caller interruption and client close cancel in-flight work', () async {
      final firstReceived = Completer<void>();
      final secondReceived = Completer<void>();
      var requests = 0;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        await request.drain<void>();
        requests++;
        (requests == 1 ? firstReceived : secondReceived).complete();
      });
      final client = _client(server);
      final runtime = Runtime();
      addTearDown(runtime.close);
      addTearDown(client.close);
      final interactions = GoogleInteractionsResource(client);
      final operation = interactions.retrieve('slow');

      final callerCancelled = runtime.fork(operation);
      await firstReceived.future;
      final callerExit = await callerCancelled
          .interrupt('caller stopped waiting')
          .timeout(const Duration(seconds: 2));
      final closeCancelled = runtime.fork(operation);
      await secondReceived.future;
      await client.close().timeout(const Duration(seconds: 2));
      final closeExit = await closeCancelled.join().timeout(const Duration(seconds: 2));

      expect(
        (callerExit as Failed<Object?, AiError>).cause.containsInterruption,
        isTrue,
      );
      expect(
        (closeExit as Failed<Object?, AiError>).cause.containsInterruption,
        isTrue,
      );
      expect(await operation.runFutureExit(), _failedWith<ClientClosedError>());
    });
  });
}

Matcher _failedWith<E extends AiError>() => isA<Failed<Object?, AiError>>().having(
  (failure) => failure.cause,
  'cause',
  isA<Expected<AiError>>().having(
    (expected) => expected.error,
    'error',
    isA<E>(),
  ),
);

ProviderHttpClient _client(HttpServer server) => ProviderHttpClient(
  baseUrl: Uri.parse('http://${server.address.address}:${server.port}'),
  headers: {'x-goog-api-key': 'secret'},
);

void _json(HttpRequest request, Map<String, Object?> body) {
  request.response
    ..headers.contentType = ContentType.json
    ..write(jsonEncode(body));
}

final class _RecordedRequest {
  const _RecordedRequest(this.method, this.path, this.apiKey, this.body);
  final String method;
  final String path;
  final String? apiKey;
  final Map<String, Object?>? body;
}

const _requiresAction = <String, Object?>{
  'id': 'job 1',
  'model': 'gemini-future',
  'previous_interaction_id': 'previous-id',
  'status': 'requires_action',
  'steps': [
    {
      'type': 'function_call',
      'id': 'call-1',
      'name': 'weather',
      'arguments': {'city': 'Paris'},
    },
    {
      'type': 'google_search_result',
      'call_id': 'search-1',
      'result': [
        {'title': 'Result', 'url': 'https://example.com'},
      ],
    },
    {'type': 'future_step', 'future': true},
  ],
  'future_response': {'keep': true},
};

const _failed = <String, Object?>{
  'id': 'job 1',
  'status': 'failed',
  'errors': [
    {'code': 'backend_error', 'message': 'The interaction failed.'},
  ],
};

const _cancelled = <String, Object?>{'id': 'job 1', 'status': 'cancelled'};
