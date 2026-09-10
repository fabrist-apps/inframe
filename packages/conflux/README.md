# Conflux

Conflux provides pure functional values and effectful composition for Inframe.
The current API includes `Option`, which keeps absence separate from a present
nullable value, and `Result`, which keeps expected failures in the type system.

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
