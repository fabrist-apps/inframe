# Context

A pure Dart package for passing typed, explicitly configured capabilities between operations.
Independent packages can add named extensions on the same `Context` without changing its base API.

```dart
import 'package:context/context.dart';

void main() {
  final requestKey = ContextKey<String>('request');
  final base = Context().withBinding(requestKey.bind('base'));
  final request = base.withBinding(requestKey.bind('request-1'));

  print(base.require(requestKey)); // base
  print(request.require(requestKey)); // request-1
}
```

## Binding and derivation

`Context()` is empty. Supply each value with `key.bind(value)` and pass it to `withBinding`.
Always pass the returned context downstream: ignoring the return value leaves the original unchanged.
All operations are synchronous.

Each `ContextKey<T>` has its own identity. Two keys named `request` do not refer to the same binding.
`read(key)` returns the typed value or null. `require(key)` throws `MissingContextValue` when setup
is missing; its `debugName` identifies the key's diagnostic label. There are no implicit defaults.

Values cannot be null. Incompatible direct bindings fail analysis. Dart also rejects incompatible
values passed through a covariantly widened key at runtime, before constructing a binding. Consumers
cannot construct `ContextBinding` directly.

Derivation copies an identity map, taking time and storage proportional to the number of bindings.
Replacing a binding does not affect parents or siblings. Other values retain their original object
references. Structural sharing is not implemented.

## Package-owned capabilities

A feature keeps its private key in the same Dart library as its named extension. Its public
entrypoint exports that extension and the capability type. For example, this excerpt belongs in
an analytics package that owns `Analytics`:

```dart
import 'package:context/context.dart';

final _analyticsKey = ContextKey<Analytics>('analytics');

extension AnalyticsContext on Context {
  Analytics get analytics => require(_analyticsKey);

  Context withAnalytics(Analytics analytics) =>
      withBinding(_analyticsKey.bind(analytics));
}
```

A web server package follows the same pattern with a private `ContextKey<HttpExchange>`, an
`http` getter, and `withHttp(HttpExchange exchange)`. Both features depend independently on `context`.
Neither feature depends on or re-exports the other. The base has no feature imports or exports.

The application supplies analytics once and the server derives a context for each exchange. This
setup excerpt assumes the application and server have created their capability objects:

```dart
import 'package:analytics/analytics.dart';
import 'package:context/context.dart';
import 'package:web_server/web_server.dart';

final base = Context().withAnalytics(analytics);
final request = base.withHttp(exchange);
request.analytics.track('page_view');
request.http.respond('Hello');
```

Both getters read from the same `request`. Each concurrent request derives its own context from
`base`, and middleware must pass any further derived context to its handler.

### Import visibility and setup

| Imports in a consumer library | Available API |
| --- | --- |
| `context` | Core operations |
| `context` + `analytics` | Core operations and analytics extension |
| `context` + `web_server` | Core operations and HTTP extension |
| All three | Both feature extensions on one context |

Visibility is per Dart library. Adding a dependency to `pubspec.yaml` does not import its extensions.
A deliberate barrel re-export also exposes an extension; visibility is not a security boundary.
Receivers need a static type such as `Context`; `dynamic` does not dispatch extension members.
Named invocation, such as `AnalyticsContext(request).analytics`, or import combinators can resolve
collisions between independently authored extensions.

Imports make the API available at compile time. Setup supplies its value at runtime. A plain
`Context` does not statically prove that any binding exists. Importing a feature without calling its
setup helper compiles, then accessing the getter throws `MissingContextValue`.

## Ownership

Contexts borrow objects without copying or disposing them. If multiple branches borrow a mutable
object, mutations are visible through all of them. That object must support its intended concurrent
use. The creator of a resource owns its startup and cleanup, including failure paths. Context has
no close operation.

For an analytics/HTTP integration, the application owns analytics startup and shutdown. The server
owns exchange creation and finalization, including handler failures. A production HTTP capability
must reject operations after finalization even when a caller retains it or its context. Background
analytics delivery must capture event data before request cleanup instead of retaining a live
exchange. These obligations belong to future feature integrations; the fixtures only record events
and responses in memory and do not implement resource lifecycles.

These reference semantics apply within an isolate; the package provides no cross-isolate sharing,
serialization, cancellation, deadlines, resource scopes, global registry, or ambient zone lookup.
The base package has no Flutter, HTTP, analytics, or other runtime package dependency.

## Verification

From the repository root, using its Dart SDK:

```sh
dart pub get
dart analyze
dart test packages/context/test --chain-stack-traces
```

The normal Dart tests cover binding semantics and run external consumer packages through the analyzer.
Fixture sources under `test/fixtures/` use `.dart.txt` so intentionally invalid cases stay out of
ordinary analysis. Tests stage them as `.dart` files in a temporary directory, resolve local path
dependencies offline, check specific diagnostics, and execute valid consumers. No web tests are run.

The `analytics` and `web_server` fixture packages each depend only on `context`. Four separate
consumer packages declare both features as dependencies but import only the libraries used by their
case, proving that imports control visibility. Valid cases execute the supplied objects; invalid
cases assert the analyzer's specific missing-getter diagnostics.

To run just the composition example, including concurrent request isolation and reversed setup order:

```sh
dart test packages/context/test/context_extensions_test.dart --name 'should compose both features'
```

The executable source is [the combined consumer fixture](test/fixtures/combined_consumer/valid.dart.txt).
The test stages and runs it as an independent package. Analytics and HTTP here are local fixtures,
not production packages or network clients.
