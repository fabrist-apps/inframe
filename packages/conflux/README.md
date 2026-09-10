# Conflux

Conflux provides pure functional values and effectful composition for Inframe.
The current API includes `Option`, which keeps absence separate from a present
nullable value.

```dart
import 'package:conflux/conflux.dart';

const Option<String?> missing = None();
const Option<String?> cleared = Some(null);
const Option<String?> supplied = Some('Bhaswanth');

String describe(Option<String?> option) => option.match(
  onSome: (value) => 'Supplied: $value',
  onNone: () => 'Not supplied',
);
```

`getOrNull()` intentionally maps both `None()` and `Some(null)` to `null`. Use
`match` or an exhaustive switch when that distinction matters. Fallbacks and
transformation callbacks run only for the branch that needs them. Exceptions
thrown by callbacks remain ordinary Dart exceptions.

Run the package tests from the repository root:

```sh
dart test packages/conflux/test --chain-stack-traces
```
