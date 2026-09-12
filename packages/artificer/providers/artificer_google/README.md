# Artificer Google

`artificer_google` is a standalone server-side Dart SDK for the Gemini Developer API. It provides
common `LanguageModel` generation and streaming plus typed native model discovery and
GenerateContent operations. It depends only on `artificer_core`, Conflux, and `package:http`.

The native types and deterministic fixtures are pinned to the official
[GenerateContent](https://ai.google.dev/api/generate-content) and
[Models](https://ai.google.dev/api/models) references as retrieved on 2026-09-12. Fields outside
the typed snapshot remain available through `raw` and `extensions` values.

```dart
import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_google/artificer_google.dart';
import 'package:conflux/conflux.dart';

final provider = GoogleProvider(apiKey: credential);
try {
  final model = provider.languageModel('gemini-3.8-flash');
  final result = await model
      .generate(
        GenerationRequest(
          instructions: 'Answer in one sentence.',
          messages: [UserMessage.text('Why is explicit history useful?')],
        ),
      )
      .runFuture();
  print(result.text);
} finally {
  await provider.close();
}
```

Model IDs passed to `languageModel` are bare provider IDs. The adapter adds `models/` and sends one
request to `/v1beta/models/{id}:generateContent`; it never discovers a model first. Common calls
always request one candidate and default `maxOutputTokens` to 4096. Instructions map to
`systemInstruction`, while user and assistant turns retain their supplied order. The common API is
explicit-history GenerateContent and stores no remote conversation state.

Streaming is a cold Conflux `Flow`. Every consumption makes one fresh request to
`/v1beta/models/{id}:streamGenerateContent?alt=sse`. Success requires selected-candidate finish
metadata or recognized prompt-block feedback followed by normal EOF. This lets the adapter retain
usage records that arrive after finish metadata. Premature EOF and HTTP-200 error records fail with
typed `AiError`s and no `GenerationFinished` event.

Concrete models accept per-call `GoogleModelOptions`. `Setting.inherit`, `Setting.set`, and
`Setting.clear` make default replacement and removal explicit:

```dart
final model = provider.languageModel(
  'gemini-3.8-flash',
  options: GoogleModelOptions(
    thinkingConfig: Setting.set(GoogleThinkingConfig(thinkingBudget: 512)),
  ),
);

final result = await model
    .generate(
      request,
      options: GoogleModelOptions(
        thinkingConfig: const Setting.clear(),
      ),
    )
    .runFuture();
```

Native calls keep authoritative resource names:

```dart
final page = await provider.models.list(pageSize: 20).runFuture();
final selected = await provider.models.retrieve('models/gemini-3.8-flash').runFuture();

final native = await provider.models
    .generateContent(
      GoogleGenerateContentRequest(
        model: selected.value.name,
        contents: [
          GoogleContent(role: 'user', parts: [GooglePart.text('Hello')]),
        ],
      ),
    )
    .runFuture();
final common = provider.models.normalizeGenerateContent(native);
```

`models.list` fetches exactly one page. Native multi-candidate responses require an explicit
`candidateIndex` when normalized. The provider performs no retries, redirects, polling, automatic
pagination, or hidden model turns. A supplied `http.Client` is borrowed; `close()` interrupts only
this provider's active operations and never closes the borrowed client.
