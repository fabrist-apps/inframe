# dart_mappable_conflux

Custom dart_mappable mappers for Conflux `Moment` and `Option`.

```dart
import 'package:conflux/moment.dart';
import 'package:conflux/option.dart';
import 'package:dart_mappable/dart_mappable.dart';
import 'package:dart_mappable_conflux/dart_mappable_conflux.dart';

part 'event.mapper.dart';

@MappableClass(
  includeCustomMappers: [MomentMapper(), OptionMapper()],
  hook: OptionFieldsHook(['occurred_at']),
)
class Event with EventMappable {
  const Event(this.occurredAt);

  @MappableField(key: 'occurred_at')
  final Option<Moment?> occurredAt;
}
```

Generate the consumer's mapper with `dart run build_runner build`.

| Dart field value | Encoded object |
| --- | --- |
| `None()` | `{}` |
| `Some(null)` | `{"occurred_at": null}` |
| `Some(moment)` | `{"occurred_at": "2026-01-18T10:30:00.123456+08:00"}` |

Only the class-level `OptionFieldsHook` is required. It takes the
serialized keys, including renames. It restores missing fields as `None()` and
present null as `Some(null)`; null fails when the wrapped type is non-nullable.
It copies input maps before changing them.

dart_mappable performs normal class encoding. `OptionMapper` encodes `Some(value)`
using the wrapped value's mapper and `None()` as an internal omission marker.
`OptionFieldsHook.afterEncode` removes markers only at the configured paths.
Paths such as `profile.nickname` traverse maps using serialized keys. Missing or
non-map parents are left unchanged; array indexing and literal dots in keys are
not supported. During decoding the same paths distinguish missing from null.

`toValue` and `toMap` can retain markers at the root, in lists, or at unlisted
paths. Those markers are not JSON encodable: `toJson` rejects them with
`JsonUnsupportedObjectError`. There is no additional validation pass on raw map
output. `Some(None())` is rejected by the mapper to avoid collapsing nested absence.

Raw null is handled by dart_mappable before custom mappers run. Consequently,
decoding null directly with `MapperContainer.fromValue<Option<T?>>(null)` does
not produce `Some(null)`; the class hook provides that distinction for
model fields. The same limitation applies to null elements in lists of Options.

`MomentMapper` writes six fractional digits and the current offset. `Z` decodes
as `UtcMoment`; numeric offsets decode as fixed-zone `ZonedMoment`, including
`+00:00` and historical offset seconds. Named timezone identity and future DST
rules are not retained. Decoding needs no timezone database initialization.
Invalid timestamps fail with `MapperException` through dart_mappable.

Register both mappers at startup (repeated calls are safe):

```dart
ConfluxMappers.initialize();
```
