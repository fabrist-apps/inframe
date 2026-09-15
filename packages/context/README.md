# Context

A pure Dart package for passing typed capabilities explicitly between operations.

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

## Bindings

Each key has its own identity, even when two keys have the same diagnostic name.
`read(key)` returns null when absent; `require(key)` throws `MissingContextValue`.
Values must be non-null and match the key's type.

`key.bind(value)` checks against the key's actual type, including when the key is
accessed through a wider type such as `ContextKey<Object>`. Bindings cannot be
constructed directly.

`withBinding` copies the bindings and returns a new context. Pass that result
downstream: the original and sibling contexts remain unchanged. Copying takes
time and storage proportional to the number of bindings.

## Feature extensions

A feature owns its private key and exports a named extension:

```dart
import 'package:context/context.dart';

final _eventsKey = ContextKey<List<String>>('events');

extension EventsContext on Context {
  List<String> get events => require(_eventsKey);

  Context withEvents(List<String> events) => withBinding(_eventsKey.bind(events));
}
```

Importing the extension makes its API available; calling its setup method supplies
the value. Access before setup throws `MissingContextValue`. Independent features
can add extensions to the same context without depending on each other.

## Ownership

Contexts borrow values without copying or disposing them. Branches retain the same
references to unchanged values, so mutations to a shared object are visible to
all of them. The object's creator owns its lifecycle and cleanup.

Operations are synchronous. Context provides no ambient lookup, resource scopes,
serialization, or cross-isolate sharing.

## Tests

Run from the repository root:

```sh
dart pub get
dart analyze packages/context
dart test packages/context/test --chain-stack-traces
```

Ordinary tests cover binding behavior and extension composition. Three
`.dart.txt` fixtures check that consumers cannot bind null, bind an incompatible
value, or construct a binding directly. The analyzer tests stage them as Dart
files in one temporary package and resolve its local dependency offline.
