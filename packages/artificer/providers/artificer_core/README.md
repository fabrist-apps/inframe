# Artificer core

Shared contracts for standalone Dart text providers. Providers implement `LanguageModel` and own a `ProviderHttpClient`; applications own conversation history and the Conflux `Runtime` that executes requests. Model handles borrow the provider client and keep no hidden conversation or runtime.

```dart
import 'package:artificer_core/artificer_core.dart';
import 'package:conflux/effect.dart';

final request = GenerationRequest(messages: [UserMessage.text('Hello')]);
final program = model.generate(request); // LanguageModel supplied by a provider.
final runtime = Runtime();
try {
  final exit = await runtime.run(program);
  // Inspect Succeeded<GenerationResult, AiError> or Failed with its complete Cause.
} finally {
  await runtime.close();
}
```

Factories accept nonempty provider-local string model IDs. Unknown IDs do not imply unsupported capabilities and do not trigger discovery. Credentials and endpoints belong to provider construction, never serialized model data. Native JSON uses ordinary Dart maps, lists and primitive values.

`GenerationResult.fromJson(result.toJson())` restores a persisted result, including its complete native payload. Public data classes expose `fromMap` and `fromJson`; JSON entry points consume/return strings. Call `ArtificerCore.initialize()` at startup in each isolate before serialization or container-based decoding. It initializes Conflux’s mappers and timezone database, then registers all core mappers. Initialization is synchronous, repeatable and makes no network requests. Generate core’s mappers and initializer after checkout with `just generate` from the workspace root. Consuming applications need no builder dependency or code generation of their own. Domain messages and results use schema version 1 and reject unknown versions. Native wire bodies use their endpoint schema, without domain tags.

Model generation enables encoding, decoding, value equality, and `copyWith` through `build.yaml`. Generated `toString` is disabled. `Message` and `AssistantMessage` use the same defaults. `AssistantMessage.withParts` clears replay state; generated `copyWith` preserves it unless explicitly replaced. Models retain caller-owned collections, so their equality and hash codes can change if those collections are mutated.

Collections are ordinary Dart collections. Do not mutate requests or configuration during execution. Cold operations read their supplied values when executed, so reusing an Effect performs a new request with independent request state. Diagnostic strings omit content and raw headers; native payloads and metadata are available for explicit inspection.

## Provider transport

```dart
import 'package:artificer_core/transport.dart';
import 'package:dio/dio.dart';

final dio = Dio()..httpClientAdapter = ProviderDioAdapter();
final client = ProviderHttpClient(dio: dio);
final operation = client.requestJson(
  url: Uri.parse('https://provider.example/text'),
  headers: {'authorization': 'Bearer application-supplied-key'},
  body: {'model': 'provider-local-model', 'prompt': 'Hello'},
);
// Execute operation with the application's Runtime.
await client.close(); // Borrowed dio remains usable; its owner closes it.
```

Omit `dio` to let the client create and own its pool. A borrowed Dio must already use `ProviderDioAdapter`; incompatible adapters are rejected without mutation. Middleware must preserve streamed responses, lifetime metadata and one-attempt semantics. The SDK neither installs retry middleware nor follows redirects. Default connection timeout is 30 seconds, with no hidden inference, send or read-idle deadline. JSON responses are bounded to 64 MiB by default.

`close()` rejects new work and interrupts owned active requests, waiting for their cleanup. `closeEffect()` provides lazy scoped cleanup. Conflux interruption remains an interrupted Cause; cleanup failures remain defects. Cancellation waits for owned cleanup, including late native acquisition, and does not promise that remote generation stopped or that DNS/TLS cleanup has a fixed deadline.

Core supports text inference and text embeddings. Media inputs, files, sessions, discovery, background work, automatic tool execution, retries, fallback and application-schema validation belong outside this scope.

## Verification

From the workspace root:

```sh
dart test packages/artificer/providers/artificer_core/test --chain-stack-traces
dart analyze
```

Generated mappers and the initializer are ignored by Git. Run `just generate` from the workspace root, or `dart run build_runner build` followed by `dart format lib` from this package, before analysis or tests. The workspace’s `just generate` recipe and CI also generate these files. The separate consumer fixture resolves and runs outside the workspace using only public imports and the locally generated mappers. HTTP tests use loopback servers and require no live credentials. [Conformance coverage](test/README.md) maps the foundation contracts to focused suites.

## Options and preflight

`GenerationOptions` carries `Setting<T>` overrides. `inherit()` retains model defaults, `set(value)` replaces a scalar or complete collection, and `clear()` omits the native field. `options.resolve(modelDefaults)` applies SDK defaults first; its `toWire()` emits plain JSON fields. Optional sampling fields are absent unless supplied, and the default output limit is 4096 tokens.

```dart
final overrides = GenerationOptions(
  temperature: const Setting.clear(),
  stop: Setting.set(['END']),
);
final nativeOptions = overrides.resolve(modelDefaults).toWire();
```

`NativeField<T>` separately represents native omitted/null/present values. Use `NativeField.fromJson<String>(json)` to retain generic type arguments through the public decoding alias. A native field is resolved into a wire object with `writeTo`, never by sending its persisted form.

Provider codecs use `TextRequestPolicy` from `protocols.dart` with their pinned typed fields, hosted-tool inventory, unsupported options and storage policy. Apply it inside the lazy operation. It returns typed preflight failures for collisions and known deferred capabilities while retaining neutral new text extras. `ModelCapabilities.validateRequested` rejects only known unsupported features; unknown model support remains pass-through.

## Tool history and replay

`GenerationRequest` includes application `FunctionTool` declarations, `ToolChoice` and `OutputFormat`. Tools describe a protocol; core never executes callbacks or validates generated output against an application schema. Adapters call `request.validate(providerId: ..., api: ..., modelId: ...)` during execution before I/O to check IDs, declarations, native action targets and replay compatibility.

Assistant output distinguishes application calls from provider-owned tool records, including pending records without a result. Tool arguments preserve parsed JSON with original text, declared free-form input, tagged native actions, or malformed original arguments. Tool results retain success/application failure and JSON, ordered text or tagged native content.

Persist the returned `AssistantMessage` with its `ProviderReplay` to resubmit signed or opaque native items to the same provider/API/model. Incompatible targets fail explicitly. Use `withParts` to replace content and clear replay. Generated `copyWith` retains replay by default; pass `replay: null` when editing content through it. If you mutate `parts` or nested collections directly, set `message.replay = null` before resubmission. Opaque native base64 strings remain native strings; the SDK does not infer private reasoning from them.

## Text embeddings

`EmbeddingModel` describes one synchronous request for an ordered nonempty list of `EmbeddingInput.text` values. `CompatibleEmbeddingModel` in `protocols.dart` is provider support for indexed embedding endpoints. It borrows the provider client, accepts an open model ID, and exposes typed `EmbeddingOptions` plus `rawEmbed` for the same native execution path.

```dart
final program = Effect.build<EmbeddingResult, AiError>(($) async {
  final reply = await $(provider.languageModel(modelId).generate(request));
  return await $(provider.embeddingModel(embeddingModelId).embed(
    EmbeddingRequest(items: [EmbeddingInput.text(reply.text)]),
  ));
});
```

The application's Runtime runs the complete program. Native results retain full unknown JSON, actual model identity and available usage. Normalization restores provider indices and rejects wrong counts, duplicate/missing indices, empty/nonfinite vectors and inconsistent/requested dimensions. It never rescales vectors or splits an oversized batch. `raw.value.normalize(request, raw.raw, metadata: raw.metadata)` normalizes an existing response without another inference request.

## Streaming

`ProviderHttpClient.withSse` gives a codec response metadata and a bounded Flow of `SseEvent` frames. Defaults are 16 buffered events and 8 MiB per SSE event; `GenerationAssembler` bounds assembled output and native data to 64 MiB. Limits are configurable positive values. Parsing preserves backpressure even when a single network chunk contains many frames.

Codecs assign stable local part IDs, feed typed events to `GenerationAssembler`, and recognize their endpoint's terminal semantics. Append `GenerationFinished` after `withSse` completes so transport cleanup precedes final success. EOF alone is not success: incomplete parts, malformed frames, native errors and size limits retain typed failures and available partial output. Unknown native events remain in the final native payload without collecting every known delta.

Each consumption opens a fresh request. Early `take`, interruption and provider close release owned transport resources; closing does not wait for arbitrary application callbacks consuming the stream.

## Compatible protocols

`protocols.dart` exposes pure `ChatCodec` and `ResponsesCodec` conversion plus model handles that borrow a `ProviderHttpClient`. Provider packages configure routes, authentication, text-only inventories and dialect differences. Core imports no vendor SDK. `ChatProvider` is a convenience owner for a configured Chat endpoint; applications can also construct `ChatLanguageModel` with a shared provider client.

```dart
final codec = ResponsesCodec(ResponsesDialect(
  providerId: 'my-provider',
  route: (modelId) => configuredEndpoint,
  authentication: () => {'authorization': 'Bearer $explicitApiKey'},
));
final model = CompatibleResponsesModel(
  modelId: 'provider-local-model', client: client, codec: codec,
);
final exit = await runtime.run(model.rawGenerate(request));
if (exit case Succeeded(:final value)) {
  // Normalize the existing response without performing more I/O.
  final common = codec.normalize(value.value, value.raw, metadata: value.metadata);
}
```

Common `generate` performs this same path once. Chat uses `model.rawGenerate` and `model.codec.normalize(raw)`. Explicit native requests use `model.native(NativeChatRequest(...))` for Chat and `model.create(ResponsesRequest(...))` for Responses. Native multiple-choice normalization requires `choiceIndex` or `candidateIndex`; common requests select one candidate.

Chat defaults to a `[DONE]` terminal sentinel. A configured `ChatTerminalPolicy.finishThenEof` instead requires selected-candidate finish metadata followed by normal EOF, allowing trailing usage. Responses requires a terminal response event with its authoritative output snapshot; provider event aliases adapt compatible dialects. Both retain complete raw data and same-target replay. Unknown events remain separately available on `NativePayload.unknownEvents`.

Responses always sends `store:false` and rejects stop sequences. Dialects can configure instruction placement, hosted tool types, schema support, native error envelopes and tool event/item variations. They must explicitly represent a supported native input or reject it; unknown model names never determine capabilities. Tool results preserve ordered text parts, and application code remains responsible for executing application-owned calls.

## Provider errors

`ProviderError` preserves native diagnostics and the raw `retryAfter` header. `retryAfterDelay` parses nonnegative delay-seconds; `retryAfterDate` parses HTTP dates. Malformed values remain available as raw text and return null from parsed accessors. Applications decide whether and when to retry.
