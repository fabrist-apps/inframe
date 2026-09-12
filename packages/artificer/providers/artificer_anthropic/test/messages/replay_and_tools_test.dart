import 'dart:convert';
import 'dart:io';

import 'package:artificer_anthropic/artificer_anthropic.dart';
import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/json.dart';
import 'package:conflux/conflux.dart';
import 'package:test/test.dart';

void main() {
  group('AnthropicLanguageModel', () {
    test('should map media, structured output, tools, and exact replay', () async {
      final bodies = <Map<String, Object?>>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        bodies.add(jsonDecode(await utf8.decoder.bind(request).join())! as Map<String, Object?>);
        request.response
          ..headers.contentType = ContentType.json
          ..write(jsonEncode(bodies.length == 1 ? _toolMessage : _finalMessage));
        await request.response.close();
      });
      final provider = AnthropicProvider(
        apiKey: 'secret',
        baseUrl: Uri.parse('http://${server.address.address}:${server.port}/v1'),
      );
      addTearDown(provider.close);
      final tool = FunctionTool(
        name: 'weather',
        description: 'Read weather',
        inputSchema: JsonObject({
          'type': 'object',
          'properties': {
            'city': {'type': 'string'},
          },
          'required': ['city'],
        }),
      );
      final request = GenerationRequest(
        instructions: 'Be direct.',
        messages: [
          UserMessage([
            TextInputPart('What is the weather?'),
            MediaInputPart(
              kind: MediaKind.image,
              mimeType: 'image/png',
              source: BytesMediaSource([0, 1, 2]),
            ),
            MediaInputPart(
              kind: MediaKind.document,
              mimeType: 'application/pdf',
              source: UrlMediaSource(Uri.parse('https://example.com/report.pdf')),
            ),
            MediaInputPart(
              kind: MediaKind.document,
              mimeType: 'application/pdf',
              source: ProviderFileSource(
                providerId: 'anthropic',
                api: 'messages',
                reference: 'file_1',
                mimeType: 'application/pdf',
              ),
            ),
          ]),
        ],
        tools: [tool],
        toolChoice: FunctionToolChoice('weather'),
        output: JsonSchemaOutputFormat(
          name: 'weather_result',
          schema: JsonObject({
            'type': 'object',
            'properties': {
              'summary': {'type': 'string'},
            },
          }),
        ),
      );
      final model = provider.languageModel(
        'future-model',
        options: AnthropicModelOptions(
          cacheControl: const Setting.set(
            AnthropicCacheControl(ttl: AnthropicCacheTtl.oneHour),
          ),
        ),
      );

      final first = await model.generate(request).runFuture();
      final call = first.message.parts.whereType<ApplicationToolCallPart>().single;
      final second = await model
          .generate(
            GenerationRequest(
              instructions: request.instructions,
              messages: [
                ...request.messages,
                first.message,
                ToolMessage([
                  JsonToolResult(
                    callId: call.id,
                    value: JsonObject({'temperature': 18}),
                  ),
                ]),
              ],
              tools: request.tools,
              toolChoice: request.toolChoice,
              options: request.options,
              output: request.output,
            ),
          )
          .runFuture();

      expect(second.text, '18 C');
      expect(call.name, 'weather');
      expect((call.arguments as JsonToolArguments).value.toDart(), {'city': 'Paris'});
      expect(
        first.message.toJson().toDart(),
        Message.fromJson(first.message.toJson()).toJson().toDart(),
      );
      expect(bodies.first['output_config'], {
        'format': {
          'type': 'json_schema',
          'schema': {
            'type': 'object',
            'properties': {
              'summary': {'type': 'string'},
            },
          },
        },
      });
      expect(bodies.first['cache_control'], {'type': 'ephemeral', 'ttl': '1h'});
      expect(bodies.first['tool_choice'], {'type': 'tool', 'name': 'weather'});
      expect(bodies.first['tools'], [
        {
          'name': 'weather',
          'description': 'Read weather',
          'input_schema': tool.inputSchema.toDart(),
        },
      ]);
      final firstContent = ((bodies.first['messages']! as List).single as Map)['content'] as List;
      expect(firstContent[1], {
        'type': 'image',
        'source': {'type': 'base64', 'media_type': 'image/png', 'data': 'AAEC'},
      });
      expect(firstContent[2], {
        'type': 'document',
        'source': {'type': 'url', 'url': 'https://example.com/report.pdf'},
      });
      expect(firstContent[3], {
        'type': 'document',
        'source': {'type': 'file', 'file_id': 'file_1'},
      });
      final replayContent = ((bodies[1]['messages']! as List)[1] as Map)['content'] as List;
      expect(replayContent, _toolMessage['content']);
      expect(((bodies[1]['messages']! as List)[2] as Map)['content'], [
        {
          'type': 'tool_result',
          'tool_use_id': 'tool_1',
          'content': '{"temperature":18}',
        },
      ]);
    });

    test('should reject unsupported media and typed extra collisions before I/O', () async {
      final provider = AnthropicProvider(apiKey: 'secret');
      addTearDown(provider.close);
      final audio = GenerationRequest(
        messages: [
          UserMessage([
            MediaInputPart(
              kind: MediaKind.audio,
              mimeType: 'audio/wav',
              source: BytesMediaSource([0]),
            ),
          ]),
        ],
      );
      final collision = GenerationRequest(messages: [UserMessage.text('hello')]);

      expect(
        await provider.languageModel('model').generate(audio).runFutureExit(),
        _failedWith<UnsupportedFeatureError>(),
      );
      expect(
        () => provider
            .languageModel(
              'model',
              options: AnthropicModelOptions(extraBody: JsonObject({'messages': []})),
            )
            .generate(collision),
        throwsArgumentError,
      );
    });
  });
}

Matcher _failedWith<E extends AiError>() => isA<Failed<Object?, AiError>>().having(
  (failure) => failure.cause,
  'cause',
  isA<Expected<AiError>>().having((expected) => expected.error, 'error', isA<E>()),
);

const _toolMessage = <String, Object?>{
  'id': 'msg_1',
  'type': 'message',
  'role': 'assistant',
  'content': [
    {'type': 'text', 'text': 'I will check.', 'citations': null},
    {
      'type': 'tool_use',
      'id': 'tool_1',
      'name': 'weather',
      'input': {'city': 'Paris'},
      'future': true,
    },
  ],
  'model': 'future-model',
  'stop_reason': 'tool_use',
  'stop_sequence': null,
  'usage': {'input_tokens': 12, 'output_tokens': 8},
};

const _finalMessage = <String, Object?>{
  'id': 'msg_2',
  'type': 'message',
  'role': 'assistant',
  'content': [
    {'type': 'text', 'text': '18 C', 'citations': null},
  ],
  'model': 'future-model',
  'stop_reason': 'end_turn',
  'stop_sequence': null,
  'usage': {'input_tokens': 20, 'output_tokens': 3},
};
