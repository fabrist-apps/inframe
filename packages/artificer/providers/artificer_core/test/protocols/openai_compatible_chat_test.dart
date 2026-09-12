import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/json.dart';
import 'package:artificer_core/protocols.dart';
import 'package:artificer_core/transport.dart';
import 'package:conflux/conflux.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

void main() {
  group('OpenAiCompatibleChatCodec', () {
    test('two typed dialects share one loopback create and authoritative mapper', () async {
      final received = <JsonObject>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        received.add(JsonObject.parse(await utf8.decoder.bind(request).join()));
        request.response
          ..headers.contentType = ContentType.json
          ..write(jsonEncode(_response('answer')));
        await request.response.close();
      });
      final client = ProviderHttpClient(
        baseUrl: Uri.parse('http://${server.address.address}:${server.port}/'),
      );
      addTearDown(client.close);
      final cases = [
        (
          OpenAiCompatibleChatCodec(_Dialect(providerId: 'xai', field: 'search_parameters')),
          const _Options({'mode': 'auto'}),
          'search_parameters',
        ),
        (
          OpenAiCompatibleChatCodec(_Dialect(providerId: 'baseten', field: 'model_adapter')),
          const _Options('adapter-v2'),
          'model_adapter',
        ),
      ];

      for (final (codec, options, _) in cases) {
        final execution = await _executeCreate(
          client,
          codec,
          options,
          _conversation(),
        ).runFuture();
        final mappedAgain = _success(codec.normalize(execution.native));

        expect(execution.native.value.choices.single.message.content, 'answer');
        expect(execution.native.value.extensions.toDart()['provider_marker'], {'keep': true});
        expect(execution.result.toJson().toDart(), mappedAgain.toJson().toDart());
        expect(execution.result.message.parts, [isA<TextOutputPart>()]);
      }

      expect(received, hasLength(2));
      for (var index = 0; index < received.length; index++) {
        final body = received[index].toDart();
        expect(body['n'], 1);
        expect(body['messages'], hasLength(3));
        expect(body[cases[index].$3], cases[index].$2.value);
      }
    });

    test('requires explicit native choice and rejects typed-field collisions', () {
      final codec = OpenAiCompatibleChatCodec(
        _Dialect(providerId: 'xai', field: 'search_parameters'),
      );
      final raw = JsonObject.fromDart(_response('first', second: 'second'));
      final decoded = _success(codec.decodeNative(_rawResponse(raw, providerId: 'xai')));

      expect(codec.normalize(decoded), isA<Failure<GenerationResult, AiError>>());
      expect(_success(codec.normalize(decoded, choiceIndex: 1)).text, 'second');

      final extended = _success(
        codec.encode(
          _conversation(),
          modelId: 'model-1',
          options: const _Options({'mode': 'auto'}),
          extraBody: JsonObject({'future_field': 7}),
        ),
      );
      expect(extended.body.toDart()['future_field'], 7);

      final collision = codec.encode(
        _conversation(),
        modelId: 'model-1',
        options: const _Options({'mode': 'auto'}),
        extraBody: JsonObject({'n': 2}),
      );
      expect(
        (collision as Failure<OpenAiCompatibleChatRequest, AiError>).error,
        isA<InvalidRequestError>(),
      );
    });

    test('dialect validation rejects unsupported options before transport', () {
      final codec = OpenAiCompatibleChatCodec(
        _Dialect(
          providerId: 'baseten',
          field: 'model_adapter',
          rejectStopSequences: true,
        ),
      );
      final request = GenerationRequest(
        messages: [UserMessage.text('hello')],
        options: GenerationOptions(stopSequences: ['END']),
      );

      final encoded = codec.encode(
        request,
        modelId: 'model-1',
        options: const _Options('adapter-v2'),
      );

      expect(
        (encoded as Failure<OpenAiCompatibleChatRequest, AiError>).error,
        isA<UnsupportedFeatureError>(),
      );
    });

    test('preserves same-target assistant replay and rejects incompatible targets', () {
      final xai = OpenAiCompatibleChatCodec(
        _Dialect(providerId: 'xai', field: 'search_parameters'),
      );
      final baseten = OpenAiCompatibleChatCodec(
        _Dialect(providerId: 'baseten', field: 'model_adapter'),
      );
      final response = JsonObject.fromDart({
        ..._response(''),
        'choices': [
          {
            'index': 0,
            'message': {
              'role': 'assistant',
              'content': null,
              'refusal': 'blocked',
              'reasoning_content': {'signature': 'keep'},
            },
            'finish_reason': 'refusal',
          },
        ],
      });
      final normalized = _success(
        xai.normalize(
          _success(xai.decodeNative(_rawResponse(response, providerId: 'xai'))),
        ),
      );
      final next = GenerationRequest(
        messages: [UserMessage.text('again'), normalized.message],
      );

      final encoded = _success(
        xai.encode(
          next,
          modelId: 'model-1',
          options: const _Options({'mode': 'auto'}),
        ),
      );
      final messages = encoded.body.toDart()['messages']! as List<Object?>;
      expect(messages.last, {
        'role': 'assistant',
        'content': null,
        'refusal': 'blocked',
        'reasoning_content': {'signature': 'keep'},
      });
      expect(
        baseten.encode(
          next,
          modelId: 'model-1',
          options: const _Options('adapter-v2'),
        ),
        isA<Failure<OpenAiCompatibleChatRequest, AiError>>(),
      );
      final ambiguousReplay = ProviderReplay(
        providerId: 'xai',
        api: 'chat.completions',
        modelId: 'model-1',
        items: [
          ReplayItem(
            phase: 'choice',
            data: JsonObject.fromDart({
              'index': 0,
              'message': {'role': 'assistant', 'content': 'answer'},
              'finish_reason': 'stop',
            }),
          ),
          ReplayItem(
            phase: 'delta-extension',
            data: JsonObject.fromDart({'opaque_signature': 'cannot merge'}),
          ),
        ],
      );
      expect(
        xai.encode(
          GenerationRequest(
            messages: [
              AssistantMessage(
                [TextOutputPart('answer')],
                replay: ambiguousReplay,
              ),
            ],
          ),
          modelId: 'model-1',
          options: const _Options({'mode': 'auto'}),
        ),
        isA<Failure<OpenAiCompatibleChatRequest, AiError>>(),
      );
    });

    test('keeps empty native tool arguments inspectable as malformed JSON', () {
      final codec = OpenAiCompatibleChatCodec(
        _Dialect(providerId: 'xai', field: 'search_parameters'),
      );
      final normalized = _success(
        codec.normalize(
          _success(
            codec.decodeNative(
              _rawResponse(
                JsonObject.fromDart(_response('', toolArguments: '  ')),
                providerId: 'xai',
              ),
            ),
          ),
        ),
      );

      final arguments =
          (normalized.message.parts.single as ApplicationToolCallPart).arguments
              as MalformedToolArguments;
      expect(arguments.originalText, '  ');
    });

    test('common and typed streams share framing while preserving malformed arguments', () async {
      final codec = OpenAiCompatibleChatCodec(
        _Dialect(providerId: 'xai', field: 'search_parameters'),
      );
      final body = _streamBody();
      var requests = 0;
      final client = ProviderHttpClient(
        baseUrl: Uri.parse('https://example.test/'),
        client: _StreamClient(() {
          requests++;
          return http.StreamedResponse(Stream.value(body), 200);
        }),
      );
      addTearDown(client.close);

      final common = await client
          .sendSse<GenerationEvent>(
            ProviderHttpRequest(method: 'POST', path: 'chat/completions'),
            createProtocol: () => codec.commonStream(modelId: 'model-1'),
          )
          .runCollect()
          .runFuture();
      final native = await client
          .sendSse<OpenAiCompatibleStreamEvent>(
            ProviderHttpRequest(method: 'POST', path: 'chat/completions'),
            createProtocol: codec.toNativeStream,
          )
          .runCollect()
          .runFuture();
      final finished = common.whereType<GenerationFinished>().single.result;
      final nonstream = _success(
        codec.normalize(
          _success(
            codec.decodeNative(
              _rawResponse(
                JsonObject.fromDart(_response('Answer done', toolArguments: '{')),
                providerId: 'xai',
              ),
            ),
          ),
        ),
      );

      expect(requests, 2);
      expect(
        finished.message.parts.map((part) => part.toDart()),
        nonstream.message.parts.map((part) => part.toDart()),
      );
      expect(
        (finished.message.parts.last as ApplicationToolCallPart).arguments,
        isA<MalformedToolArguments>(),
      );
      expect(finished.usage?.totalTokens, 5);
      final assembled = finished.nativePayload.json.toDart();
      final choices = assembled['choices'];
      if (choices is! List<Object?>) {
        fail('Expected one assembled native choice.');
      }
      final assembledChoice = choices.single;
      if (assembledChoice is! Map<String, Object?>) {
        fail('Expected one assembled native choice.');
      }
      final message = assembledChoice['message'];
      if (message is! Map<String, Object?>) {
        fail('Expected one assembled native tool call.');
      }
      final calls = message['tool_calls'];
      if (calls is! List<Object?>) {
        fail('Expected one assembled native tool call.');
      }
      final assembledCall = calls.single;
      if (assembledCall is! Map<String, Object?>) {
        fail('Expected one assembled native tool call.');
      }
      expect(
        (assembled['usage']! as Map<String, Object?>)['completion_tokens_details'],
        {'reasoning_tokens': 2},
      );
      expect(assembledChoice['choice_future'], {'keep': true});
      expect(assembledCall['tool_future'], isTrue);
      expect(
        (assembledCall['function']! as Map<String, Object?>)['function_future'],
        9,
      );
      expect(finished.message.replay?.items.first.phase, 'choice');
      final replayed = _success(
        codec.encode(
          GenerationRequest(messages: [finished.message]),
          modelId: 'model-1',
          options: const _Options({'mode': 'auto'}),
        ),
      );
      final replayedMessages = replayed.body.toDart()['messages']! as List<Object?>;
      expect(
        (replayedMessages.single! as Map<String, Object?>)['reasoning_content'],
        'signed-trace',
      );
      expect(common.whereType<ProviderEvent>(), hasLength(3));
      expect(common.last, isA<GenerationFinished>());
      expect(native.whereType<OpenAiCompatibleChunk>(), hasLength(5));
      expect(native.whereType<OpenAiCompatibleUnknownEvent>(), hasLength(1));
      expect(native.last, isA<OpenAiCompatibleDone>());
    });
  });
}

Effect<({NativeResponse<OpenAiCompatibleChatResponse> native, GenerationResult result}), AiError>
_executeCreate(
  ProviderHttpClient client,
  OpenAiCompatibleChatCodec<_Options> codec,
  _Options options,
  GenerationRequest request,
) => Effect.build(($) async {
  final encoded = await $(
    Effect.fromResult(
      codec.encode(request, modelId: 'model-1', options: options),
    ),
  );
  final raw = await $(
    client.sendJson(
      ProviderHttpRequest(method: 'POST', path: 'chat/completions', body: encoded.body),
      providerId: codec.dialect.providerId,
      api: codec.dialect.api,
      modelId: encoded.modelId,
    ),
  );
  final native = await $(Effect.fromResult(codec.decodeNative(raw)));
  final result = await $(Effect.fromResult(codec.normalize(native)));
  return (native: native, result: result);
});

GenerationRequest _conversation() => GenerationRequest(
  messages: [
    UserMessage.text('weather'),
    AssistantMessage([
      ApplicationToolCallPart(
        id: 'call-1',
        name: 'lookup',
        arguments: JsonToolArguments(
          JsonObject({'city': 'Paris'}),
          originalText: '{"city":"Paris"}',
        ),
      ),
    ]),
    ToolMessage([JsonToolResult(callId: 'call-1', value: const JsonString('sunny'))]),
  ],
  tools: [FunctionTool(name: 'lookup', inputSchema: JsonObject({}))],
);

Map<String, Object?> _response(
  String text, {
  String? second,
  String? toolArguments,
}) => {
  'id': 'response-1',
  'model': 'model-1',
  'provider_marker': {'keep': true},
  'choices': [
    {
      'index': 0,
      'message': {
        'role': 'assistant',
        'content': text,
        if (toolArguments != null)
          'tool_calls': [
            {
              'id': 'call-2',
              'type': 'function',
              'function': {'name': 'lookup', 'arguments': toolArguments},
            },
          ],
      },
      'finish_reason': toolArguments == null ? 'stop' : 'tool_calls',
    },
    if (second != null)
      {
        'index': 1,
        'message': {'role': 'assistant', 'content': second},
        'finish_reason': 'stop',
      },
  ],
  'usage': {'prompt_tokens': 2, 'completion_tokens': 3, 'total_tokens': 5},
};

NativeResponse<JsonObject> _rawResponse(JsonObject raw, {required String providerId}) =>
    NativeResponse(
      value: raw,
      payload: NativePayload(
        providerId: providerId,
        api: 'chat.completions',
        modelId: 'model-1',
        json: raw,
      ),
      metadata: ResponseMetadata(statusCode: 200, requestId: 'request-1'),
    );

List<int> _streamBody() {
  final records = <Object>[
    {
      'id': 'response-1',
      'model': 'model-1',
      'choices': [
        {
          'index': 0,
          'delta': {
            'role': 'assistant',
            'content': 'Answer ',
            'reasoning_content': 'signed-',
          },
          'finish_reason': null,
        },
      ],
    },
    {
      'id': 'response-1',
      'model': 'model-1',
      'choices': [
        {
          'index': 0,
          'choice_future': {'keep': true},
          'delta': {
            'tool_calls': [
              {
                'index': 0,
                'id': 'call-2',
                'tool_future': true,
                'function': {
                  'name': 'lookup',
                  'arguments': '{',
                  'function_future': 9,
                },
              },
            ],
          },
          'finish_reason': null,
        },
      ],
    },
    {
      'id': 'response-1',
      'model': 'model-1',
      'choices': [
        {
          'index': 0,
          'delta': {'content': 'done', 'reasoning_content': 'trace'},
          'finish_reason': null,
        },
      ],
    },
    {
      'future_event': {'keep': true},
    },
    {
      'id': 'response-1',
      'model': 'model-1',
      'choices': [
        {'index': 0, 'delta': <String, Object?>{}, 'finish_reason': 'tool_calls'},
      ],
    },
    {
      'id': 'response-1',
      'model': 'model-1',
      'choices': <Object?>[],
      'usage': {
        'prompt_tokens': 2,
        'completion_tokens': 3,
        'total_tokens': 5,
        'completion_tokens_details': {'reasoning_tokens': 2},
      },
    },
  ];
  return utf8.encode(
    '${records.map((record) => 'data: ${jsonEncode(record)}\n\n').join()}data: [DONE]\n\n',
  );
}

A _success<A>(Result<A, AiError> result) => switch (result) {
  Success(:final value) => value,
  Failure(:final error) => throw StateError('Expected success, got $error'),
};

final class _Options {
  const _Options(this.value);

  final Object? value;
}

final class _Dialect implements OpenAiCompatibleChatDialect<_Options> {
  _Dialect({
    required this.providerId,
    required this.field,
    this.rejectStopSequences = false,
  });

  @override
  final String providerId;
  final String field;
  final bool rejectStopSequences;

  @override
  String get api => 'chat.completions';

  @override
  AiError? validate(GenerationRequest request, _Options options) {
    if (rejectStopSequences && request.options.stopSequences.isNotEmpty) {
      return const UnsupportedFeatureError(
        'This dialect does not support stop sequences.',
        feature: 'stopSequences',
      );
    }
    return null;
  }

  @override
  JsonObject requestFields(_Options options) => JsonObject({field: options.value});
}

final class _StreamClient extends http.BaseClient {
  _StreamClient(this.response);

  final http.StreamedResponse Function() response;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async => response();
}
