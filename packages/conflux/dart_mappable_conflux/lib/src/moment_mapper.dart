import 'package:conflux/moment.dart';
import 'package:conflux/result.dart';
import 'package:dart_mappable/dart_mappable.dart';

/// Serializes Moment as an ISO timestamp with its current offset.
///
/// Decoding retains fixed offsets, including historical seconds. Named zones
/// become fixed zones; their identity and future DST rules are not serialized.
final class MomentMapper extends SimpleMapper<Moment> {
  const MomentMapper();

  @override
  Moment decode(Object value) {
    if (value is! String) {
      throw FormatException('Expected an ISO timestamp string.', value);
    }

    return switch (Moment.parse(value)) {
      Success(:final value) => value,
      Failure(:final error) => throw FormatException(error.message, value),
    };
  }

  @override
  Object encode(Moment self) => self.formatIsoOffset();
}
