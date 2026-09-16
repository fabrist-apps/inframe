import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/protocols.dart';
import 'package:conflux/result.dart';
import 'package:test/test.dart';

import 'responses_fixtures.dart';

T value<T>(Result<T, AiError> result) => switch (result) {
  Success(:final value) => value,
  Failure(:final error) => throw StateError(error.message),
};

void main() {
  final codec = ResponsesCodec(
    ResponsesDialect(
      providerId: 'synthetic',
      route: (_) => Uri.parse('https://example.test/responses'),
      authentication: () => {},
    ),
  );
  group('ResponsesCodec', () {
    test('should forward ordered freeform native success and application errors', () {
      final request = GenerationRequest(
        messages: [
          AssistantMessage([
            ToolCallPart(
              callId: 'free',
              name: 'custom',
              arguments: const FreeFormToolArguments(text: 'run text'),
            ),
            ToolCallPart(
              callId: 'native',
              name: 'shell',
              arguments: const NativeToolArguments(
                providerId: 'synthetic',
                api: 'responses',
                value: {
                  'type': 'shell_call',
                  'call_id': 'native',
                  'action': {'command': 'pwd'},
                },
              ),
            ),
          ]),
          ToolMessage([
            ToolFailure(
              callId: 'free',
              content: const TextToolResultContent(parts: ['failed', 'details']),
            ),
            ToolSuccess(
              callId: 'native',
              content: const NativeToolResultContent(
                providerId: 'synthetic',
                api: 'responses',
                value: {
                  'type': 'shell_call_output',
                  'call_id': 'native',
                  'output': {'exit_code': 0},
                },
              ),
            ),
          ]),
        ],
      );
      final native = value(codec.encode(request, 'm'));
      expect(native.input.map((item) => item['type']), [
        'custom_tool_call',
        'shell_call',
        'custom_tool_call_output',
        'shell_call_output',
      ]);
      expect(native.input[2]['status'], 'failed');
      expect(native.input[2]['output'], [
        {'type': 'input_text', 'text': 'failed'},
        {'type': 'input_text', 'text': 'details'},
      ]);
      expect(native.input[3]['output'], {'exit_code': 0});
    });

    test('should distinguish schema keywords from application property names', () {
      final strict = ResponsesCodec(
        ResponsesDialect(
          providerId: 'p',
          route: (_) => Uri.parse('https://example.test'),
          authentication: () => {},
          unsupportedSchemaKeywords: {'oneOf'},
        ),
      );
      expect(
        strict.prepare(
          const ResponsesRequest(
            model: 'm',
            input: [
              {'role': 'user', 'content': 'x'},
            ],
            text: {
              'format': {
                'type': 'json_schema',
                'schema': {
                  'type': 'object',
                  'properties': {
                    'oneOf': {'type': 'string'},
                  },
                  'default': {'oneOf': 'data'},
                },
              },
            },
          ),
        ),
        isA<Success<Map<String, Object?>, AiError>>(),
      );
    });

    test('should preserve native replay order signatures citations and pending tools', () {
      final codec = ResponsesCodec(
        ResponsesDialect(
          providerId: 'synthetic',
          route: (_) => Uri.parse('https://example.test'),
          authentication: () => {},
          hostedToolTypes: {'web_search'},
        ),
      );
      final data = responseFixture();
      final response = value(codec.decode(data));
      final raw = NativePayload(
        providerId: 'synthetic',
        api: 'responses',
        modelId: 'm',
        data: data,
      );
      final result = value(codec.normalize(response, raw));
      expect(result.text, 'hello');
      expect(result.finishReason, FinishReason.toolCalls);
      expect(result.usage!.totalTokens, isNull);
      expect((result.message.parts.last as ProviderToolPart).status, ToolStatus.pending);
      expect(result.message.parts.whereType<ToolCallPart>().single.callId, 'call');
      final restored = GenerationResult.fromJson(result.toJson());
      expect(restored.native.data, data);
      final request = value(
        codec.encode(
          GenerationRequest(
            messages: [
              restored.message,
              ToolMessage([
                ToolSuccess(
                  callId: 'call',
                  content: const JsonToolResultContent(value: {'found': true}),
                ),
              ]),
            ],
          ),
          'm',
        ),
      );
      expect(request.input.take(4).toList(), data['output']);
      expect(request.input.last['call_id'], 'call');
      expect(value(codec.prepare(request)).containsKey('previous_response_id'), isFalse);
      expect(ResponsesResponse.fromJson(response.toJson()).toMap(), response.toMap());
      expect(ResponsesRequest.fromJson(request.toJson()).toMap(), request.toMap());
      expect(
        ResponsesOptions.fromJson(const ResponsesOptions().toJson()).toMap(),
        const ResponsesOptions().toMap(),
      );
    });
    test('should preserve freeform malformed native and opaque variants distinctly', () {
      expect(
        (value(
                  codec.normalizeItem({
                    'type': 'custom_tool_call',
                    'call_id': 'c',
                    'name': 'custom',
                    'input': 'not JSON',
                  }),
                ).single
                as ToolCallPart)
            .arguments,
        isA<FreeFormToolArguments>(),
      );
      expect(
        (value(
                  codec.normalizeItem({
                    'type': 'function_call',
                    'call_id': 'c',
                    'name': 'custom',
                    'arguments': '{',
                  }),
                ).single
                as ToolCallPart)
            .arguments,
        isA<MalformedToolArguments>(),
      );
      expect(
        value(codec.normalizeItem({'type': 'reasoning', 'encrypted_content': 'secret'})).single,
        isA<OpaqueOutputPart>(),
      );
      expect(
        value(
          codec.normalizeItem({
            'type': 'future',
            'nested': {'x': 1},
          }),
        ).single,
        isA<OpaqueOutputPart>(),
      );
      final hooked = ResponsesCodec(
        ResponsesDialect(
          providerId: 'synthetic',
          route: (_) => Uri.parse('https://example.test'),
          authentication: () => {},
          toolItem: (item) => item['type'] == 'shell_call'
              ? Success(
                  ToolCallPart(
                    callId: item['call_id']! as String,
                    name: 'shell',
                    arguments: NativeToolArguments(
                      providerId: 'synthetic',
                      api: 'responses',
                      value: item,
                    ),
                  ),
                )
              : null,
        ),
      );
      expect(
        (value(
                  hooked.normalizeItem({
                    'type': 'shell_call',
                    'call_id': 'c',
                    'action': {'command': 'pwd'},
                  }),
                ).single
                as ToolCallPart)
            .arguments,
        isA<NativeToolArguments>(),
      );
    });
    test('should require explicit candidate selection and preserve empty refusal outcomes', () {
      final raw = NativePayload(
        providerId: 'synthetic',
        api: 'responses',
        modelId: 'm',
        data: responseFixture(),
      );
      final response = ResponsesResponse(
        id: 'multiple',
        model: 'm',
        status: 'completed',
        output: [],
        candidates: [
          responseFixture(),
          {...responseFixture(), 'id': 'second'},
        ],
      );
      expect(codec.normalize(response, raw), isA<Failure<GenerationResult, AiError>>());
      expect(value(codec.normalize(response, raw, candidateIndex: 1)).responseId, 'second');
      expect(
        value(
          codec.normalize(
            const ResponsesResponse(
              id: 'empty',
              model: 'm',
              status: 'incomplete',
              output: [],
              incompleteDetails: {'reason': 'content_filter'},
            ),
            raw,
          ),
        ).finishReason,
        FinishReason.contentFilter,
      );
    });
    test(
      'should reject unsupported stop schema collisions and deferred extras before execution',
      () {
        expect(
          codec.encode(
            GenerationRequest(
              messages: [UserMessage.text('x')],
              options: const GenerationOptions(stop: Setting.set(['stop'])),
            ),
            'm',
          ),
          isA<Failure<ResponsesRequest, AiError>>(),
        );
        for (final extra in <Map<String, Object?>>[
          {'store': true},
          {'previous_response_id': 'r'},
          {'background': true},
          {'input': []},
          {
            'tools': [
              {'type': 'image_generation'},
            ],
          },
        ]) {
          expect(
            codec.prepare(
              ResponsesRequest(
                model: 'm',
                input: [
                  {'role': 'user', 'content': 'x'},
                ],
                extraBody: extra,
              ),
            ),
            isA<Failure<Map<String, Object?>, AiError>>(),
          );
        }
        final strict = ResponsesCodec(
          ResponsesDialect(
            providerId: 's',
            route: (_) => Uri.parse('https://example.test'),
            authentication: () => {},
            unsupportedSchemaKeywords: {'oneOf'},
          ),
        );
        expect(
          strict.prepare(
            const ResponsesRequest(
              model: 'm',
              input: [
                {'role': 'user', 'content': 'x'},
              ],
              text: {
                'format': {
                  'type': 'json_schema',
                  'schema': {'oneOf': <Object?>[]},
                },
              },
            ),
          ),
          isA<Failure<Map<String, Object?>, AiError>>(),
        );
        expect(
          codec.prepare(
            const ResponsesRequest(
              model: 'm',
              input: [
                {'type': 'input_image', 'image_url': 'https://example.test'},
              ],
            ),
          ),
          isA<Failure<Map<String, Object?>, AiError>>(),
        );
        expect(
          codec.prepare(
            const ResponsesRequest(
              model: 'm',
              input: [
                {'role': 'user', 'content': 'x'},
              ],
              tools: [
                {'type': 'web_search'},
              ],
            ),
          ),
          isA<Failure<Map<String, Object?>, AiError>>(),
        );
      },
    );
    test('should preserve schema faithfully and use alternate instruction placement', () {
      const schema = {
        'type': 'object',
        'properties': {
          'x': {'type': 'integer'},
        },
        'required': ['x'],
        'additionalProperties': false,
      };
      final alternate = ResponsesCodec(
        ResponsesDialect(
          providerId: 'alt',
          api: 'alt-responses',
          route: (_) => Uri.parse('https://example.test'),
          authentication: () => {'x-key': 'test'},
          instructionRole: 'developer',
        ),
      );
      final request = value(
        alternate.encode(
          GenerationRequest(
            messages: [UserMessage.text('x')],
            instructions: 'rules',
            output: JsonSchemaOutput(name: 'answer', schema: schema),
          ),
          'm',
        ),
      );
      final wire = value(alternate.prepare(request));
      expect(wire['store'], false);
      expect(wire.containsKey('instructions'), false);
      expect((wire['input']! as List).first, {
        'role': 'developer',
        'content': [
          {'type': 'input_text', 'text': 'rules'},
        ],
      });
      expect(((wire['text']! as Map)['format'] as Map)['schema'], schema);
      expect(wire.containsKey('schemaVersion'), false);
    });
    test('should return protocol errors for malformed native required fields', () {
      expect(codec.decode({'id': 'missing'}), isA<Failure<ResponsesResponse, AiError>>());
      expect(
        codec.normalizeItem({
          'type': 'function_call',
          'call_id': '',
          'name': 'x',
          'arguments': '{}',
        }),
        isA<Failure<List<OutputPart>, AiError>>(),
      );
      expect(
        codec.normalizeItem({
          'type': 'message',
          'content': [
            {
              'type': 'output_text',
              'text': 'x',
              'annotations': [
                {'url': 3},
              ],
            },
          ],
        }),
        isA<Failure<List<OutputPart>, AiError>>(),
      );
    });

    test('should reject native result payload that contradicts the referenced call', () {
      final request = GenerationRequest(
        messages: [
          AssistantMessage([
            ToolCallPart(
              callId: 'call',
              name: 'run',
              arguments: const NativeToolArguments(
                providerId: 'synthetic',
                api: 'responses',
                value: {'type': 'shell_call', 'call_id': 'call'},
              ),
            ),
          ]),
          ToolMessage([
            ToolSuccess(
              callId: 'call',
              content: const NativeToolResultContent(
                providerId: 'synthetic',
                api: 'responses',
                value: {'type': 'shell_call_output', 'call_id': 'other', 'output': 'ok'},
              ),
            ),
          ]),
        ],
      );
      expect(codec.encode(request, 'm'), isA<Failure<ResponsesRequest, AiError>>());
    });
  });
}
