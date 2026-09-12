import 'dart:convert';
import 'dart:io';

import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/json.dart';
import 'package:artificer_openai/artificer_openai.dart';
import 'package:conflux/conflux.dart';
import 'package:test/test.dart';

void main() {
  test('returned output replays exactly with a caller tool result', () async {
    final bodies = <Map<String, Object?>>[];
    final server = await _server((request, index) async {
      bodies.add(jsonDecode(await utf8.decoder.bind(request).join())! as Map<String, Object?>);
      return index == 0 ? _toolResponse : _textResponse;
    });
    final provider = _provider(server);
    addTearDown(provider.close);
    final model = provider.languageModel('gpt-future');
    final firstRequest = GenerationRequest(
      messages: [UserMessage.text('weather?')],
      tools: [
        FunctionTool(
          name: 'get_weather',
          description: 'Gets weather.',
          inputSchema: JsonObject({
            'type': 'object',
            'properties': {
              'city': {'type': 'string'},
            },
          }),
        ),
      ],
    );

    final first = await model.generate(firstRequest).runFuture();
    final call = first.message.parts.whereType<ApplicationToolCallPart>().single;
    final second = await model
        .generate(
          GenerationRequest(
            messages: [
              ...firstRequest.messages,
              first.message,
              ToolMessage([
                JsonToolResult(callId: call.id, value: JsonObject({'temperature': 18})),
              ]),
            ],
            tools: firstRequest.tools,
          ),
        )
        .runFuture();

    expect(first.message.parts, [
      isA<ReasoningSummaryPart>(),
      isA<TextOutputPart>(),
      isA<ApplicationToolCallPart>(),
      isA<ProviderToolRecordPart>().having(
        (part) => part.owner,
        'owner',
        ToolExecutionOwner.provider,
      ),
      isA<OpaqueOutputPart>(),
    ]);
    expect((call.arguments as JsonToolArguments).originalText, '{"city":"Paris"}');
    expect(first.message.replay!.items.map((item) => item.id), [
      'rs_1',
      'msg_1',
      'fc_1',
      'ws_1',
      'future_1',
    ]);
    expect(second.text, 'It is 18 C.');
    final replayed = bodies[1]['input']! as List<Object?>;
    expect(replayed.sublist(1, 6), _toolResponse['output']);
    expect(replayed.last, {
      'type': 'function_call_output',
      'call_id': 'call_1',
      'output': '{"temperature":18}',
    });
  });

  test('merges typed options, tools, and structured output without collisions', () async {
    late Map<String, Object?> body;
    final server = await _server((request, _) async {
      body = jsonDecode(await utf8.decoder.bind(request).join())! as Map<String, Object?>;
      return _textResponse;
    });
    final provider = _provider(server);
    addTearDown(provider.close);
    final defaults = OpenAIModelOptions(
      reasoning: const Setting.set(OpenAIReasoningOptions(effort: 'high', summary: 'auto')),
      promptCacheKey: const Setting.set('cache-1'),
      serviceTier: const Setting.set(OpenAIServiceTier.priority),
      include: const Setting.set([OpenAIResponseInclude.reasoningEncryptedContent]),
      tools: Setting.set([
        const OpenAIWebSearchTool(),
        OpenAIFileSearchTool(vectorStoreIds: ['vs_1']),
        const OpenAICodeInterpreterTool(),
        OpenAIRemoteMcpTool(serverLabel: 'docs', serverUrl: Uri.parse('https://mcp.test/sse')),
        const OpenAIComputerTool(),
        const OpenAIShellTool(),
        const OpenAIApplyPatchTool(),
      ]),
    );
    final model = provider.languageModel('gpt-future', options: defaults);

    await model
        .generate(
          GenerationRequest(
            messages: [UserMessage.text('Return JSON.')],
            output: JsonSchemaOutputFormat(
              name: 'answer',
              description: 'A typed answer.',
              schema: JsonObject({
                'type': 'object',
                'properties': {
                  'answer': {'type': 'string'},
                },
                'required': ['answer'],
                'additionalProperties': false,
              }),
            ),
          ),
          options: OpenAIModelOptions(
            reasoning: const Setting.clear(),
            promptCacheRetention: const Setting.set('24h'),
            include: const Setting.set([OpenAIResponseInclude.webSearchSources]),
          ),
        )
        .runFuture();

    expect(body['reasoning'], isNull);
    expect(body['prompt_cache_key'], 'cache-1');
    expect(body['prompt_cache_retention'], '24h');
    expect(body['service_tier'], 'priority');
    expect(body['include'], ['web_search_call.action.sources']);
    expect((body['tools']! as List<Object?>).map((tool) => (tool! as Map)['type']), [
      'web_search',
      'file_search',
      'code_interpreter',
      'mcp',
      'computer',
      'shell',
      'apply_patch',
    ]);
    expect(body['text'], {
      'format': {
        'type': 'json_schema',
        'name': 'answer',
        'description': 'A typed answer.',
        'schema': isA<Map<String, Object?>>(),
        'strict': true,
      },
    });
  });

  test('maps explicit image sources and rejects unsupported media before I/O', () async {
    var requests = 0;
    late Map<String, Object?> body;
    final server = await _server((request, _) async {
      requests++;
      body = jsonDecode(await utf8.decoder.bind(request).join())! as Map<String, Object?>;
      return _textResponse;
    });
    final provider = _provider(server);
    addTearDown(provider.close);
    final model = provider.languageModel('gpt-future');

    await model
        .generate(
          GenerationRequest(
            messages: [
              UserMessage([
                TextInputPart('describe'),
                MediaInputPart(
                  kind: MediaKind.image,
                  mimeType: 'image/png',
                  source: BytesMediaSource([1, 2, 3]),
                ),
                MediaInputPart(
                  kind: MediaKind.image,
                  mimeType: 'image/png',
                  source: ProviderFileSource(
                    providerId: 'openai',
                    api: 'responses',
                    reference: 'file_1',
                    mimeType: 'image/png',
                  ),
                ),
              ]),
            ],
          ),
        )
        .runFuture();
    final parts = ((body['input']! as List).single as Map)['content']! as List;
    expect(parts[1], {'type': 'input_image', 'image_url': 'data:image/png;base64,AQID'});
    expect(parts[2], {'type': 'input_image', 'file_id': 'file_1'});

    final failed = await model
        .generate(
          GenerationRequest(
            messages: [
              UserMessage([
                MediaInputPart(
                  kind: MediaKind.video,
                  mimeType: 'video/mp4',
                  source: UrlMediaSource(Uri.parse('https://example.test/video.mp4')),
                ),
              ]),
            ],
          ),
        )
        .runFutureExit();
    expect(failed, _failedWith<UnsupportedFeatureError>());
    expect(requests, 1);
  });

  test('keeps refusals, truncation, malformed arguments, and native actions inspectable', () {
    final provider = OpenAIProvider(apiKey: 'secret');
    addTearDown(provider.close);
    final raw = JsonObject({
      'id': 'resp_edges',
      'status': 'incomplete',
      'incomplete_details': {'reason': 'max_output_tokens'},
      'model': 'gpt-future',
      'output': [
        {
          'id': 'msg_refusal',
          'type': 'message',
          'status': 'incomplete',
          'role': 'assistant',
          'content': [
            {'type': 'refusal', 'refusal': 'Cannot help.'},
          ],
        },
        {
          'id': 'fn_bad',
          'type': 'function_call',
          'call_id': 'call_bad',
          'name': 'broken',
          'arguments': '{',
          'status': 'incomplete',
        },
        {
          'id': 'custom_1',
          'type': 'custom_tool_call',
          'call_id': 'call_custom',
          'name': 'grammar',
          'input': 'plain text',
          'status': 'completed',
        },
        {
          'id': 'computer_1',
          'type': 'computer_call',
          'call_id': 'call_computer',
          'status': 'completed',
          'action': {'type': 'click', 'x': 1, 'y': 2},
        },
      ],
    });
    final response = NativeResponse(
      value: OpenAIResponse.fromJson(raw),
      payload: NativePayload(
        providerId: 'openai',
        api: 'responses',
        modelId: 'gpt-future',
        json: raw,
      ),
      metadata: ResponseMetadata(statusCode: 200),
    );

    final result = provider.responses.normalize(response);
    final calls = result.message.parts.whereType<ApplicationToolCallPart>().toList();

    expect(result.finishReason, FinishReason.outputLimit);
    expect(result.message.parts.whereType<RefusalPart>().single.text, 'Cannot help.');
    expect(calls[0].arguments, isA<MalformedToolArguments>());
    expect(calls[1].arguments, isA<TextToolArguments>());
    expect(calls[2].arguments, isA<NativeToolArguments>());
    expect(result.message.replay!.items, hasLength(4));
  });

  test('rejects stateful common options and incompatible replay before I/O', () async {
    var requests = 0;
    final server = await _server((request, _) async {
      requests++;
      await request.drain<void>();
      return _textResponse;
    });
    final provider = _provider(server);
    addTearDown(provider.close);
    final stateful = provider.languageModel(
      'gpt-future',
      options: OpenAIModelOptions(extraBody: JsonObject({'background': true})),
    );
    final replay = AssistantMessage(
      [TextOutputPart('old')],
      replay: ProviderReplay(
        providerId: 'another-provider',
        api: 'responses',
        modelId: 'gpt-future',
        items: [
          ReplayItem(data: JsonObject({'type': 'message'})),
        ],
      ),
    );

    final statefulExit = await stateful
        .generate(GenerationRequest(messages: [UserMessage.text('hello')]))
        .runFutureExit();
    final replayExit = await provider
        .languageModel('gpt-future')
        .generate(GenerationRequest(messages: [UserMessage.text('hello'), replay]))
        .runFutureExit();

    expect(statefulExit, _failedWith<InvalidRequestError>());
    expect(replayExit, _failedWith<InvalidRequestError>());
    expect(requests, 0);
  });
}

Future<HttpServer> _server(
  Future<Map<String, Object?>> Function(HttpRequest request, int index) response,
) async {
  var index = 0;
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  addTearDown(() => server.close(force: true));
  server.listen((request) async {
    final payload = await response(request, index++);
    request.response
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(payload));
    await request.response.close();
  });
  return server;
}

OpenAIProvider _provider(HttpServer server) => OpenAIProvider(
  apiKey: 'secret',
  baseUrl: Uri.parse('http://${server.address.address}:${server.port}/v1/'),
);

Matcher _failedWith<E extends AiError>() => isA<Failed<Object?, AiError>>().having(
  (failure) => failure.cause,
  'cause',
  isA<Expected<AiError>>().having((expected) => expected.error, 'error', isA<E>()),
);

const _toolResponse = <String, Object?>{
  'id': 'resp_tools',
  'status': 'completed',
  'model': 'gpt-future',
  'output': [
    {
      'id': 'rs_1',
      'type': 'reasoning',
      'status': 'completed',
      'summary': [
        {'type': 'summary_text', 'text': 'Checking the weather.'},
      ],
      'encrypted_content': 'opaque-signature',
    },
    {
      'id': 'msg_1',
      'type': 'message',
      'status': 'completed',
      'role': 'assistant',
      'phase': 'commentary',
      'content': [
        {
          'type': 'output_text',
          'text': 'I will check.',
          'annotations': [
            {'type': 'url_citation', 'url': 'https://weather.test', 'title': 'Weather'},
          ],
        },
      ],
    },
    {
      'id': 'fc_1',
      'type': 'function_call',
      'call_id': 'call_1',
      'name': 'get_weather',
      'arguments': '{"city":"Paris"}',
      'status': 'completed',
    },
    {
      'id': 'ws_1',
      'type': 'web_search_call',
      'status': 'completed',
      'action': {'type': 'search', 'query': 'Paris weather'},
    },
    {
      'id': 'future_1',
      'type': 'future_output',
      'payload': {'keep': true},
    },
  ],
  'usage': {'input_tokens': 2, 'output_tokens': 4, 'total_tokens': 6},
};

const _textResponse = <String, Object?>{
  'id': 'resp_text',
  'status': 'completed',
  'model': 'gpt-future',
  'output': [
    {
      'id': 'msg_2',
      'type': 'message',
      'status': 'completed',
      'role': 'assistant',
      'content': [
        {'type': 'output_text', 'text': 'It is 18 C.', 'annotations': <Object?>[]},
      ],
    },
  ],
};
