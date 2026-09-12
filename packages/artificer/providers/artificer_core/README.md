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
