# Artificer xAI

`artificer_xai` is a standalone server-side Dart SDK for xAI native inference APIs and
`artificer_core` model contracts. It does not depend on another provider package, the Artificer
agent runtime, or Ack.

The native model snapshot follows xAI's REST reference and OpenAPI 1.0.0 as retrieved on
2026-09-12.

```dart
final provider = XaiProvider(apiKey: credential);
try {
  final result = await provider
      .languageModel(modelId)
      .generate(
        GenerationRequest(messages: [UserMessage.text('Explain this change.')]),
      )
      .runFuture();
  print(result.text);
} finally {
  await provider.close();
}
```

Common generation uses xAI Responses with explicit caller-owned history and `store: false`.
Native callers can use `responses.create` and `responses.stream` directly. Both routes use one
shared transport and typed decoder; normalizing a decoded response performs no I/O.

Response streams are cold and bounded. A documented terminal event is required for success;
premature EOF and native error events fail without producing a final result. Closing the provider
interrupts its active work and closes only a client it owns.

`XaiModelOptions` adds xAI reasoning, priority service, sampling, agent-turn, log-probability,
and End User controls. Native tools cover web search, X search, code execution, existing xAI
collections, and remote MCP. The adapter keeps provider-hosted activity separate from application
function calls and never executes either kind of tool.

Returned assistant messages carry native replay items for stateless same-provider, same-API, and
same-model follow-up requests. Application code owns the ordered history and explicit tool results.
Structured output is forwarded through the native response format; generated JSON is returned
without Ack validation, repair, or retries.
