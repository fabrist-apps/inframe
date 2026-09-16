# Foundation conformance

Run these suites from the workspace root with `dart test packages/artificer/providers/artificer_core/test --chain-stack-traces`. Fixtures use loopback HTTP and the production Dio adapter. No test needs credentials or a live service.

| Foundation contract | Focused coverage |
| --- | --- |
| Shipped generated mappers, package registration, repeated initialization, public aliases, generic and nested polymorphic decoding without consumer builders | `consumer_test.dart`, `fixtures/consumer/persistence.dart.txt`, generation serialization tests |
| Version 1 messages/results, unknown-version rejection, native raw JSON and unknown fields, omitted/null/present values, unresolved options absent from wire | Generation conversation/options tests; Chat/Responses codec tests; external consumer |
| Ordinary mutable collections, cold reads, replay-clearing edits, no generated stale copy helpers | Generation conversation tests; external consumer |
| JSON cycles, non-string keys, unsupported objects and nonfinite values; no implicit registered-object coercion | Generation JSON boundary/persistence/tool argument tests |
| Content-free diagnostics and observations, runtime handles excluded, explicit credentials and application-owned Runtime | Consumer persistence/observation checks; `observations/` |
| Public language/embedding providers, typed concrete options, Effect.build composition, unknown model IDs without discovery | External consumer and embedding/model wire tests |
| One native/common transport and decoder path, pure authoritative normalization, explicit multi-candidate selection | `protocols/chat/`, `protocols/responses/`, `fixtures/consumer/protocols.dart.txt` |
| Options inheritance/replacement/clear, known unsupported capabilities and conflicts rejected before I/O | Generation option tests; Chat/Responses/embedding tests |
| Ordered tool conversations/results, malformed vs free-form/native arguments, provider-owned pending work, schemas without application validation | Generation conversation tests and both codec suites |
| Refusal, truncation, paused outcomes, citations, reasoning signatures, ordered same-target replay and incompatible target failures | Conversation and Responses codec/model tests; Chat replay fixtures |
| Common/native deferred input and storage policy, extras collisions, hosted inventory, schema differences | Request policy and Chat/Responses codec tests |
| Stream/unary equivalence, stable interleaved part identity/order, late metadata, typed deltas, usage snapshots and unknown events | Generation assembler tests and both production codec stream suites |
| Explicit terminal policy, premature EOF, malformed frames, HTTP-200 errors, partial output and no false final success | SSE/assembler tests and both codec stream suites |
| Event-count backpressure independent of frame/assembled byte bounds; no dropped protocol fragments | `transport/provider_sse_test.dart`, `protocols/sse_test.dart`, assembler and codec limit tests |
| Embedding input order, count/index/dimension/finite-vector integrity, no rescaling or implicit batching | `embeddings/` and composed external consumer |
| Tracked borrowed adapter required without mutation; shared options/middleware/unrelated users preserved | `transport/` |
| Fresh requests/tokens on repeated and concurrent execution, one attempt without SDK retries/redirects/fallback | Transport and external consumer wire tests |
| Cancellation before headers/during body, late acquisition abort-before-send, late response disposal, timeout cleanup, early take | Production adapter lifecycle and SSE transport tests |
| Cleanup before terminal success or interrupted Exit, retained cleanup defects, conservative delivery states | Transport lifecycle/SSE tests; generation transport tests; `observations/` |
| Idempotent close/closeEffect, rejection of new work, active request release and borrowed pool remains usable | Transport lifecycle tests |
| Correlated start/response/usage/verdict/one terminal outcome, normalization emits no second attempt, observer defects retain cleanup | `observations/`, external protocol consumer |
| Native status/code/message/details/request ID, raw and parsed Retry-After, service errors distinct from protocol/transport/defect/interruption | Observation diagnostic/model tests; codec error fixtures; transport lifecycle tests |

CI regenerates the package's mappers, formats generated output, and checks that regeneration leaves the checkout unchanged. The separate consumer resolves from a temporary directory and runs only shipped source and mappers.
