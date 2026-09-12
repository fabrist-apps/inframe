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

Common streaming preserves interleaved text, refusal, reasoning-summary, and caller-owned tool
argument deltas. The terminal Responses object supplies final citations, tool metadata, provider
tool records, usage, and replay data. Unknown native events are emitted as `ProviderEvent`s and
retained in replay; a native error or a stream that ends without a terminal event fails with the
partial assistant message attached to the error. Native callers can set decoded-event and byte
limits on `responses.stream` before transport begins.

Native lifecycle calls are explicit cold operations: `responses.retrieve`, `responses.cancel`,
`responses.delete`, `responses.listInputItems`, `responses.countInputTokens`, and
`responses.compact` never poll, paginate, or carry state between calls. `models.list` returns one
page and `models.retrieve` resolves one exact model ID. Background create results preserve queued
and in-progress states for the caller to inspect and advance explicitly.

`chatCompletions.create` and `chatCompletions.stream` expose the pinned native Chat Completions
shape without changing the common language model's Responses backend. Normalizing a completion
with multiple choices requires an explicit `choiceIndex`. Legacy text Completions and stored Chat
Completions administration are intentionally outside this package's endpoint snapshot.

`embeddingModel` sends one synchronous text batch and restores vectors by native index. Every
common input must contain exactly one text part; media and multipart inputs fail before I/O. Native
`embeddings.create` additionally accepts explicit token-ID inputs and base64 output, without local
tokenization, vector normalization, retries, or asynchronous batch jobs.
