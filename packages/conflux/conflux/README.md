# Conflux

Conflux provides pure functional values and lazy effectful composition for
Inframe. `Option` keeps absence separate from a present nullable value,
`Result` keeps synchronous expected failures in the type system, and `Effect`
adds asynchronous execution, Context access, structured concurrency, and
resource scopes.

## Validation

Conflux uses Ack for input validation. Schemas live as static methods on the
types that own the rules. Use `safeParse` to decode input and `safeEncode` to
validate and encode an existing model. For example, decode calendar fields with
`MomentParts.schema()`:

```dart
import 'package:conflux/moment.dart';

final result = MomentParts.schema().safeParse(
  {'year': 2025, 'month': 2, 'day': 29},
);
assert(result.isFail); // February 2025 has 28 days.

final encoded = MomentParts.schema().safeEncode(
  const MomentParts(year: 2024, month: 2, day: 29),
);
assert(encoded.isOk);
```

Moment and Cron factories retain their typed `Result` failures. Runtime
operations retain their argument error types and validation timing. Argument
errors use Ack constraint messages. Scalar arguments use Ack’s `debugName`
(such as `concurrency`); grouped configuration schemas report JSON Pointer
paths (such as `#/capacity`). Schemas check
input constraints; `Result.validate` and `Effect.validate` compose caller
operations and collect their expected failures.

## Usage

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
    release: (connection, context) => connection.closeEffect(),
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
Future factories, failure mappers, cancellation hooks, timeout fallbacks,
resource releases, and exit observers receive the `Context` captured where
their owning Effect is evaluated or resource is registered.

Contexts contain borrowed references. Only `acquireRelease`, `addFinalizer`,
or another explicit cleanup operation transfers ownership to an Effect scope.
Scopes interrupt and await child fibers before running finalizers once in
reverse registration order. Finalizers are protected from ordinary
cancellation, so an uncooperative finalizer can prevent bounded shutdown.

`Cache` shares scoped lookups and retains successful values with a separate
limit for active loads and stored entries:

```dart
final cachedLengths = Effect.build<(int, int), Never>(($) async {
  final cache = await $(
    Cache.make<String, int, Never>(
      capacity: 100,
      concurrency: 8,
      expiry: CacheExpiry.fixed(const Duration(minutes: 5)),
      lookup: (key, _) => Effect.succeed(key.length),
    ),
  );

  final first = await $(cache.get('conflux'));
  final second = await $(cache.get('conflux'));
  return (first, second);
});
```

`Cache.make` captures its creation scope's Context and Clock. Its lookup
callback receives `(key, context)`, and a lookup started by another caller still
uses those captured dependencies. Value-dependent expiry receives
`(key, value, context)` from the same owner. `invalidateWhere` instead receives
the calling Effect's Context. Put request-dependent data in the key or acquire
the Cache inside the request scope. Cache coordination is confined to one
isolate.

Concurrent requests for one key and generation share a load. Cancelling one
waiter leaves that owner-scoped load available to other waiters. `concurrency`
bounds active lookups, while `capacity` bounds successful retained values by
LRU. Expiry uses monotonic time from successful completion. Use
`CacheExpiry.fixed` for one TTL or `CacheExpiry.byValue` to derive it from the
key and successful value.

`getOption` and `containsKey` inspect only ready unexpired values. The `size`,
`keys`, `values`, and `entries` getters return immutable ready snapshots and
never start a lookup. `set`, `invalidate`, `invalidateAll`, and
`invalidateWhere` advance generations so older loads cannot overwrite newer
state. `refresh` starts or joins a current-generation load while an existing
unexpired value remains readable; a failed refresh keeps that value and its
original deadline.

Cached values are borrowed. Eviction, invalidation, and Cache closure do not
dispose them. Scope closure interrupts active loads, wakes waiters, and makes
later Cache use a defect. Failure caching, eviction-time disposal, durable
persistence, and automatic invalidation streams are outside this API.

Timing operations use the runtime's `Clock`, so tests can control both wall and
monotonic time. `delay` waits before starting work, `timed` reports monotonic
elapsed time, and `timeout` interrupts and awaits child cleanup before returning
its expected error:

```dart
final measured = await Effect.succeed<String, String>('ready')
    .delay(const Duration(milliseconds: 10))
    .timeout(
      const Duration(seconds: 1),
      onTimeout: (_) => 'operation timed out',
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
final loaded = Effect.defer<int, String>((_) {
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
cap; add one explicitly with `modifyDelay` when the operation needs it. Schedule
callbacks receive the consuming driver's execution `Context` as their final
argument:

```dart
final backoff = Schedule.exponential<String>(
  const Duration(milliseconds: 100),
).jittered().modifyDelay(
  (delay, _) => delay > const Duration(seconds: 10)
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

### Moment date and time

Import `package:conflux/moment.dart` for pure date-time values, or use the
convenience barrel. `UtcMoment` and `ZonedMoment` hold exact epoch microseconds;
a zoned value retains a `NamedTimeZone` or `FixedTimeZone`. Native Dart
`DateTime` interop is explicit through `fromDateTime` and `toDateTimeUtc`.
UTC and fixed offsets need no IANA initialization.

```dart
import 'package:conflux/conflux.dart';

void main() {
  final parsed = Moment.parse('2026-01-18T10:30:00.123456+08:00');
  final utc = parsed.map((value) => value.toUtc());
  print(utc.match(
    onSuccess: (value) => value.formatIso(),
    onFailure: (error) => error.message,
  ));
  // 2026-01-18T02:30:00.123456Z.
}
```

Parsing requires `year-MM-DDTHH:mm:ss[.fraction](Z|±HH:MM[:SS])`, with
1–6 fractional digits and no whitespace. Invalid fields never normalize.
Expected failures are `Result<..., MomentError>` with a diagnostic kind and
optional field. UTC and derived local fields use Dart DateTime’s full native
range, including year zero and negative years. Years follow Dart’s ISO spelling:
`0000` through `9999`, `-0001` through `-9999`, and signed six digits outside
that interval (for example, `+010000`). Parsing rejects other year spellings.

`setZone` preserves an instant. To interpret local fields, use
`Moment.zoned(parts, zone, disambiguation: ...)`; `withParts`, calendar
arithmetic, and period boundaries also require a policy. `earlier`/`later`
select the corresponding overlap instant or shift backward/forward by a gap.
`compatible` selects the earlier overlap and shifts forward in a gap;
`reject` returns a typed failure. Named lookup uses the caller's initialized
database and retains its resolved Location.

`addDuration` changes elapsed microseconds. `addCalendar` combines years and
months, clamps the day once, then adds weeks and days before resolving the
final local fields. One calendar day can differ from 24 elapsed hours across
DST. `startOf`/`endOf` use local fields and Monday weeks; a gap shift may leave
the nominal period. Boundaries outside the native range return `outOfRange`. Calendar getters include `dayOfYear` and `isoWeek`.

Equality includes representation and exact zone identity, so UTC, fixed zero,
and named UTC differ. Comparison, difference, and bounds use the instant;
`difference` returns `Result<Duration, MomentError>` with `outOfRange` if the
elapsed microseconds exceed Duration’s signed 64-bit range. `min`/`max` retain
the first input on ties. `formatIso` emits UTC with six
fractional digits; `formatIsoOffset` retains the numeric offset, including
historical seconds. Parsing offset output loses named identity.

`Effect.now()` reads the current execution's injected Clock on every run.
`Clock.wallTime()` returns `UtcMoment`; elapsed schedules, Flow timing, and
Cache TTLs continue to use monotonic `Duration` values. Custom Clock
implementations must migrate their wall-time return type.

The implementation starts at `moment.dart`: value and zone files own identity
and conversion, `local_resolution.dart` resolves transitions, and `calendar.dart`
owns calendar operations. Native calendar coordinates used during Cron search
stay in the internal date-time module. JSON persistence, locale/custom formats,
and ambient timezone services are outside this API.

`Cron` is a pure calendar value with an explicit `timezone.Location`. The
application can call `Conflux.initialize()` to load the bundled IANA database.
It retains an already initialized database and is safe to call repeatedly.
The timezone package sets its local default to UTC on first initialization;
Moment and Cron continue to use explicitly supplied zones. Applications can
also initialize a different timezone dataset themselves before this call:

```dart
import 'package:conflux/conflux.dart';
import 'package:timezone/timezone.dart' as tz;

Future<void> main() async {
  Conflux.initialize();
  final location = tz.getLocation('America/New_York');
  final parsed = Cron.parse('0 9 * * mon-fri', location);
  final now = await Effect.now().runFuture();

  switch (parsed) {
    case Success(value: final cron):
      print(cron.matches(now));
      print(cron.next(now).match(
        onSuccess: (next) => next.formatIsoOffset(),
        onFailure: (error) => error.message,
      ));
    case Failure(error: final error):
      print('Invalid Cron: $error');
  }
}
```

Five-field expressions use second zero; six-field expressions put seconds
first. Omitted `fromFields` values are wildcards, while explicit empty sets are
invalid. When both day-of-month and weekday are restricted, either may match.
When either begins with `*`, including `*/step`, both must match. `format`
returns six fields and keeps the location separate.

`matches`, `next`, `previous`, and `sequence` accept `Moment`. Successful
occurrence results are `ZonedMoment` retaining the configured Location.
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
final policy = Schedule.cron<void>(
  cron,
).mapError<JobError>((error, _) => InvalidCalendar(error));
final Effect<void, JobError> job = Effect.sync((_) => print('run job'));
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
    .map((value, _) => value * 2)
    .take(3)
    .runCollect();

final values = await firstThree.runFuture(); // [2, 4, 6]
```

Use a factory when adapting a Dart `Stream`, then choose how the bounded
Flow-owned buffer behaves when a producer outruns its consumer:

```dart
final events = Flow.fromStream<int, String>(
  (_) => eventStream,
  onError: (error, stackTrace, _) => 'stream failed: $error',
  capacity: 32,
  overflow: FlowOverflowPolicy.backpressure,
);
```

Flow source callbacks receive the source execution `Context`. Transformations,
selection, recovery, observation, and terminal consumers receive their current
consumption `Context`. Stream errors and overflow retain the `Context` captured
when that subscription opened. The named `context` arguments on `subscribe`
and `toStream` still select the root execution context.
Concurrent flattening mappers and `withLatestFrom` combiners receive the
operator's execution `Context`. Delayed overflow callbacks for merge and
combination buffers retain that same owning region.
Shared Flow work and overflow remain in the first subscriber's connection
`Context`; live and replayed values are observed in each subscriber's own
region. Timed buffer, debounce, and throttle overflow callbacks retain their
operator's execution `Context` across timer activity.

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
dart test packages/conflux/conflux/test --chain-stack-traces
```

## Val validation

Import `package:conflux/val.dart` or the `conflux.dart` barrel. Validation is
synchronous and needs no runtime, clock, or timezone setup.

```dart
final profile = Val.object({
  'name': Val.string(name: 'Name').notEmpty(),
  'nickname': Val.string().optional(),
});
final result = profile.safeParse({'name': 'Ada'});
// Result<Map<String, Object?>, NonEmptyList<ValidationIssue>>
```

`safeParse` returns the existing Conflux Result. `parse` throws
`ValidationException` containing the same ordered issues on failure. Each issue
has a string `code`, a `message`, an `IssueKind`, and an immutable path of `Field`
and `Index` segments. A refinement path is relative to its schema.

Fields are required by default. `optional()` omits missing fields without
accepting present null; `nullable()` accepts present null and changes the output
type. Presence uses the last `required()`/`optional()` selection. Nullable
wrapping skips preceding checks for null; later refinements receive null.

Objects reject extra keys by default. `strict()` customizes rejection,
`strip()` removes extras before refinements, and `passthrough()` retains them.
Policies apply only to the selected object. Object refinements run only after
all declared fields and the unknown-key policy pass. Compatible checks collect
failures in declaration order; fields use schema order and extras use input order.

Schema names label generated messages, while custom messages remain verbatim.
Codes and messages may be overridden independently; null selects the default,
and an empty string is an explicit override. Names never change structural paths.
String lengths count UTF-16 code units. Schema derivations and validated
containers are immutable and detached; passthrough values remain borrowed.
Callback exceptions propagate, and repeated parsing may invoke callbacks again.

Implementation reading path: `val.dart` → factories in `src/val/val.dart` →
typed stages in `schema.dart` → primitive and container validators. Foundational
Result/Option modules do not depend on Val.
