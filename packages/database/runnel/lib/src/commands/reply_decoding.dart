import 'package:runnel/src/resp/resp_value.dart';

/// Shared reply shapes used by ordinary command families.
extension CommandReply on RespValue {
  /// Requires an integer reply without coercing text or booleans.
  int get integer => switch (this) {
    RespInteger(:final value) => value,
    _ => throw FormatException('Expected an integer reply, received $runtimeType.'),
  };

  /// Requires an array reply, retaining its order and duplicates.
  List<RespValue> get array => switch (this) {
    RespArray(:final values) => values,
    _ => throw FormatException('Expected an array reply, received $runtimeType.'),
  };

  /// Decodes null or strict UTF-8 text.
  String? get nullableText => this is RespNull ? null : respText(this);

  /// Decodes an immutable array of nullable text values.
  List<String?> get nullableTextList => List.unmodifiable(
    array.map((value) => value.nullableText),
  );

  /// Requires Redis's OK acknowledgement.
  void requireOkay({String message = 'Expected an OK reply.'}) {
    if (respText(this) != 'OK') throw FormatException(message);
  }
}
