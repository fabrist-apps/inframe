import 'package:artificer_core/json.dart';

/// One typed native beta Messages stream event.
sealed class BasetenMessageEvent {
  const BasetenMessageEvent(this.raw);

  /// Complete immutable event data.
  final JsonObject raw;

  /// Native event discriminator.
  String get type;
}

/// A recognized beta Messages event whose payload remains available intact.
final class BasetenKnownMessageEvent extends BasetenMessageEvent {
  /// Creates a recognized event.
  const BasetenKnownMessageEvent(this.type, super.raw);

  @override
  final String type;
}

/// The documented terminal beta Messages event.
final class BasetenMessageStopEvent extends BasetenMessageEvent {
  /// Creates the terminal event.
  const BasetenMessageStopEvent(super.raw);

  @override
  String get type => 'message_stop';
}

/// A future or unrecognized beta Messages event retained without loss.
final class BasetenUnknownMessageEvent extends BasetenMessageEvent {
  /// Creates an unknown event.
  const BasetenUnknownMessageEvent(this.type, super.raw);

  @override
  final String type;
}
