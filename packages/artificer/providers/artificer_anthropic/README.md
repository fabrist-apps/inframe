# Artificer Anthropic

`artificer_anthropic` is a standalone server-side Dart SDK for Anthropic Messages and
`artificer_core`. It has no dependency on the Artificer agent runtime or Ack.

The native model snapshot follows `anthropics/anthropic-sdk-typescript` commit
`135f71e9297683e14614d4307081c0273ed0a09c`, inspected on 2026-09-12. Requests default to the
stable `2023-06-01` API version and always send it explicitly.

```dart
final provider = AnthropicProvider(apiKey: credential);
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

Operations are lazy and issue one HTTP attempt for each execution. The SDK keeps no conversation
history, runs no tools, and provides no embedding factory because Anthropic has no embedding API.
Callers compose retries, fallback, deadlines, and cancellation with Conflux. A supplied HTTP client
is borrowed; `close()` releases only provider-owned resources and interrupts the provider's active
work.

`provider.messages.create` returns a typed `AnthropicMessage` with its full immutable native JSON
and HTTP metadata. `provider.messages.stream` emits typed native events. Common streaming requires
`message_stop`; an error event or premature EOF fails without a terminal generation result. Unknown
events and fields remain available for inspection.
