import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/json.dart';
import 'package:artificer_core/protocols.dart';
import 'package:conflux/conflux.dart';

Future<void> main() async {
  final model = EchoModel('example-model');
  final result = await model
      .generate(GenerationRequest(messages: [UserMessage.text('Hello')]))
      .runFuture();
  print(result.text);
}

final class EchoModel implements LanguageModel {
  EchoModel(this.modelId) {
    if (modelId.isEmpty) throw ArgumentError.value(modelId, 'modelId');
  }

  @override
  final String modelId;

  @override
  String get providerId => 'example';

  @override
  ModelCapabilities get capabilities => ModelCapabilities({
    ModelCapability.textGeneration: CapabilitySupport.supported,
  });

  @override
  Effect<GenerationResult, AiError> generate(GenerationRequest request) {
    final text = (request.messages.single as UserMessage).parts.single as TextInputPart;
    final payload = NativePayload(
      providerId: providerId,
      api: 'echo',
      modelId: modelId,
      json: JsonObject({'text': text.text}),
    );
    return Effect.succeed(
      GenerationResult(
        message: AssistantMessage([TextOutputPart(text.text)]),
        finishReason: FinishReason.stop,
        nativePayload: payload,
        metadata: ResponseMetadata(statusCode: 200),
      ),
    );
  }

  @override
  Flow<GenerationEvent, AiError> stream(GenerationRequest request) => Flow.defer(() {
    final input = (request.messages.single as UserMessage).parts.single as TextInputPart;
    final assembler = GenerationStreamAssembler(
      providerId: providerId,
      api: 'echo',
      modelId: modelId,
    );
    final events = <GenerationEvent>[
      assembler.start(ResponseMetadata(statusCode: 200)),
      assembler.startPart(index: 0, kind: GenerationPartKind.text),
      assembler.appendText(0, input.text),
      assembler.finishPart(0, TextOutputPart(input.text)),
      assembler.finish(
        finishReason: FinishReason.stop,
        nativeResponse: JsonObject({'text': input.text}),
      ),
    ];
    return Flow.fromIterable(events).widenError<AiError>();
  });
}
