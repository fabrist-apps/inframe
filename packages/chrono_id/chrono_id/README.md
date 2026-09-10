# Chrono ID

`chrono_id` generates timestamp-bearing string IDs and validates their structure.

```dart
import 'package:chrono_id/chrono_id.dart';

final id = ChronoID.generate();
final userId = ChronoID.generate(prefix: 'use');
final longerUserId = ChronoID.generate(prefix: 'use', size: 32);

final valid = ChronoID.isValid(userId, prefix: 'use');
```

An ID has this format:

```text
[prefix_]<8-character base62 timestamp><random alphanumeric suffix>
```

`size` counts the timestamp and random suffix. It excludes the optional prefix and `_`
separator, defaults to 24, and must be at least 16. A prefix starts with an ASCII letter and
contains only ASCII letters and digits.

The timestamp is Unix milliseconds encoded with
`0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz`. The suffix uses characters from the
same alphabet and is sampled with `Random.secure()`. Failure to obtain secure randomness is
reported to the caller without a weaker fallback.

Validation checks the exact prefix, body length, and alphabet. It does not trim or normalize the
input, establish where an ID came from, or guarantee uniqueness. Uniqueness is probabilistic: the
default 16-character suffix contains about 95 bits of randomness, and the package does not detect
collisions or retry them.

For IDs with the same prefix, different timestamps sort by encoded time under case-sensitive ASCII
comparison. IDs created in one millisecond have random order. Prefixes sort before timestamps, and
clock rollback or skew can make a later-generated ID sort earlier. Generation is not monotonic or
globally ordered.
