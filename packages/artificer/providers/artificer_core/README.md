# Artificer core

`artificer_core` defines the immutable model contracts shared by independently packaged
Artificer providers. It depends on Conflux for lazy `Effect` and `Flow` execution and uses
one-attempt HTTP operations. Callers compose retry, fallback, timing, and runtime ownership.

Import `artificer_core.dart` for model and value APIs, `json.dart` for validated JSON,
`transport.dart` when implementing a provider, and `protocols.dart` for reusable wire codecs.
The domain barrel does not export transport internals.

Models accept provider-local string IDs. They own no conversation history or runtime, and each
execution creates fresh request state. Provider clients accept explicit base URLs and headers;
they do not read credentials from environment variables or `Context`.

Messages preserve ordered text, explicit media sources, application tool calls and results,
provider-owned tool records, citations, refusals, reasoning summaries, and unknown native content.
Versioned JSON persistence includes copied media bytes and provider replay data. Replaying signed or
provider-owned state requires the same provider, API, and model. Constructing edited content creates
a new message and retains replay only when the caller passes it explicitly.

`AiError.toString()` reports only the error type so logs do not expose provider-returned content.
Applications can inspect the typed error fields when they intentionally need the message, request ID,
native details, partial output, or remote resource ID.

`Setting<T>` distinguishes inherited values, replacements, and explicit clearing for immutable
provider options. Provider adapters must reject known unsupported features and conflicting native
fields before I/O; they must not silently drop options or validate generated JSON against application
schemas.

`ProviderHttpClient.close()` rejects new work, interrupts and awaits the operations registered by
that provider, then closes only its owned client. Caller cancellation aborts acquisition and cancels
an acquired response body. A borrowed client must honor abortable requests and response-subscription
cancellation; arbitrary borrowed clients can make cleanup unbounded. Cancellation does not prove that
remote inference stopped. Callers compose inference and read-idle timeouts through Conflux.

An `EmbeddingInput` is one semantic input even when it contains multiple text or media parts. An
`EmbeddingRequest` list is a batch of independent inputs. Provider adapters issue one synchronous
request, restore native indices, and use `EmbeddingResult.fromIndexed` to reject missing, duplicate,
empty, nonfinite, or inconsistent vectors. The common contract does not split, parallelize, cache,
normalize, or retry embedding work.

`UploadSource.bytes` copies its input immediately. `UploadSource.stream` opens a fresh stream for
each execution and checks its declared length. `ProviderHttpClient.sendUpload` forwards that length,
filename, and media type, and it cancels both the source and transport before interruption or provider
close completes. If a remote resource ID is already known, upload failures retain it for diagnostics.
The core client does not retry uploads or delete remote files, so executing an upload again may create
another remote file. Generation media accepts explicit bytes or URLs; it never reads an upload source
or filesystem path implicitly.

`ProviderHttpClient.sendSse` is cold: every `Flow` consumption sends one request and creates new UTF-8,
SSE, protocol, and aggregation state. The decoded-event capacity defaults to 16 with lossless upstream
backpressure. Individual SSE events default to an 8 MiB limit, while streamed and assembled native
responses default to 64 MiB. Provider protocols use `GenerationStreamAssembler` to issue stable local
part IDs, cumulative usage snapshots, immutable partial messages, and one final result after recognized
terminal semantics and transport cleanup. Unknown native events can be emitted as `ProviderEvent` and
stored selectively in replay data. Premature EOF and partial service failures end the `Flow` with an
`AiError`; early `take`, `runFirst`, subscription cancellation, and parent interruption close the owned
response body without closing a shared client.

`OpenAiCompatibleChatCodec` covers the shared JSON and SSE shape of the xAI and Baseten Chat
Completions endpoints. Provider packages implement `OpenAiCompatibleChatDialect<O>` to validate typed
options and add vendor fields. The codec always requests one candidate, requires an explicit index when
normalizing a native multi-choice response, retains unknown native extensions, and rejects `extraBody`
collisions before I/O. Nonstreaming and assembled streaming results retain a native choice for exact
same-target assistant replay, including refusal, usage, choice, tool-call, and function extensions. It
does not claim that every OpenAI-shaped service or vendor feature is compatible; Anthropic and Google
keep their own protocol adapters.

The compatible fixtures are pinned on 2026-09-12 to the published
[xAI Chat Completions reference](https://docs.x.ai/developers/rest-api-reference/inference/chat-completions)
and [Baseten Chat Completions reference](https://docs.baseten.co/reference/inference-api/chat-completions).
Provider packages should update their own fixtures and dialect hooks when a vendor contract changes.
