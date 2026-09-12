import 'dart:convert';
import 'dart:io';

import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/json.dart';
import 'package:artificer_google/artificer_google.dart';
import 'package:conflux/conflux.dart';
import 'package:test/test.dart';

void main() {
  group('Google common content and tools', () {
    test('serializes the pinned native tool surface', () {
      expect(
        [
          GoogleFunctionDeclarationsTool([
            GoogleFunctionDeclaration(
              name: 'lookup',
              description: 'Lookup',
              parameters: JsonObject({'type': 'object'}),
            ),
          ]),
          GoogleSearchTool(config: JsonObject({'searchTypes': {}})),
          GoogleCodeExecutionTool(),
          GoogleUrlContextTool(),
          GoogleFileSearchTool(['fileSearchStores/store-1']),
          GoogleMapsTool(config: JsonObject({'enableWidget': true})),
          GoogleRemoteMcpTool([
            JsonObject({
              'name': 'weather',
              'streamableHttpTransport': {'url': 'https://mcp.example'},
            }),
          ]),
          GoogleComputerUseTool(JsonObject({'environment': 'ENVIRONMENT_BROWSER'})),
          GoogleSearchRetrievalTool(JsonObject({'dynamicRetrievalConfig': {}})),
        ].map((tool) => tool.toJson().toDart()).toList(),
        [
          {
            'functionDeclarations': [
              {
                'name': 'lookup',
                'description': 'Lookup',
                'parameters': {'type': 'object'},
              },
            ],
          },
          {
            'googleSearch': {'searchTypes': <String, Object?>{}},
          },
          {'codeExecution': <String, Object?>{}},
          {'urlContext': <String, Object?>{}},
          {
            'fileSearch': {
              'fileSearchStoreNames': ['fileSearchStores/store-1'],
            },
          },
          {
            'googleMaps': {'enableWidget': true},
          },
          {
            'mcpServers': [
              {
                'name': 'weather',
                'streamableHttpTransport': {'url': 'https://mcp.example'},
              },
            ],
          },
          {
            'computerUse': {'environment': 'ENVIRONMENT_BROWSER'},
          },
          {
            'googleSearchRetrieval': {
              'dynamicRetrievalConfig': <String, Object?>{},
            },
          },
        ],
      );
    });

    test('maps media, tools, JSON Schema, native activity, and citations', () async {
      final bodies = <Map<String, Object?>>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        bodies.add(jsonDecode(await utf8.decoder.bind(request).join())! as Map<String, Object?>);
        _json(request, _toolResponse);
        await request.response.close();
      });
      final provider = _provider(server);
      addTearDown(provider.close);
      final model = provider.languageModel(
        'gemini-test',
        options: GoogleModelOptions(
          tools: Setting.set([
            GoogleSearchTool(),
            GoogleComputerUseTool(JsonObject({'environment': 'ENVIRONMENT_BROWSER'})),
          ]),
        ),
      );
      final request = GenerationRequest(
        messages: [
          UserMessage([
            TextInputPart('Inspect these inputs.'),
            MediaInputPart(
              kind: MediaKind.image,
              mimeType: 'image/png',
              source: BytesMediaSource([1, 2, 3]),
            ),
            MediaInputPart(
              kind: MediaKind.audio,
              mimeType: 'audio/wav',
              source: BytesMediaSource([4, 5]),
            ),
            MediaInputPart(
              kind: MediaKind.video,
              mimeType: 'video/mp4',
              source: BytesMediaSource([6, 7]),
            ),
            MediaInputPart(
              kind: MediaKind.document,
              mimeType: 'application/pdf',
              source: ProviderFileSource(
                providerId: 'google',
                api: 'files',
                reference: 'https://files.example/file-1',
                mimeType: 'application/pdf',
              ),
            ),
          ]),
        ],
        tools: [
          FunctionTool(
            name: 'lookup',
            description: 'Look up a value.',
            inputSchema: JsonObject({
              'type': 'object',
              'properties': {
                'query': {'type': 'string'},
              },
              'required': ['query'],
            }),
          ),
        ],
        toolChoice: FunctionToolChoice('lookup'),
        output: JsonSchemaOutputFormat(
          name: 'answer',
          schema: JsonObject({
            'type': 'object',
            'properties': {
              'answer': {'type': 'string'},
            },
            'required': ['answer'],
          }),
        ),
      );

      final result = await model.generate(request).runFuture();

      final body = bodies.single;
      final inputParts = ((body['contents']! as List).single as Map)['parts']! as List;
      expect(inputParts, [
        {'text': 'Inspect these inputs.'},
        {
          'inlineData': {'mimeType': 'image/png', 'data': 'AQID'},
        },
        {
          'inlineData': {'mimeType': 'audio/wav', 'data': 'BAU='},
        },
        {
          'inlineData': {'mimeType': 'video/mp4', 'data': 'Bgc='},
        },
        {
          'fileData': {
            'mimeType': 'application/pdf',
            'fileUri': 'https://files.example/file-1',
          },
        },
      ]);
      expect(body['tools']! as List, hasLength(3));
      expect((body['toolConfig']! as Map)['functionCallingConfig']! as Map, {
        'mode': 'ANY',
        'allowedFunctionNames': ['lookup'],
      });
      expect((body['generationConfig']! as Map)['responseMimeType'], 'application/json');
      expect((body['generationConfig']! as Map)['responseJsonSchema'], {
        'type': 'object',
        'properties': {
          'answer': {'type': 'string'},
        },
        'required': ['answer'],
      });
      expect(
        result.message.parts.whereType<TextOutputPart>().single.citations.single.uri.host,
        'source.example',
      );
      expect(result.message.parts.whereType<ApplicationToolCallPart>().single.id, 'call-1');
      expect(result.message.parts.whereType<ProviderToolRecordPart>(), hasLength(2));
      expect(result.finishReason, FinishReason.toolCalls);
      expect(
        result.message.replay!.items
            .where((item) => item.phase == 'content')
            .single
            .data
            .toDart()['parts'],
        contains(
          containsPair('thoughtSignature', 'signed-thought'),
        ),
      );
    });

    test('replays signed native content and ordered application results', () async {
      final bodies = <Map<String, Object?>>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        bodies.add(jsonDecode(await utf8.decoder.bind(request).join())! as Map<String, Object?>);
        _json(request, _toolResponse);
        await request.response.close();
      });
      final provider = _provider(server);
      addTearDown(provider.close);
      final model = provider.languageModel('gemini-test');
      final firstRequest = GenerationRequest(
        messages: [UserMessage.text('Call the tool.')],
        tools: [
          FunctionTool(name: 'lookup', inputSchema: JsonObject({'type': 'object'})),
        ],
      );
      final first = await model.generate(firstRequest).runFuture();
      final persisted = GenerationResult.fromJson(first.toJson());

      await model
          .generate(
            GenerationRequest(
              messages: [
                UserMessage.text('Call the tool.'),
                persisted.message,
                ToolMessage([
                  JsonToolResult(
                    callId: 'call-1',
                    value: JsonValue.fromDart({'value': 42}),
                  ),
                ]),
              ],
              tools: [
                FunctionTool(name: 'lookup', inputSchema: JsonObject({'type': 'object'})),
              ],
            ),
          )
          .runFuture();

      final contents = bodies.last['contents']! as List;
      final replayed = contents[1] as Map<String, Object?>;
      expect(replayed['role'], 'model');
      expect(
        replayed['parts'],
        _toolResponse['candidates'] is List
            ? ((_toolResponse['candidates']! as List).single as Map)['content'] is Map
                  ? (((_toolResponse['candidates']! as List).single as Map)['content']!
                        as Map)['parts']
                  : null
            : null,
      );
      final resultPart = ((contents[2] as Map)['parts']! as List).single as Map;
      expect(resultPart['functionResponse'], {
        'id': 'call-1',
        'name': 'lookup',
        'response': {
          'output': {'value': 42},
        },
      });
    });

    test('rejects unsupported media and schema keywords before I/O', () async {
      var requests = 0;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) => requests++);
      final provider = _provider(server);
      addTearDown(provider.close);
      final model = provider.languageModel('gemini-test');

      final media = await model
          .generate(
            GenerationRequest(
              messages: [
                UserMessage([
                  MediaInputPart(
                    kind: MediaKind.image,
                    mimeType: 'image/png',
                    source: UrlMediaSource(Uri.parse('https://example.com/image.png')),
                  ),
                ]),
              ],
            ),
          )
          .runFutureExit();
      final schema = await model
          .generate(
            GenerationRequest(
              messages: [UserMessage.text('json')],
              output: JsonSchemaOutputFormat(
                name: 'bad',
                schema: JsonObject({'type': 'string', 'pattern': '^x'}),
              ),
            ),
          )
          .runFutureExit();

      expect(media, _failedWith<UnsupportedFeatureError>());
      expect(schema, _failedWith<UnsupportedFeatureError>());
      expect(requests, 0);
    });

    test('rejects duplicate function declarations before I/O', () async {
      var requests = 0;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) => requests++);
      final provider = _provider(server);
      addTearDown(provider.close);
      final model = provider.languageModel(
        'gemini-test',
        options: GoogleModelOptions(
          tools: Setting.set([
            GoogleFunctionDeclarationsTool([
              GoogleFunctionDeclaration(
                name: 'lookup',
                parameters: JsonObject({'type': 'object'}),
              ),
            ]),
            GoogleFunctionDeclarationsTool([
              GoogleFunctionDeclaration(
                name: 'lookup',
                parameters: JsonObject({'type': 'object'}),
              ),
            ]),
          ]),
        ),
      );

      final exit = await model
          .generate(
            GenerationRequest(
              messages: [UserMessage.text('call')],
            ),
          )
          .runFutureExit();

      expect(exit, _failedWith<InvalidRequestError>());
      expect(requests, 0);
    });
  });

  test('counts tokens through one typed selected-model request', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      expect(request.method, 'POST');
      expect(request.uri.path, '/v1beta/models/gemini-test:countTokens');
      expect(jsonDecode(await utf8.decoder.bind(request).join()), {
        'generateContentRequest': {
          'contents': [
            {
              'role': 'user',
              'parts': [
                {'text': 'hello'},
              ],
            },
          ],
          'tools': [
            {
              'functionDeclarations': [
                {
                  'name': 'lookup',
                  'parameters': {'type': 'object'},
                },
              ],
            },
          ],
        },
      });
      _json(request, {
        'totalTokens': 7,
        'cachedContentTokenCount': 2,
        'promptTokensDetails': [
          {'modality': 'TEXT', 'tokenCount': 7},
        ],
      });
      await request.response.close();
    });
    final provider = _provider(server);
    addTearDown(provider.close);

    final result = await provider.models
        .countTokens(
          GoogleCountTokensRequest(
            model: 'models/gemini-test',
            generateContentRequest: GoogleGenerateContentRequest(
              model: 'models/gemini-test',
              contents: [
                GoogleContent(role: 'user', parts: [GooglePart.text('hello')]),
              ],
              tools: [
                GoogleFunctionDeclarationsTool([
                  GoogleFunctionDeclaration(
                    name: 'lookup',
                    parameters: JsonObject({'type': 'object'}),
                  ),
                ]),
              ],
            ),
          ),
        )
        .runFuture();

    expect(result.value.totalTokens, 7);
    expect(result.value.cachedContentTokenCount, 2);
    expect(result.value.extensions.toDart()['promptTokensDetails'], isNotEmpty);
  });

  test('retains malformed function arguments without coercion', () {
    final provider = GoogleProvider(apiKey: 'secret');
    addTearDown(provider.close);
    final response = NativeResponse(
      value: GoogleGenerateContentResponse.fromJson(
        JsonObject({
          'candidates': [
            {
              'content': {
                'role': 'model',
                'parts': [
                  {
                    'functionCall': {'name': 'lookup', 'args': 'not-an-object'},
                  },
                ],
              },
              'finishReason': 'FUNCTION_CALL',
            },
          ],
        }),
      ),
      payload: NativePayload(
        providerId: 'google',
        api: 'generateContent',
        modelId: 'gemini-test',
        json: JsonObject({}),
      ),
      metadata: ResponseMetadata(statusCode: 200),
    );
    final request = GoogleGenerateContentRequest(
      model: 'models/gemini-test',
      contents: [
        GoogleContent(role: 'user', parts: [GooglePart.text('call')]),
      ],
      tools: [
        GoogleFunctionDeclarationsTool([
          GoogleFunctionDeclaration(name: 'lookup', parameters: JsonObject({'type': 'object'})),
        ]),
      ],
    );

    final call = provider.generateContent
        .normalize(response, request: request)
        .message
        .parts
        .whereType<ApplicationToolCallPart>()
        .single;

    expect(call.arguments, isA<MalformedToolArguments>());
    expect((call.arguments as MalformedToolArguments).originalText, '"not-an-object"');
    final replay = response.value.candidates.single.content!.toJson().toDart();
    expect(
      (((replay['parts']! as List).single as Map)['functionCall']! as Map)['args'],
      'not-an-object',
    );
  });

  test('keeps computer-use calls as provider-tagged application actions', () {
    final provider = GoogleProvider(apiKey: 'secret');
    addTearDown(provider.close);
    final response = NativeResponse(
      value: GoogleGenerateContentResponse.fromJson(
        JsonObject({
          'candidates': [
            {
              'content': {
                'role': 'model',
                'parts': [
                  {
                    'functionCall': {
                      'id': 'computer-1',
                      'name': 'open_web_browser',
                      'args': {'url': 'https://example.com'},
                    },
                    'thoughtSignature': 'computer-signature',
                  },
                ],
              },
              'finishReason': 'FUNCTION_CALL',
            },
          ],
        }),
      ),
      payload: NativePayload(
        providerId: 'google',
        api: 'generateContent',
        modelId: 'gemini-test',
        json: JsonObject({}),
      ),
      metadata: ResponseMetadata(statusCode: 200),
    );
    final request = GoogleGenerateContentRequest(
      model: 'models/gemini-test',
      contents: [
        GoogleContent(role: 'user', parts: [GooglePart.text('browse')]),
      ],
      tools: [
        GoogleComputerUseTool(JsonObject({'environment': 'ENVIRONMENT_BROWSER'})),
      ],
    );

    final call = provider.generateContent
        .normalize(response, request: request)
        .message
        .parts
        .whereType<ApplicationToolCallPart>()
        .single;

    expect(call.id, 'computer-1');
    expect(call.arguments, isA<NativeToolArguments>());
    final action = (call.arguments as NativeToolArguments).action.toDart();
    expect(action['thoughtSignature'], 'computer-signature');
    expect(((action['functionCall']! as Map)['args']! as Map)['url'], 'https://example.com');
  });
}

Matcher _failedWith<E extends AiError>() => isA<Failed<Object?, AiError>>().having(
  (failure) => (failure.cause as Expected<AiError>).error,
  'error',
  isA<E>(),
);

GoogleProvider _provider(HttpServer server) => GoogleProvider(
  apiKey: 'secret',
  baseUrl: Uri.parse('http://${server.address.address}:${server.port}'),
);

void _json(HttpRequest request, Map<String, Object?> body) {
  request.response
    ..headers.contentType = ContentType.json
    ..write(jsonEncode(body));
}

const _toolResponse = <String, Object?>{
  'candidates': [
    {
      'content': {
        'role': 'model',
        'parts': [
          {'text': 'I will look that up.', 'thoughtSignature': 'signed-thought'},
          {
            'functionCall': {
              'id': 'call-1',
              'name': 'lookup',
              'args': {'query': 'answer'},
            },
          },
          {
            'executableCode': {'language': 'PYTHON', 'code': 'print(42)'},
          },
          {
            'codeExecutionResult': {'outcome': 'OUTCOME_OK', 'output': '42'},
          },
        ],
      },
      'finishReason': 'FUNCTION_CALL',
      'groundingMetadata': {
        'groundingChunks': [
          {
            'web': {'uri': 'https://source.example/page', 'title': 'Source'},
          },
        ],
      },
      'futureCandidate': true,
    },
  ],
  'usageMetadata': {'promptTokenCount': 3, 'candidatesTokenCount': 4, 'totalTokenCount': 7},
};
