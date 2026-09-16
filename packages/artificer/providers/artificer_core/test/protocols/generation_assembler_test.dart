import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/protocols.dart';
import 'package:conflux/result.dart';
import 'package:test/test.dart';

T value<T>(Result<T, AiError> result) => switch (result) {
  Success(:final value) => value,
  Failure(:final error) => throw StateError(error.message),
};

void main() {
  const native = NativePayload(providerId: 'p', api: 'a', modelId: 'm', data: {'complete': true});
  group('GenerationAssembler', () {
    test('should reject invalid native JSON through the typed protocol channel', () {
      final cycle = <Object?>[];
      cycle.add(cycle);
      for (final data in [
        Object(),
        double.nan,
        cycle,
        {1: 'nonstring'},
      ]) {
        final assembler = GenerationAssembler();
        value(assembler.add(const GenerationStarted()));
        final result = assembler.complete(
          terminal: true,
          native: NativePayload(providerId: 'p', api: 'a', modelId: 'm', data: data),
          finishReason: FinishReason.stop,
        ) as Failure<GenerationFinished, AiError>;
        expect(result.error, isA<ProtocolError>());
      }
    });

    test('should order interleaved finished parts and retain late metadata', () {
      final assembler = GenerationAssembler();
      value(assembler.add(const GenerationStarted(responseId: 'r')));
      value(
        assembler.add(
          const PartStarted(
            id: 'tool-local',
            index: 1,
            kind: GenerationPartKind.toolCall,
            owner: ToolExecutionOwner.application,
          ),
        ),
      );
      value(
        assembler.add(const PartStarted(id: 'text-local', index: 0, kind: GenerationPartKind.text)),
      );
      value(
        assembler.add(
          const PartDelta(
            id: 'tool-local',
            delta: ToolArgumentsDelta(text: '{"x":'),
          ),
        ),
      );
      value(
        assembler.add(
          const PartDelta(
            id: 'text-local',
            delta: TextDelta(text: 'hello'),
          ),
        ),
      );
      value(
        assembler.add(
          const PartDelta(
            id: 'tool-local',
            delta: ToolArgumentsDelta(text: '1}'),
          ),
        ),
      );
      final tool = value(assembler.assembledPart('tool-local', callId: 'late-id', name: 'lookup'));
      value(assembler.add(PartFinished(id: 'tool-local', part: tool)));
      value(
        assembler.add(
          const PartFinished(
            id: 'text-local',
            part: TextOutputPart(
              'hello',
              citations: [
                Citation(data: {'late': true}, url: 'https://example.test'),
              ],
            ),
          ),
        ),
      );
      value(assembler.add(const UsageUpdated(usage: Usage(outputTokens: 2))));
      value(assembler.add(const UsageUpdated(usage: Usage(outputTokens: 3))));
      value(
        assembler.add(
          const ProviderEvent(
            providerId: 'p',
            api: 'a',
            event: 'future',
            data: {
              'unknown': [1, 2],
            },
          ),
        ),
      );
      final replay = ProviderReplay(
        providerId: 'p',
        api: 'a',
        modelId: 'm',
        items: [
          {'signature': 'late'},
        ],
      );
      final result = value(
        assembler.complete(
          terminal: true,
          native: native,
          finishReason: FinishReason.toolCalls,
          replay: replay,
        ),
      ).result;
      expect(result.text, 'hello');
      expect(result.message.parts[0], isA<TextOutputPart>());
      expect((result.message.parts[1] as ToolCallPart).callId, 'late-id');
      expect(
        (result.message.parts[0] as TextOutputPart).citations.single.url,
        'https://example.test',
      );
      expect(result.usage!.outputTokens, 3);
      expect(result.native.data, native.data);
      expect(result.native.unknownEvents.single['event'], 'future');
      expect(result.message.replay!.items, replay.items);
      expect(
        assembler.complete(terminal: true, native: native, finishReason: FinishReason.stop),
        isA<Failure<GenerationFinished, AiError>>(),
      );
    });
    test('should retain malformed tool arguments as inspectable completed output', () {
      final assembler = GenerationAssembler();
      value(assembler.add(const GenerationStarted()));
      value(
        assembler.add(
          const PartStarted(
            id: 't',
            index: 0,
            kind: GenerationPartKind.toolCall,
            callId: 'call',
            name: 'lookup',
          ),
        ),
      );
      value(
        assembler.add(
          const PartDelta(
            id: 't',
            delta: ToolArgumentsDelta(text: '{"truncated":'),
          ),
        ),
      );
      final part = value(assembler.assembledPart('t')) as ToolCallPart;
      expect(part.arguments, isA<MalformedToolArguments>());
      value(assembler.add(PartFinished(id: 't', part: part)));
      expect(
        value(
          assembler.complete(
            terminal: true,
            native: native,
            finishReason: FinishReason.outputLimit,
          ),
        ).result.finishReason,
        FinishReason.outputLimit,
      );
    });
    test('should reject premature EOF with available partial output', () {
      final assembler = GenerationAssembler();
      value(assembler.add(const GenerationStarted()));
      value(assembler.add(const PartStarted(id: 'p', index: 0, kind: GenerationPartKind.text)));
      value(
        assembler.add(
          const PartDelta(
            id: 'p',
            delta: TextDelta(text: 'partial'),
          ),
        ),
      );
      final failure = assembler.complete(
        terminal: false,
        native: native,
        finishReason: FinishReason.stop,
      ) as Failure<GenerationFinished, AiError>;
      expect(failure.error, isA<ProtocolError>());
      expect((failure.error as ProtocolError).partialOutput.toString(), contains('partial'));
      expect(
        assembler.complete(terminal: true, native: native, finishReason: FinishReason.stop),
        isA<Failure<GenerationFinished, AiError>>(),
      );
    });
    test('should reject identity kind and delta contradictions', () {
      for (final bad in <GenerationEvent>[
        const PartStarted(id: 'other', index: 0, kind: GenerationPartKind.text),
        const PartDelta(
          id: 'unknown',
          delta: TextDelta(text: 'x'),
        ),
        const PartDelta(
          id: 'p',
          delta: ReasoningDelta(text: 'x'),
        ),
        const PartFinished(id: 'p', part: TextOutputPart('different')),
      ]) {
        final assembler = GenerationAssembler();
        value(assembler.add(const GenerationStarted()));
        value(assembler.add(const PartStarted(id: 'p', index: 0, kind: GenerationPartKind.text)));
        value(
          assembler.add(
            const PartDelta(
              id: 'p',
              delta: TextDelta(text: 'expected'),
            ),
          ),
        );
        expect(assembler.add(bad), isA<Failure<GenerationEvent, AiError>>());
      }
    });
    test('should bound retained UTF8 output unknown events and native payload', () {
      for (final kind in ['delta', 'unknown', 'native']) {
        final assembler = GenerationAssembler(maxResponseBytes: 512);
        value(assembler.add(const GenerationStarted()));
        final huge = List.filled(512, 'é').join();
        Result<Object?, AiError> outcome;
        if (kind == 'delta') {
          value(assembler.add(const PartStarted(id: 'p', index: 0, kind: GenerationPartKind.text)));
          outcome = assembler.add(
            PartDelta(
              id: 'p',
              delta: TextDelta(text: huge),
            ),
          );
        } else if (kind == 'unknown') {
          outcome = assembler.add(
            ProviderEvent(providerId: 'p', api: 'a', event: 'future', data: huge),
          );
        } else {
          outcome = assembler.complete(
            terminal: true,
            native: NativePayload(providerId: 'p', api: 'a', modelId: 'm', data: huge),
            finishReason: FinishReason.stop,
          );
        }
        expect((outcome as Failure<Object?, AiError>).error, isA<ResponseLimitError>());
      }
    });
    test('should preserve endpoint failure and never fabricate final success', () {
      final assembler = GenerationAssembler();
      value(assembler.add(const GenerationStarted()));
      const error = ProviderError('native stream error', statusCode: 200);
      assembler.fail(error);
      final result = assembler.complete(
        terminal: true,
        native: native,
        finishReason: FinishReason.stop,
      ) as Failure<GenerationFinished, AiError>;
      expect(result.error, same(error));
    });
  });
}
