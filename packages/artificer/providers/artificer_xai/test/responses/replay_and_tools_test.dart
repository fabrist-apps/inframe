import 'dart:convert';
import 'dart:io';

import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/json.dart';
import 'package:artificer_xai/artificer_xai.dart';
import 'package:conflux/conflux.dart';
import 'package:test/test.dart';

void main() {
  test('xAI code execution omits the rejected OpenAI container field', () {
    expect(const XaiCodeInterpreterTool().toDart(), {
      'type': 'code_interpreter',
    });
  });

  test('returned output replays exactly with a caller tool result', () async {
    final bodies = <Map<String, Object?>>[];
    final server = await _server((request, index) async {
      bodies.add(jsonDecode(await utf8.decoder.bind(request).join())! as Map<String, Object?>);
      return index == 0 ? _toolResponse : _textResponse;
    });
    final provider = _provider(server);
    addTearDown(provider.close);
    final model = provider.languageModel('grok-future');
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
    expect(((bodies.first['tools']! as List<Object?>).single! as Map)['strict'], isFalse);
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
    final defaults = XaiModelOptions(
      reasoning: const Setting.set(XaiReasoningOptions(effort: 'high', summary: 'auto')),
      promptCacheKey: const Setting.set('cache-1'),
      serviceTier: const Setting.set(XaiServiceTier.priority),
      inference: const Setting.set(XaiInferenceOptions(maxTurns: 4, minP: 0.1)),
      include: const Setting.set([XaiResponseInclude.reasoningEncryptedContent]),
      tools: Setting.set([
        XaiWebSearchTool(allowedDomains: ['docs.x.ai'], enableImageSearch: true),
        XaiXSearchTool(allowedHandles: ['xai'], enableVideoUnderstanding: true),
        XaiCollectionsSearchTool(collectionIds: ['collection_1'], maxResults: 5),
        const XaiCodeInterpreterTool(),
        XaiRemoteMcpTool(
          serverLabel: 'docs',
          serverUrl: Uri.parse('https://mcp.test/sse'),
          allowedTools: ['lookup'],
          deferLoading: true,
        ),
      ]),
    );
    final model = provider.languageModel('grok-future', options: defaults);

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
          options: XaiModelOptions(
            reasoning: const Setting.clear(),
            inference: const Setting.set(
              XaiInferenceOptions(topK: 32, logprobs: true, topLogprobs: 4),
            ),
            include: const Setting.set([XaiResponseInclude.webSearchSources]),
          ),
        )
        .runFuture();

    expect(body['reasoning'], isNull);
    expect(body['prompt_cache_key'], 'cache-1');
    expect(body['service_tier'], 'priority');
    expect(body['max_turns'], isNull);
    expect(body['top_k'], 32);
    expect(body['logprobs'], isTrue);
    expect(body['top_logprobs'], 4);
    expect(body['include'], [
      'reasoning.encrypted_content',
      'web_search_call.action.sources',
    ]);
    expect((body['tools']! as List<Object?>).map((tool) => (tool! as Map)['type']), [
      'web_search',
      'x_search',
      'file_search',
      'code_interpreter',
      'mcp',
    ]);
    final tools = body['tools']! as List<Object?>;
    expect(tools[0], {
      'type': 'web_search',
      'allowed_domains': ['docs.x.ai'],
      'enable_image_search': true,
    });
    expect(tools[1], {
      'type': 'x_search',
      'allowed_x_handles': ['xai'],
      'enable_video_understanding': true,
    });
    expect(tools[2], {
      'type': 'file_search',
      'vector_store_ids': ['collection_1'],
      'max_num_results': 5,
    });
    expect(tools[3], {'type': 'code_interpreter'});
    expect(tools[4], {
      'type': 'mcp',
      'server_label': 'docs',
      'server_url': 'https://mcp.test/sse',
      'allowed_tools': ['lookup'],
      'defer_loading': true,
    });
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
    final model = provider.languageModel('grok-future');

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
              ]),
            ],
          ),
        )
        .runFuture();
    final parts = ((body['input']! as List).single as Map)['content']! as List;
    expect(parts[1], {'type': 'input_image', 'image_url': 'data:image/png;base64,AQID'});

    final fileImageFailed = await model
        .generate(
          GenerationRequest(
            messages: [
              UserMessage([
                MediaInputPart(
                  kind: MediaKind.image,
                  mimeType: 'image/png',
                  source: ProviderFileSource(
                    providerId: 'xai',
                    api: 'responses',
                    reference: 'file_1',
                    mimeType: 'image/png',
                  ),
                ),
              ]),
            ],
          ),
        )
        .runFutureExit();

    final audioFailed = await model
        .generate(
          GenerationRequest(
            messages: [
              UserMessage([
                MediaInputPart(
                  kind: MediaKind.audio,
                  mimeType: 'audio/wav',
                  source: BytesMediaSource([1, 2, 3]),
                ),
              ]),
            ],
          ),
        )
        .runFutureExit();
    final videoFailed = await model
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
    expect(fileImageFailed, _failedWith<UnsupportedFeatureError>());
    expect(audioFailed, _failedWith<UnsupportedFeatureError>());
    expect(videoFailed, _failedWith<UnsupportedFeatureError>());
    expect(requests, 1);
  });

  test('empty portable assistant history fails through the typed channel', () async {
    var requests = 0;
    final server = await _server((request, _) async {
      requests++;
      return _textResponse;
    });
    final provider = _provider(server);
    addTearDown(provider.close);
    final model = provider.languageModel('grok-future');
    final histories = [
      AssistantMessage([]),
      AssistantMessage([TextOutputPart('')]),
    ];

    for (final assistant in histories) {
      final request = GenerationRequest(
        messages: [UserMessage.text('before'), assistant, UserMessage.text('after')],
      );
      expect(await model.generate(request).runFutureExit(), _failedWith<UnsupportedFeatureError>());
      expect(
        await model.stream(request).runCollect().runFutureExit(),
        _failedWith<UnsupportedFeatureError>(),
      );
    }
    expect(requests, 0);
  });

  test('encodes custom and native caller tool results with their matching types', () async {
    late Map<String, Object?> body;
    final server = await _server((request, _) async {
      body = jsonDecode(await utf8.decoder.bind(request).join())! as Map<String, Object?>;
      return _textResponse;
    });
    final provider = _provider(server);
    addTearDown(provider.close);
    final assistant = AssistantMessage(
      [
        ApplicationToolCallPart(
          id: 'call_custom',
          name: 'grammar',
          arguments: TextToolArguments('plain text'),
        ),
        ApplicationToolCallPart(
          id: 'call_computer',
          name: 'computer',
          arguments: NativeToolArguments(
            providerId: 'xai',
            api: 'responses',
            action: JsonObject({
              'action': {'type': 'click', 'x': 1, 'y': 2},
            }),
          ),
        ),
      ],
      replay: ProviderReplay(
        providerId: 'xai',
        api: 'responses',
        modelId: 'grok-future',
        items: [
          ReplayItem(
            data: JsonObject({
              'type': 'custom_tool_call',
              'call_id': 'call_custom',
              'name': 'grammar',
              'input': 'plain text',
            }),
          ),
          ReplayItem(
            data: JsonObject({
              'type': 'computer_call',
              'call_id': 'call_computer',
              'action': {'type': 'click', 'x': 1, 'y': 2},
            }),
          ),
        ],
      ),
    );

    await provider
        .languageModel('grok-future')
        .generate(
          GenerationRequest(
            messages: [
              assistant,
              ToolMessage([
                TextToolResult(callId: 'call_custom', content: [TextInputPart('accepted')]),
                NativeToolResult(
                  callId: 'call_computer',
                  providerId: 'xai',
                  api: 'responses',
                  value: JsonObject({
                    'output': {
                      'type': 'computer_screenshot',
                      'image_url': 'https://example.test/screenshot.png',
                    },
                  }),
                ),
              ]),
            ],
          ),
        )
        .runFuture();

    expect((body['input']! as List<Object?>).sublist(2), [
      {
        'type': 'custom_tool_call_output',
        'call_id': 'call_custom',
        'output': [
          {'type': 'input_text', 'text': 'accepted'},
        ],
      },
      {
        'output': {
          'type': 'computer_screenshot',
          'image_url': 'https://example.test/screenshot.png',
        },
        'type': 'computer_call_output',
        'call_id': 'call_computer',
      },
    ]);
  });

  test('keeps refusals, truncation, malformed arguments, and native actions inspectable', () {
    final provider = XaiProvider(apiKey: 'secret');
    addTearDown(provider.close);
    final raw = JsonObject({
      'id': 'resp_edges',
      'status': 'incomplete',
      'incomplete_details': {'reason': 'max_output_tokens'},
      'model': 'grok-future',
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
      ],
    });
    final response = NativeResponse(
      value: XaiResponse.fromJson(raw),
      payload: NativePayload(
        providerId: 'xai',
        api: 'responses',
        modelId: 'grok-future',
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
    expect(result.message.replay!.items, hasLength(3));
  });

  test('keeps each xAI-hosted tool as provider-owned activity in output order', () {
    final raw = JsonObject({
      'id': 'resp_hosted',
      'status': 'completed',
      'model': 'grok-future',
      'output': [
        for (final type in [
          'web_search_call',
          'x_search_call',
          'file_search_call',
          'code_interpreter_call',
          'mcp_call',
          'tool_search_call',
        ])
          {'id': 'id_$type', 'type': type, 'status': 'completed'},
      ],
    });
    final provider = XaiProvider(apiKey: 'secret');
    addTearDown(provider.close);
    final response = NativeResponse(
      value: XaiResponse.fromJson(raw),
      payload: NativePayload(
        providerId: 'xai',
        api: 'responses',
        modelId: 'grok-future',
        json: raw,
      ),
      metadata: ResponseMetadata(statusCode: 200),
    );

    final records = provider.responses
        .normalize(response)
        .message
        .parts
        .whereType<ProviderToolRecordPart>()
        .toList();

    expect(records.map((record) => record.name), [
      'web_search',
      'x_search',
      'file_search',
      'code_interpreter',
      'mcp',
      'tool_search',
    ]);
    expect(records.map((record) => record.owner), everyElement(ToolExecutionOwner.provider));
  });

  test('malformed optional fields fail predictably and invalid citations are skipped', () {
    expect(
      () => XaiResponseOutputItem.fromDart({
        'id': 1,
        'type': 'message',
        'content': <Object?>[],
      }),
      throwsFormatException,
    );
    final raw = JsonObject({
      'id': 'resp_citation',
      'status': 'completed',
      'model': 'grok-future',
      'output': [
        {
          'id': 'msg_1',
          'type': 'message',
          'status': 'completed',
          'content': [
            {
              'type': 'output_text',
              'text': 'answer',
              'annotations': [
                {'type': 'url_citation', 'url': 'http://['},
              ],
            },
          ],
        },
      ],
    });
    final provider = XaiProvider(apiKey: 'secret');
    addTearDown(provider.close);

    final result = provider.responses.normalize(
      NativeResponse(
        value: XaiResponse.fromJson(raw),
        payload: NativePayload(
          providerId: 'xai',
          api: 'responses',
          modelId: 'grok-future',
          json: raw,
        ),
        metadata: ResponseMetadata(statusCode: 200),
      ),
    );

    expect(result.message.parts.whereType<TextOutputPart>().single.citations, isEmpty);
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
      'grok-future',
      options: XaiModelOptions(extraBody: JsonObject({'background': true})),
    );
    final replay = AssistantMessage(
      [TextOutputPart('old')],
      replay: ProviderReplay(
        providerId: 'another-provider',
        api: 'responses',
        modelId: 'grok-future',
        items: [
          ReplayItem(data: JsonObject({'type': 'message'})),
        ],
      ),
    );

    final statefulExit = await stateful
        .generate(GenerationRequest(messages: [UserMessage.text('hello')]))
        .runFutureExit();
    final replayExit = await provider
        .languageModel('grok-future')
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

XaiProvider _provider(HttpServer server) => XaiProvider(
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
  'model': 'grok-future',
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
  'model': 'grok-future',
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
