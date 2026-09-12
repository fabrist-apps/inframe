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
