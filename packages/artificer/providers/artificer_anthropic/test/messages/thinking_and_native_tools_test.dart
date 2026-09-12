import 'dart:convert';
import 'dart:io';

import 'package:artificer_anthropic/artificer_anthropic.dart';
import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/json.dart';
import 'package:conflux/conflux.dart';
import 'package:test/test.dart';

void main() {
  group('Anthropic thinking and native tools', () {
    test('should preserve ownership and replay a complete paused tool turn', () async {
      final requests = <HttpRequest>[];
      final bodies = <Map<String, Object?>>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        requests.add(request);
        bodies.add(jsonDecode(await utf8.decoder.bind(request).join())! as Map<String, Object?>);
        request.response
          ..headers.contentType = ContentType.json
          ..write(jsonEncode(bodies.length == 1 ? _pausedMessage : _finalMessage));
        await request.response.close();
      });
      final provider = AnthropicProvider(
        apiKey: 'secret',
        baseUrl: Uri.parse('http://${server.address.address}:${server.port}/v1'),
      );
      addTearDown(provider.close);
      final model = provider.languageModel(
        'future-model',
        options: AnthropicModelOptions(
          thinking: Setting.set(
            AnthropicEnabledThinking(
              budgetTokens: 2048,
              display: AnthropicThinkingDisplay.summarized,
            ),
          ),
          effort: const Setting.set(AnthropicEffort.high),
          serviceTier: const Setting.set(AnthropicServiceTier.standardOnly),
          betaFeatures: const Setting.set([
            AnthropicBeta.computerUse20250124,
            AnthropicBeta.mcpClient20251120,
          ]),
          nativeTools: Setting.set([
            AnthropicWebSearchTool(),
            AnthropicComputerTool(displayWidthPx: 1280, displayHeightPx: 720),
          ]),
          remoteMcpServers: Setting.set([
            AnthropicRemoteMcpServer(
              name: 'docs',
              url: Uri.parse('https://mcp.example.com/sse'),
              authorizationToken: 'mcp-secret',
              allowedTools: const ['search'],
              enabled: true,
            ),
          ]),
        ),
      );
      final request = GenerationRequest(
        messages: [UserMessage.text('Research and update the page.')],
        tools: [
          FunctionTool(
            name: 'weather',
            inputSchema: JsonObject({'type': 'object'}),
          ),
        ],
      );

      final first = await model.generate(request).runFuture();
      final computer = first.message.parts.whereType<ApplicationToolCallPart>().singleWhere(
        (part) => part.name == 'computer',
      );
      final providerRecords = first.message.parts.whereType<ProviderToolRecordPart>().toList();
      final second = await model
          .generate(
            GenerationRequest(
              messages: [
                ...request.messages,
                first.message,
                ToolMessage([
                  NativeToolResult(
                    callId: computer.id,
                    providerId: 'anthropic',
                    api: 'messages',
                    value: JsonObject({
                      'type': 'tool_result',
                      'tool_use_id': computer.id,
                      'content': 'Clicked.',
                    }),
                  ),
                ]),
              ],
              tools: request.tools,
            ),
          )
          .runFuture();

      expect(first.finishReason, FinishReason.paused);
      expect(first.nativeFinishReason, 'pause_turn');
      expect(first.message.parts.whereType<ReasoningSummaryPart>().single.text, 'Check sources.');
      expect(computer.arguments, isA<NativeToolArguments>());
      expect((computer.arguments as NativeToolArguments).action.toDart(), {
        'action': 'left_click',
        'coordinate': [50, 80],
      });
      expect(providerRecords, hasLength(2));
      expect(providerRecords.first.owner, ToolExecutionOwner.provider);
      expect(providerRecords.first.status, ProviderToolStatus.pending);
      expect(providerRecords.last.status, ProviderToolStatus.completed);
      expect(first.message.parts.whereType<OpaqueOutputPart>().map((part) => part.kind), [
        'redacted_thinking',
        'container_upload',
      ]);
      expect(
        first.message.toJson().toDart(),
        Message.fromJson(first.message.toJson()).toJson().toDart(),
      );
      expect(second.text, 'Done.');

      expect(
        requests.first.headers.value('anthropic-beta'),
        'computer-use-2025-01-24,mcp-client-2025-11-20',
      );
      expect(bodies.first['thinking'], {
        'type': 'enabled',
        'budget_tokens': 2048,
        'display': 'summarized',
      });
      expect(bodies.first['output_config'], {'effort': 'high'});
      expect(bodies.first['service_tier'], 'standard_only');
      expect((bodies.first['tools']! as List).map((item) => (item as Map)['name']), [
        'weather',
        'web_search',
        'computer',
      ]);
      expect(bodies.first['mcp_servers'], [
        {
          'type': 'url',
          'name': 'docs',
          'url': 'https://mcp.example.com/sse',
          'authorization_token': 'mcp-secret',
          'tool_configuration': {
            'allowed_tools': ['search'],
            'enabled': true,
          },
        },
      ]);
      final replay = ((bodies[1]['messages']! as List)[1] as Map)['content'];
      expect(replay, _pausedMessage['content']);
      expect(((bodies[1]['messages']! as List)[2] as Map)['content'], [
        {'type': 'tool_result', 'tool_use_id': 'computer_1', 'content': 'Clicked.'},
      ]);
    });

    test('should reject conflicting tool names and mismatched native results before I/O', () async {
      final provider = AnthropicProvider(apiKey: 'secret');
      addTearDown(provider.close);
      final request = GenerationRequest(
        messages: [UserMessage.text('Use the computer.')],
        tools: [
          FunctionTool(name: 'computer', inputSchema: JsonObject({'type': 'object'})),
        ],
      );
      final duplicate = provider.languageModel(
        'model',
        options: AnthropicModelOptions(
          nativeTools: Setting.set([
            AnthropicComputerTool(displayWidthPx: 1, displayHeightPx: 1),
          ]),
        ),
      );

      expect(await duplicate.generate(request).runFutureExit(), _failedWith<InvalidRequestError>());

      final replay = AssistantMessage([
        ApplicationToolCallPart(
          id: 'computer_1',
          name: 'computer',
          arguments: NativeToolArguments(
            providerId: 'anthropic',
            api: 'messages',
            action: JsonObject({'action': 'screenshot'}),
          ),
        ),
      ]);
      expect(
        () => GenerationRequest(
          messages: [
            UserMessage.text('Look.'),
            replay,
            ToolMessage([
              NativeToolResult(
                callId: 'computer_1',
                providerId: 'openai',
                api: 'responses',
                value: JsonObject({
                  'type': 'tool_result',
                  'tool_use_id': 'computer_1',
                  'content': 'done',
                }),
              ),
            ]),
          ],
        ),
        throwsArgumentError,
      );
    });

    test('should not infer native ownership from an application tool name', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        await request.drain<void>();
        request.response
          ..headers.contentType = ContentType.json
          ..write(jsonEncode(_pausedMessage));
        await request.response.close();
      });
      final provider = AnthropicProvider(
        apiKey: 'secret',
        baseUrl: Uri.parse('http://${server.address.address}:${server.port}/v1'),
      );
      addTearDown(provider.close);

      final result = await provider
          .languageModel('future-model')
          .generate(
            GenerationRequest(
              messages: [UserMessage.text('Use my computer function.')],
              tools: [
                FunctionTool(
                  name: 'computer',
                  inputSchema: JsonObject({'type': 'object'}),
                ),
              ],
            ),
          )
          .runFuture();

      final call = result.message.parts.whereType<ApplicationToolCallPart>().singleWhere(
        (part) => part.name == 'computer',
      );
      expect(call.arguments, isA<JsonToolArguments>());
    });

    test('should allow an omitted thinking signature only in a block-start event', () {
      final startRaw = JsonObject({
        'type': 'content_block_start',
        'index': 0,
        'content_block': {'type': 'thinking', 'thinking': ''},
      });

      final event = AnthropicMessageEvent.fromJson(startRaw) as AnthropicContentBlockStartEvent;
      final thinking = event.contentBlock as AnthropicThinkingBlock;

      expect(thinking.signature, isEmpty);
      expect(thinking.raw.toDart(), {'type': 'thinking', 'thinking': ''});
      expect(
        () => AnthropicContentBlock.fromJson(
          JsonObject({'type': 'thinking', 'thinking': 'Complete.'}),
        ),
        throwsFormatException,
      );
      expect(
        () => AnthropicMessage.fromJson(
          JsonObject({
            ..._finalMessage,
            'content': [
              {'type': 'thinking', 'thinking': 'Complete.'},
            ],
          }),
        ),
        throwsFormatException,
      );
      expect(
        () => AnthropicMessageEvent.fromJson(
          JsonObject({
            'type': 'content_block_start',
            'index': 0,
            'content_block': {
              'type': 'thinking',
              'thinking': '',
              'signature': null,
            },
          }),
        ),
        throwsFormatException,
      );
    });

    test('should encode only string or native-block tool-result content', () {
      final content = <AnthropicContentBlock>[
        AnthropicTextBlock('Done.'),
        AnthropicImageBlock.file('file_1'),
      ];
      final block = AnthropicToolResultBlock(
        toolUseId: 'tool_1',
        content: content,
        isError: true,
      );

      content.add(AnthropicTextBlock('Later mutation.'));

      expect(block.content, isA<List<AnthropicContentBlock>>());
      expect(block.toDart(), {
        'type': 'tool_result',
        'tool_use_id': 'tool_1',
        'content': [
          {'type': 'text', 'text': 'Done.'},
          {
            'type': 'image',
            'source': {'type': 'file', 'file_id': 'file_1'},
          },
        ],
        'is_error': true,
      });
      expect(
        () => (block.content as List<AnthropicContentBlock>).add(
          AnthropicTextBlock('Mutation.'),
        ),
        throwsUnsupportedError,
      );

      final decoded = AnthropicContentBlock.fromJson(
        JsonObject({
          'type': 'tool_result',
          'tool_use_id': 'tool_2',
          'content': [
            {'type': 'text', 'text': 'Decoded.'},
          ],
        }),
      ) as AnthropicToolResultBlock;
      expect(decoded.content, isA<List<AnthropicContentBlock>>());
      expect((decoded.content as List<AnthropicContentBlock>).single, isA<AnthropicTextBlock>());

      for (final invalid in <Object>[
        1,
        JsonObject({'status': 'done'}),
        <Object?>[
          {'type': 'text', 'text': 'Already encoded.'},
        ],
      ]) {
        expect(
          () => AnthropicToolResultBlock(toolUseId: 'tool_3', content: invalid),
          throwsArgumentError,
        );
      }
      expect(
        () => AnthropicContentBlock.fromJson(
          JsonObject({
            'type': 'tool_result',
            'tool_use_id': 'tool_4',
            'content': {'status': 'done'},
          }),
        ),
        throwsFormatException,
      );
      expect(
        () => AnthropicContentBlock.fromJson(
          JsonObject({
            'type': 'tool_result',
            'tool_use_id': 'tool_5',
            'content': ['not-a-block'],
          }),
        ),
        throwsFormatException,
      );
    });
  });
}

Matcher _failedWith<E extends AiError>() => isA<Failed<Object?, AiError>>().having(
  (failure) => failure.cause,
  'cause',
  isA<Expected<AiError>>().having((expected) => expected.error, 'error', isA<E>()),
);

const _pausedMessage = <String, Object?>{
  'id': 'msg_paused',
  'type': 'message',
  'role': 'assistant',
  'model': 'future-model',
  'content': [
    {
      'type': 'thinking',
      'thinking': 'Check sources.',
      'signature': 'signed-thinking',
    },
    {'type': 'redacted_thinking', 'data': 'encrypted-thinking'},
    {
      'type': 'server_tool_use',
      'id': 'search_1',
      'name': 'web_search',
      'input': {'query': 'Anthropic'},
      'caller': {'type': 'direct'},
    },
    {
      'type': 'web_search_tool_result',
      'tool_use_id': 'search_1',
      'content': [
        {
          'type': 'web_search_result',
          'url': 'https://example.com/source',
          'title': 'Source',
        },
      ],
    },
    {
      'type': 'tool_use',
      'id': 'computer_1',
      'name': 'computer',
      'input': {
        'action': 'left_click',
        'coordinate': [50, 80],
      },
      'caller': {'type': 'direct'},
    },
    {
      'type': 'text',
      'text': 'I found a source.',
      'citations': [
        {
          'type': 'web_search_result_location',
          'url': 'https://example.com/source',
          'title': 'Source',
        },
      ],
    },
    {
      'type': 'container_upload',
      'file_id': 'file_artifact',
      'future_metadata': {'origin': 'hosted-tool'},
    },
  ],
  'stop_reason': 'pause_turn',
  'stop_sequence': null,
  'stop_details': {'type': 'pause_turn', 'reason': 'hosted work pending'},
  'usage': {'input_tokens': 20, 'output_tokens': 12},
  'future_response_field': true,
};

const _finalMessage = <String, Object?>{
  'id': 'msg_done',
  'type': 'message',
  'role': 'assistant',
  'model': 'future-model',
  'content': [
    {'type': 'text', 'text': 'Done.', 'citations': null},
  ],
  'stop_reason': 'end_turn',
  'stop_sequence': null,
  'usage': {'input_tokens': 34, 'output_tokens': 2},
};
