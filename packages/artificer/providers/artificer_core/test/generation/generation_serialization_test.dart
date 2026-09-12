import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/json.dart';
import 'package:test/test.dart';

void main() {
  group('Generation serialization', () {
    test('should round-trip request options, tools, and structured output', () {
      final request = GenerationRequest(
        instructions: 'Be concise',
        messages: [UserMessage.text('hello')],
        options: GenerationOptions(
          maxOutputTokens: 12,
          temperature: 0.2,
          stopSequences: ['stop'],
        ),
        tools: [
          FunctionTool(name: 'lookup', inputSchema: JsonObject({'type': 'object'})),
        ],
        toolChoice: FunctionToolChoice('lookup'),
        output: JsonSchemaOutputFormat(
          name: 'answer',
          schema: JsonObject({'type': 'object'}),
        ),
      );

      final decoded = GenerationRequest.fromJson(request.toJson());

      expect(decoded.instructions, 'Be concise');
      expect(decoded.options.maxOutputTokens, 12);
      expect(decoded.options.temperature, 0.2);
      expect(decoded.options.stopSequences, ['stop']);
      expect(decoded.tools.single.name, 'lookup');
      expect(decoded.toolChoice, isA<FunctionToolChoice>());
      expect(decoded.output, isA<JsonSchemaOutputFormat>());
    });

    test('should round-trip generation outcome and replay metadata', () {
      final result = GenerationResult(
        message: AssistantMessage(
          [const RefusalPart('Cannot comply')],
          replay: ProviderReplay(
            providerId: 'provider',
            api: 'responses',
            modelId: 'model',
            items: [
              ReplayItem(phase: 'final', data: JsonObject({'signature': 'abc'})),
            ],
          ),
        ),
        finishReason: FinishReason.refusal,
        nativeFinishReason: 'blocked',
        usage: const Usage(inputTokens: 2, outputTokens: 1),
        responseId: 'response-1',
        requestId: 'request-1',
        nativePayload: NativePayload(
          providerId: 'provider',
          api: 'responses',
          modelId: 'model',
          json: JsonObject({
            'unknown': {'nested': true},
          }),
        ),
        metadata: ResponseMetadata(
          statusCode: 200,
          requestId: 'request-1',
          headers: {'x-request-id': 'request-1'},
        ),
      );

      final decoded = GenerationResult.fromJson(result.toJson());

      expect(decoded.finishReason, FinishReason.refusal);
      expect(decoded.nativeFinishReason, 'blocked');
      expect(decoded.usage?.inputTokens, 2);
      expect(decoded.message.parts.single, isA<RefusalPart>());
      expect(decoded.message.replay?.items.single.data.toDart()['signature'], 'abc');
      expect(decoded.nativePayload.json.toDart()['unknown'], {'nested': true});
    });

    test('should reject undeclared named tool choice', () {
      expect(
        () => GenerationRequest(
          messages: [UserMessage.text('hello')],
          toolChoice: FunctionToolChoice('missing'),
        ),
        throwsArgumentError,
      );
    });

    test('should reject wrong-shaped serialized integer fields', () {
      expect(
        () => GenerationOptions.fromDart({
          'maxOutputTokens': '12',
          'stopSequences': <Object?>[],
        }),
        throwsFormatException,
      );
      expect(
        () => Usage.fromDart({'inputTokens': '2'}),
        throwsFormatException,
      );
      expect(
        () => ResponseMetadata.fromJson(
          JsonObject({
            'schemaVersion': 1,
            'statusCode': '200',
            'headers': <String, Object?>{},
          }),
        ),
        throwsFormatException,
      );
    });
  });
}
