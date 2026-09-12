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

Compatible chat maps ordered text and image inputs, application function tools and results, and
text, JSON-object, or JSON-Schema output configuration. Image bytes are copied into a data URL;
absolute image URLs remain URLs. Audio, video, documents, provider file references, and media tool
results currently fail before I/O because this snapshot has no verified compatible mapping for
them. The service decides whether a selected model supports a request whose protocol mapping is
known.

`BasetenModelOptions` uses `Setting.inherit`, `Setting.set`, and `Setting.clear` for optional
vendor fields. Per-call settings resolve over model defaults, collections replace rather than
append, and `clear` omits the field. `extraBody` carries forward-compatible native fields; a key
that collides with a common or typed field fails before transport.

Returned assistant messages carry compatible native replay data. Reusing that message with the
same Baseten API and model preserves native message extensions, reasoning data, tool IDs, and
malformed argument text. Replay against another provider, API, or model fails explicitly. The SDK
never executes application tools or treats unknown native tool activity as an application call.

Dedicated BEI/OpenAI-compatible deployments expose `embeddings` and `embeddingModel`; the catalog
does not expose an embedding factory. A common embedding run sends one ordered text batch to the
configured deployment's `embeddings` path and restores vectors by response index:

```dart
final catalogModel = provider.languageModel(catalogModelId);
final dedicated = provider.deployment(baseUrl: deploymentBaseUrl);
final embeddingModel = dedicated.embeddingModel(servedModelId);
final vectors = await embeddingModel
    .embed(
      EmbeddingRequest(
        items: [EmbeddingInput.text('Deployment documentation')],
      ),
    )
    .runFuture();
```

The embedding adapter validates response count, indices, finite values, and dimensions. It accepts
one text part per common input. It does not combine items, split batches, normalize vectors, retry,
or infer a model name from the deployment URL. Native calls retain response extensions and HTTP
metadata, and `BasetenEmbeddingsResource.normalize` can map an already-decoded result without I/O.

`provider.messages` exposes Baseten's beta native Messages API. It uses `Authorization: Bearer`
and Baseten's endpoint schema rather than Anthropic SDK defaults:

```dart
final response = await provider.messages
    .create(
      BasetenMessageRequest(
        model: catalogModelId,
        maxTokens: 1024,
        messages: [BasetenInputMessage.userText('Explain gradient descent.')],
      ),
    )
    .runFuture();
```

Native content and tool blocks are immutable `JsonObject` values within typed request, response,
and event envelopes. This preserves beta additions without claiming a stable exhaustive schema.
Streaming requires `message_stop`; unknown event kinds remain inspectable, while error events,
premature EOF, malformed payloads, and configured limits fail through `AiError`. Common catalog
generation continues to use Chat Completions.

Custom prediction endpoints keep their complete configured path and query and use `Api-Key`
authentication. The caller owns the input and output types and supplies pure JSON codecs:

```dart
final endpoint = provider.predictionEndpoint<List<double>, double>(
  endpoint: Uri.parse('https://model.example.run/predict?environment=production'),
  encode: (input) => JsonArray(input),
  decode: (json) => (json as JsonNumber).value.toDouble(),
  decodedChunkCapacity: 16,
  maxResponseBytes: 64 * 1024 * 1024,
);
final prediction = await endpoint.predict([1, 2, 3]).runFuture();

final rawChunks = await endpoint.predictRawStream([1, 2, 3]).runCollect().runFuture();
```

Creating the binding or `Effect` does not run either callback or issue I/O. Every execution
encodes once, sends one POST, accepts any JSON response root, and decodes once. A decoder
`FormatException` becomes a `ProtocolError` with the received JSON retained as partial output;
other callback exceptions remain Conflux defects with their stacks. Successful responses retain
the complete native JSON and HTTP metadata. Custom predictions do not infer a model identity or
use the common model interface; use `deployment` only for an explicitly compatible API.

`predictRawStream` invokes only the encoder, so the encoded input must select any Baseten stream
field the deployment requires. It emits immutable `Uint8List` chunks and ends successfully at
normal HTTP EOF. It does not parse SSE, JSONL, chat events, tokens, tools, or terminal sentinels.
The configured chunk capacity bounds pending output and pauses the response stream for a slow
consumer; `maxResponseBytes` limits total bytes across both typed and raw predictions. Early Flow
termination, interruption, and `provider.close()` cancel and clean up the HTTP response. Closing a
provider never closes a borrowed `http.Client`.
