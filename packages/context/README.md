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

## Ownership

Contexts borrow objects without copying or disposing them. If multiple branches borrow a mutable
object, mutations are visible through all of them. That object must support its intended concurrent
use. The creator of a resource owns its startup and cleanup, including failure paths. Context has
no close operation.

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
