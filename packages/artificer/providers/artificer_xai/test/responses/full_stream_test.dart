import 'dart:convert';
import 'dart:io';

import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/json.dart';
import 'package:artificer_xai/artificer_xai.dart';
import 'package:conflux/conflux.dart';
import 'package:test/test.dart';

void main() {
  test('interleaved native events assemble the ordinary result with stable parts', () async {
    final server = await _streamServer([
      {'type': 'response.created', 'sequence_number': 0, 'response': _createdResponse},
      {
        'type': 'response.reasoning_summary_text.delta',
        'sequence_number': 1,
        'item_id': 'rs_1',
        'output_index': 0,
        'summary_index': 0,
        'delta': 'Checking ',
      },
      {
        'type': 'response.output_text.delta',
        'sequence_number': 2,
        'item_id': 'msg_1',
        'output_index': 1,
        'content_index': 0,
        'delta': 'Hello',
        'logprobs': <Object?>[],
      },
      {
        'type': 'response.function_call_arguments.delta',
        'sequence_number': 3,
        'item_id': 'fc_1',
        'output_index': 2,
        'delta': '{"city":',
      },
      {
        'type': 'response.reasoning_summary_text.delta',
        'sequence_number': 4,
        'item_id': 'rs_1',
        'output_index': 0,
        'summary_index': 0,
        'delta': 'weather.',
      },
      {
        'type': 'response.output_text.delta',
        'sequence_number': 5,
        'item_id': 'msg_1',
        'output_index': 1,
        'content_index': 0,
        'delta': '.',
        'logprobs': <Object?>[],
      },
      {
        'type': 'response.function_call_arguments.delta',
        'sequence_number': 6,
        'item_id': 'fc_1',
        'output_index': 2,
        'delta': '"Paris"}',
      },
      {
        'type': 'response.future.delta',
        'sequence_number': 7,
        'payload': {'keep': true},
      },
      {'type': 'response.completed', 'sequence_number': 8, 'response': _finalResponse},
    ]);
    final provider = _provider(server);
    addTearDown(provider.close);
    final request = GenerationRequest(
      messages: [UserMessage.text('hello')],
      tools: [
        FunctionTool(name: 'weather', inputSchema: artificerJsonObject({'type': 'object'})),
      ],
    );

    final events = await provider
        .languageModel('grok-future')
        .stream(request)
        .runCollect()
        .runFuture();
    final finished = events.whereType<GenerationFinished>().single.result;
    final native = NativeResponse(
      value: XaiResponse.fromJson(artificerJsonObject(_finalResponse)),
      payload: NativePayload(
        providerId: 'xai',
        api: 'responses',
        modelId: 'grok-future',
        json: artificerJsonObject(_finalResponse),
      ),
      metadata: finished.metadata,
    );
    final ordinary = provider.responses.normalize(native);
    final starts = events.whereType<PartStarted>().toList();

    expect(starts.map((event) => event.partId).toSet(), hasLength(starts.length));
    expect(starts.map((event) => event.kind), [
      GenerationPartKind.reasoning,
      GenerationPartKind.text,
      GenerationPartKind.applicationToolCall,
      GenerationPartKind.providerTool,
    ]);
    expect(
      events.whereType<ReasoningPartDelta>().map((event) => event.text).join(),
      'Checking weather.',
    );
    expect(events.whereType<TextPartDelta>().map((event) => event.text).join(), 'Hello.');
    expect(
      events.whereType<ToolArgumentsPartDelta>().map((event) => event.text).join(),
      '{"city":"Paris"}',
    );
    expect(events.whereType<ProviderEvent>().single.name, 'response.future.delta');
    expect(
      AssistantMessage(finished.message.parts).toJson().toDart(),
      AssistantMessage(ordinary.message.parts).toJson().toDart(),
    );
    expect(finished.usage!.totalTokens, 6);
    expect(finished.message.replay!.items.any((item) => item.phase == 'unknown-event'), isTrue);
  });

  test('native error events fail with partial output and no final result', () async {
    final server = await _streamServer([
      {'type': 'response.created', 'sequence_number': 0, 'response': _createdResponse},
      {
        'type': 'response.output_text.delta',
        'sequence_number': 1,
        'item_id': 'msg_1',
        'output_index': 0,
        'content_index': 0,
        'delta': 'partial',
        'logprobs': <Object?>[],
      },
      {
        'type': 'error',
        'sequence_number': 2,
        'code': 'server_error',
        'message': 'failed',
        'param': null,
      },
    ]);
    final provider = _provider(server);
    addTearDown(provider.close);

    final exit = await provider
        .languageModel('grok-future')
        .stream(GenerationRequest(messages: [UserMessage.text('hello')]))
        .runCollect()
        .runFutureExit();

    expect(
      exit,
      isA<Failed<List<GenerationEvent>, AiError>>().having(
        (failure) => (failure.cause as Expected<AiError>).error,
        'error',
        isA<ProviderError>()
            .having((error) => error.message, 'message', 'failed')
            .having((error) => error.code, 'code', 'server_error')
            .having(
              (error) => (error.partialOutput! as AssistantMessage).text,
              'partial text',
              'partial',
            ),
      ),
    );
  });

  test('response.failed reads the nested native stream error', () async {
    final server = await _streamServer([
      {
        'type': 'response.failed',
        'sequence_number': 0,
        'response': {
          ..._createdResponse,
          'status': 'failed',
          'error': {'code': 'model_error', 'message': 'nested failure'},
        },
      },
    ]);
    final provider = _provider(server);
    addTearDown(provider.close);

    final exit = await provider.responses
        .stream(
          XaiResponseRequest(
            model: 'grok-future',
            input: [XaiResponseInputMessage.userText('hello')],
          ),
        )
        .runCollect()
        .runFutureExit();

    expect(
      exit,
      isA<Failed<List<XaiResponseEvent>, AiError>>().having(
        (failure) => (failure.cause as Expected<AiError>).error,
        'error',
        isA<ProviderError>()
            .having((error) => error.message, 'message', 'nested failure')
            .having((error) => error.code, 'code', 'model_error'),
      ),
    );
  });

  test('stream replay reuses terminal items without submitting unknown events', () async {
    Map<String, Object?>? secondBody;
    var requests = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      requests++;
      final body = jsonDecode(await utf8.decoder.bind(request).join())! as Map<String, Object?>;
      if (requests == 1) {
        request.response.headers.contentType = ContentType('text', 'event-stream');
        request.response
          ..write(
            'data: ${jsonEncode({'type': 'response.future.delta', 'sequence_number': 0})}\n\n',
          )
          ..write(
            'data: ${jsonEncode({'type': 'response.completed', 'sequence_number': 1, 'response': _finalResponse})}\n\n',
          );
      } else {
        secondBody = body;
        request.response
          ..headers.contentType = ContentType.json
          ..write(jsonEncode(_finalResponse));
      }
      await request.response.close();
    });
    final provider = _provider(server);
    addTearDown(provider.close);
    final model = provider.languageModel('grok-future');
    final first = await model
        .stream(GenerationRequest(messages: [UserMessage.text('first')]))
        .runCollect()
        .runFuture();
    final assistant = first.whereType<GenerationFinished>().single.result.message;

    await model
        .generate(
          GenerationRequest(
            messages: [UserMessage.text('first'), assistant, UserMessage.text('second')],
          ),
        )
        .runFuture();

    final input = secondBody!['input']! as List<Object?>;
    expect(input, hasLength(6));
    expect(
      input.whereType<Map<String, Object?>>().any(
        (item) => item['type'] == 'response.future.delta',
      ),
      isFalse,
    );
  });

  test('validates native stream limits before opening a request', () async {
    var requests = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      requests++;
      await request.response.close();
    });
    final provider = _provider(server);
    addTearDown(provider.close);
    final request = XaiResponseRequest(
      model: 'grok-future',
      input: [XaiResponseInputMessage.userText('hello')],
    );

    expect(
      () => provider.responses.stream(request, decodedEventCapacity: 0),
      throwsArgumentError,
    );
    expect(requests, 0);
  });

  test('retained unknown events obey the assembled response limit', () async {
    final server = await _streamServer([
      {
        'type': 'response.future.delta',
        'sequence_number': 0,
        'payload': 'x' * 4096,
      },
      {'type': 'response.completed', 'sequence_number': 1, 'response': _finalResponse},
    ]);
    final provider = _provider(server);
    addTearDown(provider.close);

    final exit = await provider.responses
        .streamCommon(
          XaiResponseRequest(
            model: 'grok-future',
            input: [XaiResponseInputMessage.userText('hello')],
          ),
          maxAssembledBytes: 1024,
        )
        .runCollect()
        .runFutureExit();

    expect(
      exit,
      isA<Failed<List<GenerationEvent>, AiError>>().having(
        (failure) => (failure.cause as Expected<AiError>).error,
        'error',
        isA<ResponseLimitError>()
            .having((error) => error.limit, 'limit', 1024)
            .having((error) => error.actual, 'actual', greaterThan(4096)),
      ),
    );
  });
}

Future<HttpServer> _streamServer(List<Map<String, Object?>> events) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  addTearDown(() => server.close(force: true));
  server.listen((request) async {
    await request.drain<void>();
    request.response.headers.contentType = ContentType('text', 'event-stream');
    for (final event in events) {
      request.response.write('data: ${jsonEncode(event)}\n\n');
    }
    await request.response.close();
  });
  return server;
}

XaiProvider _provider(HttpServer server) => XaiProvider(
  apiKey: 'secret',
  baseUrl: Uri.parse('http://${server.address.address}:${server.port}/v1/'),
);

JsonObject artificerJsonObject(Map<String, Object?> value) => JsonObject.fromDart(value);

const _createdResponse = <String, Object?>{
  'id': 'resp_stream',
  'status': 'in_progress',
  'model': 'grok-future',
  'output': <Object?>[],
};

const _finalResponse = <String, Object?>{
  'id': 'resp_stream',
  'status': 'completed',
  'model': 'grok-future',
  'output': [
    {
      'id': 'rs_1',
      'type': 'reasoning',
      'status': 'completed',
      'summary': [
        {'type': 'summary_text', 'text': 'Checking weather.'},
      ],
      'encrypted_content': 'late-signature',
    },
    {
      'id': 'msg_1',
      'type': 'message',
      'status': 'completed',
      'role': 'assistant',
      'phase': 'final_answer',
      'content': [
        {
          'type': 'output_text',
          'text': 'Hello.',
          'annotations': [
            {'type': 'url_citation', 'url': 'https://example.test/source', 'title': 'Source'},
          ],
        },
      ],
    },
    {
      'id': 'fc_1',
      'type': 'function_call',
      'call_id': 'call_1',
      'name': 'weather',
      'arguments': '{"city":"Paris"}',
      'status': 'completed',
    },
    {
      'id': 'ws_1',
      'type': 'web_search_call',
      'status': 'completed',
      'action': {'type': 'search', 'query': 'weather'},
    },
  ],
  'usage': {'input_tokens': 2, 'output_tokens': 4, 'total_tokens': 6},
};
