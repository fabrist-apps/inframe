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

Timing operations use the runtime's `Clock`, so tests can control both wall and
monotonic time. `delay` waits before starting work, `timed` reports monotonic
elapsed time, and `timeout` interrupts and awaits child cleanup before returning
its expected error:

```dart
final measured = await Effect.succeed<String, String>('ready')
    .delay(const Duration(milliseconds: 10))
    .timeout(
      const Duration(seconds: 1),
      onTimeout: () => 'operation timed out',
    )
    .timed()
    .runFuture();

print('${measured.value} after ${measured.elapsed}');
```

Durations must be non-negative. Conflux passes their microsecond value to the
configured `Clock` without rounding; that Clock and its platform timer determine
effective precision.

`Schedule` values are reusable policy descriptions; every `retry`, `repeat`,
or `schedule` execution creates a fresh driver. `retry` feeds expected errors
to its driver, `repeat` runs immediately and feeds successful values, and
`schedule` asks the driver before the first execution using `None`:

```dart
var attempts = 0;
final loaded = Effect.defer<int, String>(() {
  attempts += 1;
  return attempts < 3 ? Effect.fail('try again') : Effect.succeed(42);
}).retry(Schedule.recurs(3));

final value = await loaded.runFuture();
```

`recurs(n)` permits `n` continuing decisions, so retry and repeat can execute
once initially plus `n` additional times. `Effect.schedule` can execute at most
`n` times because it consults the policy first. A failed schedule step uses its
expected-error channel and ends the operation; it is distinct from
`ScheduleStop`.

`spaced` measures each delay from the prior completion. `fixed` instead keeps an
anchored cadence and skips missed ticks. Exponential delays have no implicit
cap; add one explicitly with `modifyDelay` when the operation needs it:

```dart
final backoff = Schedule.exponential<String>(
  const Duration(milliseconds: 100),
).jittered().modifyDelay(
  (delay) => delay > const Duration(seconds: 10)
      ? const Duration(seconds: 10)
      : delay,
);

final loaded = request.retry(backoff);
```

Exponential scaling and jitter round down to whole microseconds and fail with a
defect if the computed delay exceeds Dart's signed 64-bit `Duration` range.
`Schedule.max` continues while both policies continue and waits for their later
delay. `Schedule.min` continues while either policy continues, reports stopped
branches as `None`, and waits for the earliest active delay. `within` uses the
runtime's monotonic clock to prevent a new start beyond its budget; work that
already started is allowed to finish. `whileInput`, `concat`, and `tap` support
input gates, sequential policies with fresh state, and effectful observation of
continuing decisions.

`Cron` is a pure calendar value with an explicit `timezone.Location`. The
application chooses and initializes the timezone database; Conflux does not
change the global local timezone:

```dart
import 'package:conflux/cron.dart';
import 'package:conflux/result.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

tz_data.initializeTimeZones();
final location = tz.getLocation('America/New_York');
final parsed = Cron.parse('0 9 * * mon-fri', location);

switch (parsed) {
  case Success(value: final cron):
    print(cron.matches(DateTime.now()));
  case Failure(error: final error):
    print('Invalid Cron: $error');
}
```

Five-field expressions use second zero; six-field expressions put seconds
first. Omitted `fromFields` values are wildcards, while explicit empty sets are
invalid. When both day-of-month and weekday are restricted, either may match.
When either begins with `*`, including `*/step`, both must match. `format`
returns six fields and keeps the location separate.

`next` and `previous` search strictly beyond the supplied instant. They verify
each candidate's local fields against timezone transitions, so spring-forward
gaps are skipped and both instants in a fall-back overlap can be returned. Each
occurrence search examines at most 10,000 calendar-day candidates within years
1 through 9999. A `CronError` caused by that work or date limit does not prove
that no occurrence exists. `sequence` searches lazily without timers or an end
date; it yields one terminal failure and then stops if a search is exhausted.

Attach a validated Cron to an Effect through `Schedule.cron`. `repeat` performs
the operation immediately, while `schedule` waits for the first future
occurrence. Map calendar search failures into the operation's domain error
before attaching the policy:

```dart
sealed class JobError {}
final class InvalidCalendar extends JobError {
  InvalidCalendar(this.error);
  final CronError error;
}

final cron = switch (Cron.parse('0 9 * * mon-fri', location)) {
  Success(value: final value) => value,
  Failure(error: final error) => throw FormatException('$error'),
};
final policy = Schedule.cron<void>(cron).mapError<JobError>(InvalidCalendar.new);
final Effect<void, JobError> job = Effect.sync(() => print('run job'));
final scheduled = job.repeat(policy);
```

Each decision reads current wall time, so a wait that becomes overdue may run
once and the following decision skips missed occurrences. Cancellation uses the
runtime Clock and removes the active wait. Scheduling and retries can repeat an
external side effect after partial success; callers own idempotency keys and
reconciliation.

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

`Flow` describes a lazy typed sequence. Each runner starts a fresh consumption
scope and awaits its cleanup. A bounded prefix closes upstream as soon as the
runner has its result:

```dart
final firstThree = Flow.fromIterable([1, 2, 3, 4])
    .map((value) => value * 2)
    .take(3)
    .runCollect();

final values = await firstThree.runFuture(); // [2, 4, 6]
```

Use a factory when adapting a Dart `Stream`, then choose how the bounded
Flow-owned buffer behaves when a producer outruns its consumer:

```dart
final events = Flow.fromStream<int, String>(
  () => eventStream,
  onError: (error, stackTrace) => 'stream failed: $error',
  capacity: 32,
  overflow: FlowOverflowPolicy.backpressure,
);
```

`Flow.fromQueue(queue)` creates competing consumers: one consumer receives each
accepted item. `Flow.fromPubSub(pubsub)` acquires an independent subscription
for every consumption, so active consumers receive each publication. These
adapters remove their pending takes and PubSub subscriptions on exit, but the
scope that acquired the shared Queue or PubSub still owns its shutdown.

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
