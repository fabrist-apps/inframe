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

Returned assistant messages carry the exact native output items required for a stateless second
turn. Append the message and explicit tool results to caller-owned history:

```dart
final first = await model.generate(request).runFuture();
final call = first.message.parts.whereType<ApplicationToolCallPart>().single;
final second = await model
    .generate(
      GenerationRequest(
        messages: [
          ...request.messages,
          first.message,
          ToolMessage([
            JsonToolResult(callId: call.id, value: JsonObject({'temperature': 18})),
          ]),
        ],
        tools: request.tools,
      ),
    )
    .runFuture();
```

The SDK preserves provider-hosted tool records as provider-owned output. Computer, shell, patch,
custom, and function calls remain caller-owned. It never executes either family. Common generation
always uses explicit history and `store: false`; native callers use `OpenAIResponseRequest` when they
need background or stored continuation fields.
