# Artificer OpenAI

`artificer_openai` provides typed native OpenAI inference resources and adapters for
`artificer_core`. It is a standalone server-side Dart package and does not depend on the Artificer
agent runtime or Ack.

The native model snapshot is pinned to `openai/openai-openapi` commit
`38170fdddbb6a1813eae6c6587ee17cf2987185b` (OpenAPI 2.3.0, retrieved 2026-09-12).

```dart
final provider = OpenAIProvider(apiKey: credential);
try {
  final result = await provider
      .languageModel(modelId)
      .generate(GenerationRequest(messages: [UserMessage.text('Explain this change.')]))
      .runFuture();
  print(result.text);
} finally {
  await provider.close();
}
```
