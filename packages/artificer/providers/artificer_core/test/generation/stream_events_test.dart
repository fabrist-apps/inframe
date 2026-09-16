import 'package:artificer_core/artificer_core.dart';
import 'package:test/test.dart';

void main() {
  group('GenerationEvent', () {
    test('should round trip every event and typed delta using shipped mappers', () {
      final events = <GenerationEvent>[
        const GenerationStarted(responseId: 'r', requestId: 'request'),
        const PartStarted(
          id: 't',
          index: 2,
          kind: GenerationPartKind.toolCall,
          callId: 'call',
          name: 'lookup',
          owner: ToolExecutionOwner.application,
        ),
        const PartDelta(
          id: 'p',
          delta: TextDelta(text: 'text'),
        ),
        const PartDelta(
          id: 'r',
          delta: ReasoningDelta(text: 'summary'),
        ),
        const PartDelta(
          id: 't',
          delta: ToolArgumentsDelta(text: '{'),
        ),
        const PartFinished(id: 'p', part: TextOutputPart('done')),
        const UsageUpdated(usage: Usage(inputTokens: 1, outputTokens: 2)),
        const ProviderEvent(
          providerId: 'p',
          api: 'a',
          event: 'unknown',
          data: {
            'nested': [1, null],
          },
        ),
        GenerationFinished(
          GenerationResult(
            message: AssistantMessage([]),
            finishReason: FinishReason.refusal,
            native: const NativePayload(providerId: 'p', api: 'a', modelId: 'm', data: {}),
          ),
        ),
      ];
      for (final event in events) {
        expect(GenerationEvent.fromJson(event.toJson()).toMap(), event.toMap());
      }
    });

    test('should restore typed text deltas', () {
      final event = GenerationEvent.fromMap({
        'type': 'partDelta',
        'id': 'p0',
        'delta': {'type': 'text', 'text': 'hello'},
      });
      expect(event.toMap()['delta'], {'type': 'text', 'text': 'hello'});
    });
  });
}
