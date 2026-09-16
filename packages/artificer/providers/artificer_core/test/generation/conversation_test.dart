import 'package:artificer_core/artificer_core.dart';
import 'package:test/test.dart';

void main() {
  group('AssistantMessage', () {
    test('should preserve replay identity and ordered native blocks', () {
      final message = AssistantMessage.fromMap({
        'type': 'assistant',
        'schemaVersion': 1,
        'parts': <Object?>[],
        'replay': {
          'providerId': 'p',
          'api': 'responses',
          'modelId': 'm',
          'items': [
            {'id': 'r1', 'signature': 'signed', 'phase': 'final'},
          ],
          'schemaVersion': 1,
        },
      });
      expect(message.toMap()['replay'], isNotNull);
    });
  });

  group('GenerationRequest', () {
    ToolCallPart call(String id, [ToolArguments? arguments]) => ToolCallPart(
      callId: id,
      name: 'lookup',
      arguments: arguments ?? const JsonToolArguments(value: {'q': 'x'}, original: '{"q":"x"}'),
    );
    InvalidRequestError? validate(List<Message> messages) =>
        GenerationRequest(messages: messages)
            .validate(providerId: 'p', api: 'responses', modelId: 'm');
    test('should preserve ordered tools and application failures through persistence', () {
      final request = GenerationRequest(
        messages: [
          UserMessage.text('find'),
          AssistantMessage([call('a'), call('b', const FreeFormToolArguments(text: 'raw'))]),
          ToolMessage([
            ToolFailure(
              callId: 'b',
              content: const TextToolResultContent(parts: ['failed', 'details']),
            ),
            ToolSuccess(
              callId: 'a',
              content: const JsonToolResultContent(value: {'found': true}),
            ),
          ]),
        ],
        tools: [
          FunctionTool(name: 'lookup', inputSchema: {'type': 'object'}),
        ],
        output: JsonSchemaOutput(name: 'answer', schema: {'type': 'object'}),
      );
      final restored = GenerationRequest.fromJson(request.toJson());
      expect(restored.toMap(), request.toMap());
      expect(restored.validate(providerId: 'p', api: 'responses', modelId: 'm'), isNull);
      expect((restored.messages[2] as ToolMessage).results.map((r) => r.callId), ['b', 'a']);
    });
    test('should reject duplicate calls results and missing application calls', () {
      expect(
        validate([
          AssistantMessage([call('a'), call('a')]),
        ]),
        isA<InvalidRequestError>(),
      );
      final result = ToolSuccess(callId: 'a', content: const JsonToolResultContent(value: null));
      expect(
        validate([
          ToolMessage([result]),
        ]),
        isA<InvalidRequestError>(),
      );
      expect(
        validate([
          AssistantMessage([call('a')]),
          ToolMessage([result, result]),
        ]),
        isA<InvalidRequestError>(),
      );
      expect(
        validate([
          AssistantMessage([
            const ProviderToolPart(
              id: 'a',
              name: 'search',
              owner: ToolExecutionOwner.provider,
              native: {},
            ),
          ]),
          ToolMessage([result]),
        ]),
        isA<InvalidRequestError>(),
      );
    });
    test('should require matching native action target for native results', () {
      final result = ToolSuccess(
        callId: 'a',
        content: const NativeToolResultContent(
          providerId: 'p',
          api: 'responses',
          value: {'status': 'ok'},
        ),
      );
      final native = call(
        'a',
        const NativeToolArguments(providerId: 'p', api: 'responses', value: {'action': 'run'}),
      );
      expect(
        validate([
          AssistantMessage([native]),
          ToolMessage([result]),
        ]),
        isNull,
      );
      expect(
        validate([
          AssistantMessage([call('a')]),
          ToolMessage([result]),
        ]),
        isA<InvalidRequestError>(),
      );
      expect(
        validate([
          AssistantMessage([
            call('a', const NativeToolArguments(providerId: 'other', api: 'responses', value: {})),
          ]),
        ]),
        isA<InvalidRequestError>(),
      );
    });
    test('should reject conflicting declarations and undeclared named tools', () {
      final tool = FunctionTool(name: 'lookup', inputSchema: {});
      expect(
        GenerationRequest(
          messages: [UserMessage.text('x')],
          tools: [tool, tool],
        ).validate(providerId: 'p', api: 'responses', modelId: 'm'),
        isA<InvalidRequestError>(),
      );
      expect(
        GenerationRequest(
          messages: [UserMessage.text('x')],
          toolChoice: NamedToolChoice(name: 'absent'),
        ).validate(providerId: 'p', api: 'responses', modelId: 'm'),
        isA<InvalidRequestError>(),
      );
    });
  });
  group('ToolChoice and OutputFormat', () {
    test('should persist every policy and output format without callbacks', () {
      for (final choice in <ToolChoice>[
        const AutoToolChoice(),
        const NoToolChoice(),
        const RequiredToolChoice(),
        NamedToolChoice(name: 'lookup'),
      ]) {
        expect(ToolChoice.fromJson(choice.toJson()).toMap(), choice.toMap());
      }
      for (final output in <OutputFormat>[
        const TextOutput(),
        const JsonObjectOutput(),
        JsonSchemaOutput(
          name: 'answer',
          description: 'result',
          schema: {
            'type': 'object',
            'properties': {
              'x': {'type': 'integer'},
            },
            'required': ['x'],
            'additionalProperties': false,
          },
        ),
      ]) {
        expect(OutputFormat.fromJson(output.toJson()).toMap(), output.toMap());
      }
    });
  });
  group('ToolArguments', () {
    test('should retain malformed original arguments without fabricating an object', () {
      for (final text in ['{"unfinished":', '[]', 'null']) {
        final arguments = ToolArguments.parse(text);
        expect(arguments, isA<MalformedToolArguments>());
        expect((arguments as MalformedToolArguments).original, text);
        expect(ToolArguments.fromJson(arguments.toJson()).toMap(), arguments.toMap());
      }
      expect((ToolArguments.parse('{"x":1}') as JsonToolArguments).original, '{"x":1}');
    });
  });
  group('ProviderReplay', () {
    test('should round trip ordered opaque output and reject incompatible replay', () {
      final message = AssistantMessage(
        [
          const TextOutputPart(
            'one',
            citations: [
              Citation(data: {'native': 1}, url: 'https://example.test'),
            ],
          ),
          const ReasoningOutputPart(summary: 'public summary'),
          const RefusalOutputPart(text: 'refused'),
          const OpaqueOutputPart(providerId: 'p', api: 'responses', data: {'encrypted': 'blob'}),
          const ProviderToolPart(
            id: 'pending',
            name: 'search',
            owner: ToolExecutionOwner.provider,
            status: ToolStatus.pending,
            native: {'phase': 'pending'},
          ),
          const TextOutputPart('two'),
        ],
        replay: ProviderReplay(
          providerId: 'p',
          api: 'responses',
          modelId: 'm',
          items: [
            {'id': 'reasoning', 'signature': 'signed'},
            {'id': 'pending', 'status': 'pending'},
          ],
        ),
      );
      final restored = AssistantMessage.fromJson(message.toJson());
      expect(restored.toMap(), message.toMap());
      expect(restored.text, 'onetwo');
      expect(restored.withParts([const TextOutputPart('edit')]).replay, isNull);
      expect(restored.copyWith().replay, isNull);
      final request = GenerationRequest(messages: [restored]);
      expect(request.validate(providerId: 'p', api: 'responses', modelId: 'm'), isNull);
      expect(
        request.validate(providerId: 'p', api: 'responses', modelId: 'different'),
        isA<InvalidRequestError>(),
      );
      expect(
        request.validate(providerId: 'other', api: 'responses', modelId: 'm'),
        isA<InvalidRequestError>(),
      );
      expect(
        request.validate(providerId: 'p', api: 'chat', modelId: 'm'),
        isA<InvalidRequestError>(),
      );
      expect(
        () => ProviderReplay.fromMap({...restored.replay!.toMap(), 'schemaVersion': 2}),
        throwsA(anything),
      );
    });
    test('should retain ordinary mutable content and replay collections', () {
      final items = <Object?>[];
      final parts = <OutputPart>[];
      final message = AssistantMessage(
        parts,
        replay: ProviderReplay(providerId: 'p', api: 'a', modelId: 'm', items: items),
      );
      parts.add(const TextOutputPart('later'));
      items.add({'signature': 's'});
      expect(message.text, 'later');
      expect(message.replay!.items, hasLength(1));
      message.replay = null;
      expect(message.replay, isNull);
    });
    test('should preserve no-content outcomes and absent usage', () {
      for (final reason in FinishReason.values) {
        final result = GenerationResult(
          message: AssistantMessage([]),
          finishReason: reason,
          native: const NativePayload(providerId: 'p', api: 'a', modelId: 'm', data: {}),
        );
        final restored = GenerationResult.fromJson(result.toJson());
        expect(restored.text, isEmpty);
        expect(restored.finishReason, reason);
        expect(restored.usage, isNull);
      }
    });
  });
}
