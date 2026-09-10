# Conflux

Conflux provides pure functional values and lazy effectful composition for
Inframe. `Option` keeps absence separate from a present nullable value,
`Result` keeps synchronous expected failures in the type system, and `Effect`
adds asynchronous execution, Context access, structured concurrency, and
resource scopes.

```dart
import 'package:conflux/conflux.dart';

const Option<String?> missing = None();
const Option<String?> cleared = Some(null);
const Option<String?> supplied = Some('Bhaswanth');

String describe(Option<String?> option) => option.match(
  onSome: (value) => 'Supplied: $value',
  onNone: () => 'Not supplied',
);

Result<int, String> parseCount(String input) {
  final count = int.tryParse(input);
  return count == null ? Failure('Not an integer: $input') : Success(count);
}

final label = parseCount('42')
    .filterOrFail((count) => count > 0, (_) => 'Must be positive')
    .map((count) => 'Count: $count')
    .getOrElse((error) => 'Invalid count: $error');
```

An Effect is a reusable description. Construction, `defer`, Context selection,
and foreign Future factories do no work until execution. `Runtime` owns root
fibers and waits for their resource cleanup:

```dart
final program = Effect.build<String, String>(($) async {
  final count = $.sync(parseCount('42'));
  final service = $.context.require(serviceKey);
  final connection = await $.acquireRelease(
    service.connect(count),
    release: (connection) => connection.closeEffect(),
  );
  return await $(connection.load());
});

final runtime = Runtime(context: Context().withBinding(serviceKey.bind(service)));
try {
  final exit = await runtime.run(program);
  // Inspect Succeeded(value) or Failed(cause).
} finally {
  await runtime.close();
}
```

Every asynchronous builder bind must be awaited, and the callback-local
builder cannot be used after its callback ends. Plain Dart `await` has no
Conflux cancellation hook. Adapt foreign work with `Effect.tryFuture` and
supply `onCancel` when the external operation can be stopped. Without that
hook, Conflux observes late completion but cannot claim the work stopped.

Contexts contain borrowed references. Only `acquireRelease`, `addFinalizer`,
or another explicit cleanup operation transfers ownership to an Effect scope.
Scopes interrupt and await child fibers before running finalizers once in
reverse registration order. Finalizers are protected from ordinary
cancellation, so an uncooperative finalizer can prevent bounded shutdown.

`Queue.bounded` acquires an in-memory FIFO Queue whose lifetime belongs to the
current Effect scope. A full Queue applies lossless backpressure until a take
releases capacity. Shutdown is immediate and interrupts pending data operations
with `QueueShutdown`:

```dart
final queued = Effect.build<int, Never>(($) async {
  final queue = await $(Queue.bounded<int>(1));
  await $(queue.offer(42));
  return $(queue.take());
});

final value = await queued.runFuture();
```

`PubSub.bounded` broadcasts each committed publication to the subscribers that
were active when publishing began. Each subscription has the configured bounded
capacity, so the slowest subscriber applies backpressure. Subscriptions belong
to their acquiring scopes and unsubscribe automatically:

```dart
final broadcast = Effect.build<int, Never>(($) async {
  final pubsub = await $(PubSub.bounded<int>(1));
  final subscription = await $(pubsub.subscribe());
  await $(pubsub.publish(42));
  return $(subscription.take());
});

final value = await broadcast.runFuture();
```

Ordinary recovery runs once for a cause containing only expected errors and
uses the first expected leaf in deterministic execution/source order. A defect
or interruption prevents recovery and retains the complete cause. `tapCause`
can observe that structure before recovery. `validate` intentionally collects
every expected leaf, while `result` reduces an all-expected cause to its primary
error and retains `E` in its Effect channel so a mixed cause stays typed.

`getOrNull()` intentionally maps both `None()` and `Some(null)` to `null`. Use
`match` or an exhaustive switch when that distinction matters. Fallbacks and
transformation callbacks run only for the branch that needs them. Exceptions
thrown by callbacks remain ordinary Dart exceptions.

`Result.getSuccess()` and `Result.getFailure()` return `Option`, so a nullable
success or failure remains present. `getOrNull()` intentionally collapses a
failure and a successful `null`. Use `match` when that distinction matters.

`Option.all` collects present values in order and stops at the first `None`.
`Option.firstSome` stops at the first present value, including `Some(null)`,
while `Option.fromIterable` requests only the first item from its input.

`Result.all` inspects already-created results until the first failure.
`Result.validate` invokes a validator for every input and accumulates expected
failures in an immutable `NonEmptyList`. Unexpected callback exceptions remain
ordinary Dart exceptions rather than validation failures.

Run the package tests from the repository root:

```sh
dart test packages/conflux/test --chain-stack-traces
```
