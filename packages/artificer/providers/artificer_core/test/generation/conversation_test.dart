import 'package:artificer_core/artificer_core.dart';
import 'package:test/test.dart';

void main() {
  group('GenerationRequest', () {
    ToolCallPart call(String id, [ToolArguments? arguments]) => ToolCallPart(
      callId: id,
      name: 'lookup',
      arguments: arguments ?? const JsonToolArguments(value: {'q': 'x'}, original: '{"q":"x"}'),
    );
    InvalidRequestError? validate(List<Message> messages) =>
        GenerationRequest(messages: messages)
            .validate(providerId: 'p', api: 'responses', modelId: 'm');
    test('should accept ordered tools and application failures', () {
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
      expect(request.validate(providerId: 'p', api: 'responses', modelId: 'm'), isNull);
      expect((request.messages[2] as ToolMessage).results.map((r) => r.callId), ['b', 'a']);
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
  group('ToolArguments', () {
    test('should retain malformed original arguments without fabricating an object', () {
      for (final text in ['{"unfinished":', '[]', 'null']) {
        final arguments = ToolArguments.parse(text);
        expect(arguments, isA<MalformedToolArguments>());
        expect((arguments as MalformedToolArguments).original, text);
      }
      expect((ToolArguments.parse('{"x":1}') as JsonToolArguments).original, '{"x":1}');
    });
  });
  group('ProviderReplay', () {
    test('should clear replay on content edits and reject incompatible targets', () {
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
      expect(message.text, 'onetwo');
      expect(message.withParts([const TextOutputPart('edit')]).replay, isNull);
      final request = GenerationRequest(messages: [message]);
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
        () => ProviderReplay(
          providerId: 'p',
          api: 'responses',
          modelId: 'm',
          items: [],
          schemaVersion: 2,
        ),
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
        expect(result.text, isEmpty);
        expect(result.finishReason, reason);
        expect(result.usage, isNull);
      }
    });
  });
}
