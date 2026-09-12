import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/json.dart';
import 'package:artificer_core/protocols.dart';
import 'package:test/test.dart';

void main() {
  test('assembles interleaved parts by index while retaining stable local IDs', () {
    final assembler = GenerationStreamAssembler(
      providerId: 'fixture',
      api: 'messages',
      modelId: 'model-1',
    );
    final events = <GenerationEvent>[
      assembler.start(
        ResponseMetadata(statusCode: 200, requestId: 'request-1'),
        responseId: 'response-1',
      ),
      assembler.startPart(index: 1, kind: GenerationPartKind.applicationToolCall),
      assembler.startPart(index: 0, kind: GenerationPartKind.text),
      assembler.appendText(1, '{"city"'),
      assembler.appendText(0, 'Weather'),
      assembler.appendText(1, ':"Paris"}'),
      assembler.finishPart(
        1,
        ApplicationToolCallPart(
          id: 'native-call-late',
          name: 'weather',
          arguments: JsonToolArguments(
            JsonObject({'city': 'Paris'}),
            originalText: '{"city":"Paris"}',
          ),
        ),
      ),
      assembler.finishPart(
        0,
        TextOutputPart(
          'Weather',
          citations: [
            Citation(
              uri: Uri.parse('https://example.test/source'),
              nativeMetadata: JsonObject({'late': true}),
            ),
          ],
        ),
      ),
      assembler.updateUsage(const Usage(inputTokens: 3, outputTokens: 2, totalTokens: 5)),
      assembler.updateUsage(const Usage(inputTokens: 3, outputTokens: 5, totalTokens: 8)),
    ];

    final finished = assembler.finish(
      finishReason: FinishReason.toolCalls,
      nativeFinishReason: 'tool_use',
      nativeResponse: JsonObject({'type': 'message_stop'}),
      replay: [
        ReplayItem(
          id: 'native-call-late',
          phase: 'signature',
          data: JsonObject({'signature': 'signed-late'}),
        ),
      ],
    );

    expect(events.whereType<PartStarted>().map((event) => event.partId), ['part-1', 'part-0']);
    expect(events.whereType<PartDelta>().map((event) => event.partId), [
      'part-1',
      'part-0',
      'part-1',
    ]);
    expect(finished.result.message.parts, [isA<TextOutputPart>(), isA<ApplicationToolCallPart>()]);
    expect((finished.result.message.parts.first as TextOutputPart).citations, hasLength(1));
    expect(
      (finished.result.message.parts.first as TextOutputPart).citations.single.nativeMetadata
          ?.toDart(),
      {'late': true},
    );
    expect(finished.result.usage?.totalTokens, 8);
    expect(finished.result.message.replay?.items.single.data.toDart(), {
      'signature': 'signed-late',
    });
  });

  test('attaches an immutable partial message when the assembled limit is exceeded', () {
    final assembler = GenerationStreamAssembler(
      providerId: 'fixture',
      api: 'responses',
      modelId: 'model-1',
      maxAssembledBytes: 4,
    );
    assembler.start(ResponseMetadata(statusCode: 200));
    assembler.startPart(index: 0, kind: GenerationPartKind.text);
    assembler.appendText(0, 'four');

    expect(
      () => assembler.appendText(0, '!'),
      throwsA(
        isA<ResponseLimitError>().having(
          (error) => (error.partialOutput as AssistantMessage).text,
          'partial text',
          'four',
        ),
      ),
    );
  });

  test('rejects a usage snapshot that is not cumulative', () {
    final assembler = GenerationStreamAssembler(
      providerId: 'fixture',
      api: 'responses',
      modelId: 'model-1',
    );
    assembler.start(ResponseMetadata(statusCode: 200));
    assembler.updateUsage(const Usage(totalTokens: 8));

    expect(
      () => assembler.updateUsage(const Usage(totalTokens: 7)),
      throwsA(isA<ProtocolError>()),
    );
  });
}
