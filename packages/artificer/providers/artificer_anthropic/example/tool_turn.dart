import 'package:artificer_anthropic/artificer_anthropic.dart';
import 'package:artificer_core/artificer_core.dart';
import 'package:conflux/conflux.dart';

Effect<GenerationResult, AiError> continueWithToolResults({
  required AnthropicLanguageModel model,
  required GenerationRequest request,
  required GenerationResult result,
  required List<ToolMessage> applicationToolResults,
}) {
  final next = GenerationRequest(
    messages: [...request.messages, result.message, ...applicationToolResults],
    tools: request.tools,
    instructions: request.instructions,
    toolChoice: request.toolChoice,
    options: request.options,
    output: request.output,
  );
  return model.generate(next);
}

void main() {}
