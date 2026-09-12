import 'dart:convert';
import 'dart:io';

import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/json.dart';
import 'package:artificer_xai/artificer_xai.dart';
import 'package:conflux/conflux.dart';
import 'package:test/test.dart';

void main() {
  test('native create preserves Xai fields and normalizes an explicit choice', () async {
    Map<String, Object?>? body;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      expect(request.method, 'POST');
      expect(request.uri.path, '/v1/chat/completions');
      body = jsonDecode(await utf8.decoder.bind(request).join())! as Map<String, Object?>;
      request.response
        ..headers.contentType = ContentType.json
        ..headers.set('x-request-id', 'chat-request')
        ..write(jsonEncode(_completion));
      await request.response.close();
    });
    final provider = _provider(server);
    addTearDown(provider.close);
    final request = XaiChatRequest(
      model: 'grok-future',
      messages: [XaiChatMessage.userText('weather')],
      maxCompletionTokens: 100,
      frequencyPenalty: 0.2,
      presencePenalty: -0.1,
      logprobs: true,
      topLogprobs: 4,
      parallelToolCalls: false,
      promptCacheKey: 'conversation-1',
      reasoningEffort: 'medium',
      seed: 7,
      serviceTier: 'priority',
      stop: ['END'],
      user: 'end-user-1',
      responseFormat: JsonObject({
        'type': 'json_schema',
        'json_schema': {
          'name': 'answer',
          'strict': true,
          'schema': {'type': 'object'},
        },
      }),
      tools: [
        XaiChatFunctionTool(
          name: 'weather',
          parameters: JsonObject({'type': 'object'}),
        ),
      ],
    );

    final native = await provider.chatCompletions.create(request).runFuture();
    final ambiguous = provider.chatCompletions.normalize(native);
    final selected = provider.chatCompletions.normalize(native, choiceIndex: 1);
    final refused = provider.chatCompletions.normalize(native, choiceIndex: 0);

    expect(ambiguous, isA<Failure<GenerationResult, AiError>>());
    expect(selected, isA<Success<GenerationResult, AiError>>());
    final result = (selected as Success<GenerationResult, AiError>).value;
    expect(result.finishReason, FinishReason.toolCalls);
    expect(result.message.parts.whereType<ApplicationToolCallPart>().single.name, 'weather');
    expect(
      (refused as Success<GenerationResult, AiError>).value,
      isA<GenerationResult>()
          .having((result) => result.finishReason, 'finish reason', FinishReason.outputLimit)
          .having(
            (result) => result.message.parts.whereType<RefusalPart>().single.text,
            'refusal',
            'Cannot help.',
          ),
    );
    expect(native.value.extensions.toDart()['future'], {'keep': true});
    expect(native.metadata.requestId, 'chat-request');
    expect(body, {
      'model': 'grok-future',
      'messages': [
        {'role': 'user', 'content': 'weather'},
      ],
      'max_completion_tokens': 100,
      'frequency_penalty': 0.2,
      'presence_penalty': -0.1,
      'logprobs': true,
      'top_logprobs': 4,
      'parallel_tool_calls': false,
      'prompt_cache_key': 'conversation-1',
      'reasoning_effort': 'medium',
      'seed': 7,
      'service_tier': 'priority',
      'stop': ['END'],
      'user': 'end-user-1',
      'response_format': request.responseFormat!.toDart(),
      'tools': [
        {
          'type': 'function',
          'function': {
            'name': 'weather',
            'parameters': {'type': 'object'},
            'strict': true,
          },
        },
      ],
      'stream': false,
    });
    expect(
      XaiChatRequest(
        model: 'grok-future',
        messages: [XaiChatMessage.userText('hello')],
        responseFormat: null,
      ).toJson(stream: false).toDart(),
      containsPair('response_format', null),
    );
    expect(
      () => XaiChatRequest(
        model: 'grok-future',
        messages: [XaiChatMessage.userText('hello')],
        extraBody: JsonObject({'messages': <Object?>[]}),
      ),
      throwsArgumentError,
    );
  });

  test('native SSE keeps indexed choices, late tools, usage, and unknown events', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      final body = jsonDecode(await utf8.decoder.bind(request).join())! as Map<String, Object?>;
      expect(body['stream'], isTrue);
      request.response.headers.contentType = ContentType('text', 'event-stream');
      for (final event in _streamEvents) {
        request.response.write('data: ${event is String ? event : jsonEncode(event)}\n\n');
      }
      await request.response.close();
    });
    final provider = _provider(server);
    addTearDown(provider.close);
    final operation = provider.chatCompletions.stream(
      XaiChatRequest(
        model: 'grok-future',
        messages: [XaiChatMessage.userText('weather')],
      ),
    );

    final first = await operation.runCollect().runFuture();
    final second = await operation.runCollect().runFuture();
    final chunks = first.whereType<XaiChatChunk>().toList();

    expect(first.last, isA<XaiChatDone>());
    expect(second.last, isA<XaiChatDone>());
    expect(first.whereType<XaiUnknownChatEvent>(), hasLength(1));
    expect(chunks.expand((chunk) => chunk.choices).map((choice) => choice.index), [0, 1, 1]);
    expect(chunks.last.usage!.totalTokens, 5);
    expect(chunks[1].choices.single.delta.toDart()['tool_calls'], isNotNull);
  });

  test('premature EOF and native error events cannot fabricate success', () async {
    var requests = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      requests++;
      await request.drain<void>();
      request.response.headers.contentType = ContentType('text', 'event-stream');
      if (requests == 1) {
        request.response.write('data: ${jsonEncode(_streamEvents.first)}\n\n');
      } else {
        request.response.write(
          'data: ${jsonEncode({
            'error': {'code': 'chat_failed', 'message': 'Could not finish.'},
          })}\n\n',
        );
      }
      await request.response.close();
    });
    final provider = _provider(server);
    addTearDown(provider.close);
    final operation = provider.chatCompletions.stream(
      XaiChatRequest(
        model: 'grok-future',
        messages: [XaiChatMessage.userText('weather')],
      ),
    );

    final premature = await operation.runCollect().runFutureExit();
    final failed = await operation.runCollect().runFutureExit();

    expect(premature, _failedWith<ProtocolError>());
    expect(failed, _failedWith<ProviderError>());
  });
}

Matcher _failedWith<E extends AiError>() => isA<Failed<Object?, AiError>>().having(
  (failure) => (failure.cause as Expected<AiError>).error,
  'error',
  isA<E>(),
);

XaiProvider _provider(HttpServer server) => XaiProvider(
  apiKey: 'secret',
  baseUrl: Uri.parse('http://${server.address.address}:${server.port}/v1/'),
);

const _completion = <String, Object?>{
  'id': 'chat_1',
  'object': 'chat.completion',
  'created': 123,
  'model': 'grok-future',
  'choices': [
    {
      'index': 0,
      'message': {'role': 'assistant', 'content': 'plain', 'refusal': 'Cannot help.'},
      'finish_reason': 'length',
    },
    {
      'index': 1,
      'message': {
        'role': 'assistant',
        'content': null,
        'tool_calls': [
          {
            'id': 'call_1',
            'type': 'function',
            'function': {'name': 'weather', 'arguments': '{"city":"Paris"}'},
          },
        ],
      },
      'finish_reason': 'tool_calls',
    },
  ],
  'usage': {'prompt_tokens': 2, 'completion_tokens': 3, 'total_tokens': 5},
  'future': {'keep': true},
};

const _streamEvents = <Object?>[
  {
    'id': 'chat_1',
    'object': 'chat.completion.chunk',
    'model': 'grok-future',
    'choices': [
      {
        'index': 0,
        'delta': {'role': 'assistant', 'content': 'plain'},
        'finish_reason': 'stop',
      },
    ],
  },
  {'event': 'future', 'payload': true},
  {
    'id': 'chat_1',
    'object': 'chat.completion.chunk',
    'model': 'grok-future',
    'choices': [
      {
        'index': 1,
        'delta': {
          'tool_calls': [
            {
              'index': 0,
              'function': {'arguments': '{"city":'},
            },
          ],
        },
        'finish_reason': null,
      },
    ],
  },
  {
    'id': 'chat_1',
    'object': 'chat.completion.chunk',
    'model': 'grok-future',
    'choices': [
      {
        'index': 1,
        'delta': {
          'tool_calls': [
            {
              'index': 0,
              'id': 'call_1',
              'type': 'function',
              'function': {'name': 'weather', 'arguments': '"Paris"}'},
            },
          ],
        },
        'finish_reason': 'tool_calls',
      },
    ],
  },
  {
    'id': 'chat_1',
    'object': 'chat.completion.chunk',
    'model': 'grok-future',
    'choices': <Object?>[],
    'usage': {'prompt_tokens': 2, 'completion_tokens': 3, 'total_tokens': 5},
  },
  '[DONE]',
];
