import 'dart:io';

import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_google/artificer_google.dart';
import 'package:conflux/conflux.dart';

Future<void> main() async {
  const credential = 'caller-supplied-key';
  const modelId = 'caller-supplied-model';
  final provider = GoogleProvider(apiKey: credential);
  try {
    final model = provider.languageModel(modelId);
    final request = GenerationRequest(
      instructions: 'Answer in one sentence.',
      messages: [UserMessage.text('Why is explicit conversation history useful?')],
    );

    // Construction is lazy; applications run these values in their Conflux runtime.
    final generation = model.generate(request);
    final streaming = model.stream(request).runCollect();
    if (const bool.fromEnvironment('RUN_GOOGLE_EXAMPLE')) {
      final result = await generation.runFuture();
      stdout.writeln(result.text);
      await streaming.runFuture();
    }
  } finally {
    await provider.close();
  }
}
