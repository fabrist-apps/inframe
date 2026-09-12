# Artificer Baseten

`artificer_baseten` is a standalone server-side Dart SDK for Baseten catalog inference,
explicitly compatible deployments, and custom prediction endpoints. It implements the shared
`artificer_core` model contracts without depending on another provider package, Ack, or the
Artificer agent runtime.

The native API snapshot follows the Baseten Chat Completions, Messages, deployed model, and BEI
documentation retrieved on 2026-09-12. Model and deployment identifiers remain explicit caller
configuration. Creating providers, model handles, endpoint bindings, and operations performs no
network work.

```dart
final provider = BasetenProvider(apiKey: credential);
try {
  final catalogModel = provider.languageModel(catalogModelId);
  final result = await catalogModel
      .generate(GenerationRequest(messages: [UserMessage.text('Explain this change.')]))
      .runFuture();
  print(result.text);

  final dedicated = provider.deployment(baseUrl: deploymentBaseUrl);
  final deploymentModel = dedicated.languageModel(servedModelId);
  await deploymentModel
      .stream(GenerationRequest(messages: [UserMessage.text('Stream a response.')]))
      .runCollect()
      .runFuture();
} finally {
  await provider.close();
}
```

Catalog calls use `https://inference.baseten.co/v1` and Bearer authentication by default.
Dedicated compatible deployments use the exact configured base URL with `Api-Key` authentication.
Both append `chat/completions` and send the separately supplied model string. The SDK does not
derive either value from the other or perform model discovery.

`chatCompletions.create` and `chatCompletions.stream` expose typed native compatible-chat data.
Unknown response fields and stream objects remain available through native extensions. Common
generation requests exactly one candidate and uses the same decoder and SSE framing. Native
responses with several choices require an explicit `choiceIndex` when normalized.

Streams are cold and bounded by the shared core transport. A documented `[DONE]` sentinel plus
finish metadata is required for common generation success. Premature EOF, error events, malformed
frames, and configured size limits fail without emitting a final result. Closing the provider
interrupts its catalog and deployment work, waits for cleanup, and leaves a borrowed HTTP client
open.
