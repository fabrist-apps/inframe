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

`GenerationResult.fromJson(result.toJson())` restores a persisted result, including its complete native payload. Public data classes expose `fromMap` and `fromJson`; JSON entry points consume/return strings. Call `initializeMappers()` before container-based decoding of nested or polymorphic values. Initialization is synchronous, repeatable and makes no network requests. Generated mappers are shipped with core; consuming applications need no builder dependency or code generation. Domain messages and results use schema version 1 and reject unknown versions. Native wire bodies use their endpoint schema, without domain tags.

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

Generate from this package with `dart run build_runner build`. CI regenerates and requires a clean diff. The separate consumer fixture resolves and runs outside the workspace using only public imports and shipped mappers. HTTP tests use loopback servers and require no live credentials.
