import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/src/protocols/chat/chat_codec.dart';
import 'package:artificer_core/src/protocols/chat/chat_dialect.dart';
import 'package:artificer_core/src/protocols/chat/chat_models.dart';
import 'package:artificer_core/src/protocols/chat/chat_stream.dart';
import 'package:artificer_core/transport.dart';
import 'package:conflux/result.dart';
import 'package:test/test.dart';

void main() {
  final codec = ChatCodec(
    ChatDialect(providerId: 'fixture', api: 'chat', endpoint: Uri.parse('http://localhost/chat')),
  );
  group('ChatCodec', () {
    test('should preserve ordered multipart tools, schemas, options and unknown model IDs', () {
      final schema = <String, Object?>{
        'type': 'object',
        'properties': {
          'optional': {'type': 'string'},
        },
        'required': <Object?>[],
      };
      final request = GenerationRequest(
        instructions: 'instruction',
        messages: [
          UserMessage.text('hello'),
          AssistantMessage([
            ToolCallPart(
              callId: 'call',
              name: 'lookup',
              arguments: const JsonToolArguments(value: {'q': 'x'}),
            ),
          ]),
          ToolMessage([
            ToolSuccess(
              callId: 'call',
              content: const TextToolResultContent(parts: ['one', 'two']),
            ),
          ]),
        ],
        tools: [FunctionTool(name: 'lookup', inputSchema: schema)],
        toolChoice: NamedToolChoice(name: 'lookup'),
        output: JsonSchemaOutput(name: 'answer', schema: schema),
        options: const GenerationOptions(temperature: Setting.clear()),
      );
      final result = codec.request(
        'unknown:model',
        request,
        defaults: const GenerationOptions(temperature: Setting.set(0.8)),
        options: const ChatOptions(
          seed: Setting.set(7),
          extraBody: Setting.set({'future_text_hint': true}),
        ),
      );
      final body = (result as Success<Map<String, Object?>, AiError>).value;
      expect(body['model'], 'unknown:model');
      expect(body['n'], 1);
      expect(body['store'], false);
      expect(body['max_tokens'], 4096);
      expect(body.containsKey('temperature'), false);
      expect(body['seed'], 7);
      final messages = body['messages']! as List<Map<String, Object?>>;
      expect(messages.map((item) => item['role']), ['system', 'user', 'assistant', 'tool']);
      expect(messages.last['content'], [
        {'type': 'text', 'text': 'one'},
        {'type': 'text', 'text': 'two'},
      ]);
      expect(((body['response_format']! as Map)['json_schema']! as Map)['schema'], same(schema));
      expect(schema['required'], isEmpty);
    });

    test('should reject scope bypass and collisions for both common and native requests', () {
      final request = GenerationRequest(messages: [UserMessage.text('x')]);
      for (final extras in [
        {'messages': <Object?>[]},
        {'seed': 2},
        {'image_url': 'x'},
        {'background': true},
        {'previous_response_id': 'x'},
      ]) {
        expect(
          codec.request('m', request, options: ChatOptions(extraBody: Setting.set(extras))),
          isA<Failure<Map<String, Object?>, AiError>>(),
        );
        expect(
          codec.nativeRequest(
            NativeChatRequest(
              model: 'm',
              messages: [
                {'role': 'user', 'content': 'x'},
              ],
              extraBody: extras,
            ),
          ),
          isA<Failure<Map<String, Object?>, AiError>>(),
        );
      }
      expect(
        codec.nativeRequest(
          NativeChatRequest(
            model: 'm',
            messages: [
              {
                'role': 'user',
                'content': [
                  {'type': 'image_url', 'image_url': 'x'},
                ],
              },
            ],
          ),
        ),
        isA<Failure<Map<String, Object?>, AiError>>(),
      );
    });

    test('should reject invalid nested JSON before encoding tool arguments or results', () {
      final cyclic = <String, Object?>{};
      cyclic['self'] = cyclic;
      for (final value in <Object?>[
        DateTime(2026),
        double.infinity,
        cyclic,
        {'nested': DateTime(2026)},
      ]) {
        final request = GenerationRequest(
          messages: [
            AssistantMessage([
              ToolCallPart(
                callId: 'call',
                name: 'f',
                arguments: const JsonToolArguments(value: {}),
              ),
            ]),
            ToolMessage([
              ToolSuccess(
                callId: 'call',
                content: JsonToolResultContent(value: value),
              ),
            ]),
          ],
        );
        final result = codec.request('m', request);
        expect(
          result,
          isA<Failure<Map<String, Object?>, AiError>>().having(
            (failure) => failure.error,
            'error',
            isA<InvalidRequestError>(),
          ),
        );
      }
    });

    test('should require choice selection and preserve typed, raw and replay views', () {
      final raw = <String, Object?>{
        'id': 'r',
        'model': 'm',
        'unknown': {'nested': true},
        'choices': [
          {
            'index': 0,
            'finish_reason': 'length',
            'message': {'role': 'assistant', 'content': 'first'},
          },
          {
            'index': 7,
            'finish_reason': 'tool_calls',
            'message': {
              'role': 'assistant',
              'tool_calls': [
                {
                  'id': 'c',
                  'type': 'function',
                  'function': {'name': 'f', 'arguments': '{truncated'},
                },
              ],
              'signature': 'opaque',
            },
          },
        ],
      };
      final native = (codec.decode(
        raw,
        const ResponseMetadata(statusCode: 200),
      ) as Success<NativeResponse<ChatResponse>, AiError>).value;
      expect(codec.normalize(native), isA<Failure<GenerationResult, AiError>>());
      final result =
          (codec.normalize(native, choiceIndex: 7) as Success<GenerationResult, AiError>).value;
      expect(
        result.message.parts.single,
        isA<ToolCallPart>().having(
          (part) => part.arguments,
          'arguments',
          isA<MalformedToolArguments>(),
        ),
      );
      expect(result.native.data, same(raw));
      expect(result.message.replay!.items.single, (raw['choices']! as List)[1]['message']);
      expect(ChatResponse.fromJson(native.value.toJson()).choices.length, 2);
      expect(result.toString(), isNot(contains('signature')));
    });

    test('should retain an unknown streamed native tool as opaque output', () {
      final state = ChatStreamAssembly(codec, 'm')..start(const ResponseMetadata(statusCode: 200));
      final accepted = state.accept(
        const SseEvent(
          data: '{"model":"m","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"native","type":"future_tool","payload":{"unknown":true}}]},"finish_reason":"stop"}]}',
        ),
      );
      expect(accepted, isA<Success<List<GenerationEvent>, AiError>>());
      state.accept(const SseEvent(data: '[DONE]'));
      expect(state.finishParts(), isA<Success<List<GenerationEvent>, AiError>>());
      final result = (state.complete() as Success<GenerationFinished, AiError>).value.result;
      expect(result.message.parts.single, isA<OpaqueOutputPart>());
      expect((result.message.parts.single as OpaqueOutputPart).data, {
        'id': 'native',
        'type': 'future_tool',
        'payload': {'unknown': true},
      });
    });

    test('should preserve unknown native choice fields across stream chunks', () {
      final state = ChatStreamAssembly(codec, 'm')..start(const ResponseMetadata(statusCode: 200));
      expect(
        state.accept(
          const SseEvent(
            data: '{"model":"m","choices":[{"index":0,"vendor":{"z":true},"delta":{"role":"assistant","content":"a"}}]}',
          ),
        ),
        isA<Success<List<GenerationEvent>, AiError>>(),
      );
      expect(
        state.accept(
          const SseEvent(
            data: '{"choices":[{"index":0,"delta":{"content":"b"},"finish_reason":"stop"}]}',
          ),
        ),
        isA<Success<List<GenerationEvent>, AiError>>(),
      );
      state.accept(const SseEvent(data: '[DONE]'));
      expect(state.finishParts(), isA<Success<List<GenerationEvent>, AiError>>());
      final result = (state.complete() as Success<GenerationFinished, AiError>).value.result;
      expect(((result.native.data! as Map)['choices']! as List).single['vendor'], {'z': true});
      expect(result.text, 'ab');
    });
  });
}
