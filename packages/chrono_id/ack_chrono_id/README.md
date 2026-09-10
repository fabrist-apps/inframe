# Ack Chrono ID

`ack_chrono_id` adds Chrono ID validation to Ack string schemas while keeping `chrono_id` as the
owner of the ID format.

```dart
import 'package:ack/ack.dart';
import 'package:ack_chrono_id/ack_chrono_id.dart';
import 'package:chrono_id/chrono_id.dart';

final userSchema = Ack.object({
  'id': Ack.string().chronoId(prefix: 'use'),
  'parentId': Ack.string().chronoId(prefix: 'use').optional(),
});

final id = ChronoID.generate(prefix: 'use');
final result = userSchema.safeParse({'id': id});
```

Successful validation preserves the original string. Invalid values produce ordinary Ack
validation errors at their field paths. Supply `message` to replace the default refinement error:

```dart
final idSchema = Ack.string().chronoId(
  prefix: 'use',
  message: 'Use a user Chrono ID.',
);
```

`size` defaults to 24 and counts the timestamp and random suffix only. It excludes the optional
prefix and `_` separator. Invalid size or prefix configuration throws `ArgumentError` when
`.chronoId()` constructs the schema.

The extension returns a new `StringSchema`, so existing and subsequent Ack constraints compose with
Chrono ID validation. Ack continues to control string type errors, optional fields, and nullable
values.

Chrono ID uniqueness is probabilistic. The default suffix contains about 95 bits of randomness,
without collision detection or retries. IDs with the same prefix sort by timestamp, except that
IDs created within one millisecond have random order and clock rollback or skew can reverse
generation order. Different prefixes sort by prefix first.

Ack runtime refinements do not export Chrono ID rules to JSON Schema. JSON Schema integration is
outside this package's current contract.
