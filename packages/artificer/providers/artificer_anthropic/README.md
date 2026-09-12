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

Model defaults and per-call `AnthropicModelOptions` use `Setting`, so a call can inherit, replace,
or clear thinking, effort, service tier, beta headers, native tools, remote MCP servers, and the
top-level cache breakpoint. Native tools pin the inspected schema's versioned discriminators:
web search `20260318`, web fetch `20260318`, code execution `20260521`, tool search `20251119`,
computer `20251124`, bash `20250124`, text editor `20250728`, and memory `20250818`.

```dart
final model = provider.languageModel(
  modelId,
  options: AnthropicModelOptions(
    thinking: const Setting.set(AnthropicAdaptiveThinking()),
    effort: const Setting.set(AnthropicEffort.high),
    betaFeatures: const Setting.set([AnthropicBeta.mcpClient20251120]),
    nativeTools: Setting.set([AnthropicWebSearchTool()]),
    remoteMcpServers: Setting.set([
      AnthropicRemoteMcpServer(
        name: 'docs',
        url: Uri.parse('https://mcp.example.com/sse'),
        allowedTools: const ['search'],
      ),
    ]),
  ),
);
```

Remote MCP definitions are forwarded to Anthropic; this SDK does not connect to the server.
Hosted tool work remains provider-owned and may be pending when a response pauses. Computer, bash,
text-editor, and memory calls are caller-owned `ApplicationToolCallPart` values whose arguments are
tagged `NativeToolArguments`. The caller submits a matching `NativeToolResult`; no tool runs,
software is installed, sandbox is administered, or paused turn is resumed automatically. Thinking
signatures, redacted thinking, citations, provider tool blocks, artifacts, and unknown content stay
in `ProviderReplay` unchanged.

The pinned scope excludes Message Batches, managed Agents, Skills and organization administration,
cloud authentication adapters, local MCP execution, schema validation, retries, and fallback.
