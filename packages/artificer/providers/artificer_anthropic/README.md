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

Common image inputs support documented JPEG, PNG, GIF, and WebP bytes, URLs, and Anthropic file
references. Document inputs support inline PDF or UTF-8 text, PDF URLs, and Anthropic file
references. Audio and video fail before network I/O. Native block constructors expose cache-control
placement without moving it to a lossy common option.

Application function declarations map to Anthropic client tools. Returned `tool_use` blocks remain
caller-owned calls; the SDK never invokes them. The returned assistant message carries the exact
native blocks needed for the next request:

```dart
final result = await model.generate(request).runFuture();
final next = GenerationRequest(
  messages: [...request.messages, result.message, applicationToolResults],
  tools: request.tools,
  instructions: request.instructions,
  toolChoice: request.toolChoice,
  options: request.options,
  output: request.output,
);
```

JSON Schema output maps to Anthropic's native `output_config.format`. Plain JSON-object output has
no faithful Messages representation and fails before I/O. The SDK forwards the schema as supplied;
it does not validate generated values, repair output, or retry.
