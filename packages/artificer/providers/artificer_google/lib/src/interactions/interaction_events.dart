import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/json.dart';
import 'package:artificer_google/src/interactions/interaction_models.dart';

/// One stable-v1 native Interactions stream event.
sealed class GoogleInteractionEvent {
  const GoogleInteractionEvent._({
    required this.eventType,
    required this.eventId,
    required this.sseId,
    required this.sseEvent,
    required this.retry,
    required this.raw,
    required this.extensions,
  });

  /// Decodes one event payload from the 2026-09-12 stable-v1 snapshot.
  factory GoogleInteractionEvent.fromJson(
    JsonObject raw, {
    String? sseId,
    String? sseEvent,
    Duration? retry,
  }) {
    final value = raw.toDart();
    final eventType = _string(value, 'event_type');
    final eventId = _optionalString(value, 'event_id');
    GoogleInteractionEvent base({
      required Set<String> fields,
      required GoogleInteractionEvent Function(JsonObject extensions) create,
    }) => create(JsonObject(_without(value, {'event_type', 'event_id', ...fields})));

    return switch (eventType) {
      'interaction.created' => base(
        fields: {'interaction'},
        create: (extensions) => GoogleInteractionCreatedEvent._(
          interaction: _interaction(value, 'interaction'),
          eventId: eventId,
          sseId: sseId,
          sseEvent: sseEvent,
          retry: retry,
          raw: raw,
          extensions: extensions,
        ),
      ),
      'interaction.completed' => base(
        fields: {'interaction'},
        create: (extensions) => GoogleInteractionCompletedEvent._(
          interaction: _interaction(value, 'interaction'),
          eventId: eventId,
          sseId: sseId,
          sseEvent: sseEvent,
          retry: retry,
          raw: raw,
          extensions: extensions,
        ),
      ),
      'interaction.status_update' => base(
        fields: {'interaction_id', 'status'},
        create: (extensions) {
          final nativeStatus = _string(value, 'status');
          return GoogleInteractionStatusEvent._(
            interactionId: _string(value, 'interaction_id'),
            status: _status(nativeStatus),
            nativeStatus: nativeStatus,
            eventId: eventId,
            sseId: sseId,
            sseEvent: sseEvent,
            retry: retry,
            raw: raw,
            extensions: extensions,
          );
        },
      ),
      'step.start' => base(
        fields: {'index', 'step'},
        create: (extensions) => GoogleInteractionStepStartEvent._(
          index: _integer(value, 'index'),
          step: GoogleInteractionStep.fromJson(_object(value, 'step')),
          eventId: eventId,
          sseId: sseId,
          sseEvent: sseEvent,
          retry: retry,
          raw: raw,
          extensions: extensions,
        ),
      ),
      'step.delta' => base(
        fields: {'index', 'delta', 'metadata'},
        create: (extensions) => GoogleInteractionStepDeltaEvent._(
          index: _integer(value, 'index'),
          delta: GoogleInteractionStepDelta.fromJson(_object(value, 'delta')),
          metadata: _metadata(value, 'metadata'),
          eventId: eventId,
          sseId: sseId,
          sseEvent: sseEvent,
          retry: retry,
          raw: raw,
          extensions: extensions,
        ),
      ),
      'step.stop' => base(
        fields: {'index', 'step_usage', 'usage'},
        create: (extensions) => GoogleInteractionStepStopEvent._(
          index: _integer(value, 'index'),
          stepUsage: _usage(value, 'step_usage'),
          usage: _usage(value, 'usage'),
          eventId: eventId,
          sseId: sseId,
          sseEvent: sseEvent,
          retry: retry,
          raw: raw,
          extensions: extensions,
        ),
      ),
      'error' => base(
        fields: {'error'},
        create: (extensions) => GoogleInteractionErrorEvent._(
          error: _error(value, 'error'),
          eventId: eventId,
          sseId: sseId,
          sseEvent: sseEvent,
          retry: retry,
          raw: raw,
          extensions: extensions,
        ),
      ),
      _ => GoogleUnknownInteractionEvent._(
        eventType: eventType,
        eventId: eventId,
        sseId: sseId,
        sseEvent: sseEvent,
        retry: retry,
        raw: raw,
        extensions: JsonObject(_without(value, {'event_type', 'event_id'})),
      ),
    };
  }

  /// The exact native event discriminator.
  final String eventType;

  /// The provider cursor for explicit resumption from the next event.
  final String? eventId;

  /// The SSE framing ID, retained independently from [eventId].
  final String? sseId;

  /// The SSE framing event name, when present.
  final String? sseEvent;

  /// The server-suggested retry duration, retained without automatic reconnect.
  final Duration? retry;

  /// The complete native event payload.
  final JsonObject raw;

  /// Fields outside the typed event snapshot.
  final JsonObject extensions;
}

/// Initial interaction identity and status.
final class GoogleInteractionCreatedEvent extends GoogleInteractionEvent {
  GoogleInteractionCreatedEvent._({
    required this.interaction,
    required super.eventId,
    required super.sseId,
    required super.sseEvent,
    required super.retry,
    required super.raw,
    required super.extensions,
  }) : super._(eventType: 'interaction.created');

  /// The partial interaction resource supplied by the event.
  final GoogleInteraction interaction;
}

/// Final interaction resource for a completed stream attempt.
final class GoogleInteractionCompletedEvent extends GoogleInteractionEvent {
  GoogleInteractionCompletedEvent._({
    required this.interaction,
    required super.eventId,
    required super.sseId,
    required super.sseEvent,
    required super.retry,
    required super.raw,
    required super.extensions,
  }) : super._(eventType: 'interaction.completed');

  /// The partial terminal interaction resource supplied by the event.
  final GoogleInteraction interaction;
}

/// A lifecycle status update for an interaction.
final class GoogleInteractionStatusEvent extends GoogleInteractionEvent {
  GoogleInteractionStatusEvent._({
    required this.interactionId,
    required this.status,
    required this.nativeStatus,
    required super.eventId,
    required super.sseId,
    required super.sseEvent,
    required super.retry,
    required super.raw,
    required super.extensions,
  }) : super._(eventType: 'interaction.status_update');

  /// The interaction whose status changed.
  final String interactionId;

  /// The typed lifecycle state.
  final GoogleInteractionStatus status;

  /// The exact provider status string.
  final String nativeStatus;
}

/// The beginning of one ordered interaction step.
final class GoogleInteractionStepStartEvent extends GoogleInteractionEvent {
  GoogleInteractionStepStartEvent._({
    required this.index,
    required this.step,
    required super.eventId,
    required super.sseId,
    required super.sseEvent,
    required super.retry,
    required super.raw,
    required super.extensions,
  }) : super._(eventType: 'step.start');

  /// The stable step position in the interaction.
  final int index;

  /// The typed step identity and initial fields.
  final GoogleInteractionStep step;
}

/// One ordered update to an interaction step.
final class GoogleInteractionStepDeltaEvent extends GoogleInteractionEvent {
  GoogleInteractionStepDeltaEvent._({
    required this.index,
    required this.delta,
    required this.metadata,
    required super.eventId,
    required super.sseId,
    required super.sseEvent,
    required super.retry,
    required super.raw,
    required super.extensions,
  }) : super._(eventType: 'step.delta');

  /// The stable step position in the interaction.
  final int index;

  /// The typed incremental payload.
  final GoogleInteractionStepDelta delta;

  /// Optional cumulative metadata accompanying the delta.
  final GoogleInteractionDeltaMetadata? metadata;
}

/// Completion and usage for one interaction step.
final class GoogleInteractionStepStopEvent extends GoogleInteractionEvent {
  GoogleInteractionStepStopEvent._({
    required this.index,
    required this.stepUsage,
    required this.usage,
    required super.eventId,
    required super.sseId,
    required super.sseEvent,
    required super.retry,
    required super.raw,
    required super.extensions,
  }) : super._(eventType: 'step.stop');

  /// The stable step position in the interaction.
  final int index;

  /// Usage attributable to this step.
  final GoogleInteractionUsage? stepUsage;

  /// Cumulative interaction usage at this point.
  final GoogleInteractionUsage? usage;
}

/// An HTTP-200 service error event.
final class GoogleInteractionErrorEvent extends GoogleInteractionEvent {
  GoogleInteractionErrorEvent._({
    required this.error,
    required super.eventId,
    required super.sseId,
    required super.sseEvent,
    required super.retry,
    required super.raw,
    required super.extensions,
  }) : super._(eventType: 'error');

  /// Provider error details, when supplied.
  final GoogleInteractionError? error;
}

/// An event outside the pinned snapshot, retained without loss.
final class GoogleUnknownInteractionEvent extends GoogleInteractionEvent {
  GoogleUnknownInteractionEvent._({
    required super.eventType,
    required super.eventId,
    required super.sseId,
    required super.sseEvent,
    required super.retry,
    required super.raw,
    required super.extensions,
  }) : super._();
}

/// One incremental step payload from the stable-v1 delta union.
sealed class GoogleInteractionStepDelta {
  const GoogleInteractionStepDelta._({
    required this.type,
    required this.owner,
    required this.text,
    required this.arguments,
    required this.data,
    required this.uri,
    required this.mimeType,
    required this.result,
    required this.isError,
    required this.name,
    required this.signature,
    required this.content,
    required this.annotations,
    required this.channels,
    required this.sampleRate,
    required this.resolution,
    required this.raw,
    required this.extensions,
  });

  /// Decodes one delta and selects the explicit unknown variant when needed.
  factory GoogleInteractionStepDelta.fromJson(JsonObject raw) {
    final value = raw.toDart();
    final type = _string(value, 'type');
    final fields = _DecodedDelta(
      type: type,
      owner: switch (type) {
        'arguments_delta' || 'function_result' => ToolExecutionOwner.caller,
        final value when _providerDeltaTypes.contains(value) => ToolExecutionOwner.provider,
        _ => null,
      },
      text: _optionalString(value, 'text'),
      arguments: value.containsKey('arguments') ? JsonValue.fromDart(value['arguments']) : null,
      data: _optionalString(value, 'data'),
      uri: _optionalString(value, 'uri'),
      mimeType: _optionalString(value, 'mime_type'),
      result: value.containsKey('result') ? JsonValue.fromDart(value['result']) : null,
      isError: _optionalBool(value, 'is_error'),
      name: _optionalString(value, 'name'),
      signature: _optionalString(value, 'signature'),
      content: switch (value['content']) {
        null => null,
        final Map<String, Object?> content => GoogleInteractionContent.fromJson(
          JsonObject(content),
        ),
        _ => throw const FormatException('delta.content must be an object.'),
      },
      annotations: _annotations(value, 'annotations'),
      channels: _optionalInt(value, 'channels'),
      sampleRate: _optionalInt(value, 'sample_rate'),
      resolution: _optionalString(value, 'resolution'),
      raw: raw,
      extensions: JsonObject(_without(value, _deltaFields)),
    );
    return _knownDeltaTypes.contains(type)
        ? _KnownGoogleInteractionStepDelta._(fields)
        : GoogleUnknownInteractionStepDelta._(fields);
  }

  /// The exact delta discriminator.
  final String type;

  /// Who executes the represented tool activity, when the type establishes it.
  final ToolExecutionOwner? owner;

  /// Incremental visible text.
  final String? text;

  /// Function or hosted-tool arguments in their native incremental shape.
  final JsonValue? arguments;

  /// Incremental base64 media data.
  final String? data;

  /// Incremental provider media URI.
  final String? uri;

  /// Native media MIME type.
  final String? mimeType;

  /// Incremental tool result in its native shape.
  final JsonValue? result;

  /// Whether a tool result represents an error.
  final bool? isError;

  /// Application function name, when present.
  final String? name;

  /// Opaque provider replay signature, when present.
  final String? signature;

  /// One appended thought-summary content item.
  final GoogleInteractionContent? content;

  /// Citation updates attached to streamed text.
  final List<GoogleInteractionAnnotation>? annotations;

  /// Number of streamed audio channels.
  final int? channels;

  /// Streamed audio sample rate in hertz.
  final int? sampleRate;

  /// Streamed media resolution.
  final String? resolution;

  /// The complete native delta payload.
  final JsonObject raw;

  /// Fields outside the typed delta snapshot.
  final JsonObject extensions;
}

final class _KnownGoogleInteractionStepDelta extends GoogleInteractionStepDelta {
  _KnownGoogleInteractionStepDelta._(_DecodedDelta value)
    : super._(
        type: value.type,
        owner: value.owner,
        text: value.text,
        arguments: value.arguments,
        data: value.data,
        uri: value.uri,
        mimeType: value.mimeType,
        result: value.result,
        isError: value.isError,
        name: value.name,
        signature: value.signature,
        content: value.content,
        annotations: value.annotations,
        channels: value.channels,
        sampleRate: value.sampleRate,
        resolution: value.resolution,
        raw: value.raw,
        extensions: value.extensions,
      );
}

/// A delta outside the pinned snapshot, retained without loss.
final class GoogleUnknownInteractionStepDelta extends GoogleInteractionStepDelta {
  GoogleUnknownInteractionStepDelta._(_DecodedDelta value)
    : super._(
        type: value.type,
        owner: value.owner,
        text: value.text,
        arguments: value.arguments,
        data: value.data,
        uri: value.uri,
        mimeType: value.mimeType,
        result: value.result,
        isError: value.isError,
        name: value.name,
        signature: value.signature,
        content: value.content,
        annotations: value.annotations,
        channels: value.channels,
        sampleRate: value.sampleRate,
        resolution: value.resolution,
        raw: value.raw,
        extensions: value.extensions,
      );
}

/// Optional metadata accompanying a step delta.
final class GoogleInteractionDeltaMetadata {
  GoogleInteractionDeltaMetadata._({
    required this.totalUsage,
    required this.raw,
    required this.extensions,
  });

  /// Decodes delta metadata while retaining unknown fields.
  factory GoogleInteractionDeltaMetadata.fromJson(JsonObject raw) {
    final value = raw.toDart();
    return GoogleInteractionDeltaMetadata._(
      totalUsage: _usage(value, 'total_usage'),
      raw: raw,
      extensions: JsonObject(_without(value, {'total_usage'})),
    );
  }

  /// Cumulative interaction usage at this delta.
  final GoogleInteractionUsage? totalUsage;

  /// The complete native metadata.
  final JsonObject raw;

  /// Fields outside the typed metadata snapshot.
  final JsonObject extensions;
}

final class _DecodedDelta {
  const _DecodedDelta({
    required this.type,
    required this.owner,
    required this.text,
    required this.arguments,
    required this.data,
    required this.uri,
    required this.mimeType,
    required this.result,
    required this.isError,
    required this.name,
    required this.signature,
    required this.content,
    required this.annotations,
    required this.channels,
    required this.sampleRate,
    required this.resolution,
    required this.raw,
    required this.extensions,
  });

  final String type;
  final ToolExecutionOwner? owner;
  final String? text;
  final JsonValue? arguments;
  final String? data;
  final String? uri;
  final String? mimeType;
  final JsonValue? result;
  final bool? isError;
  final String? name;
  final String? signature;
  final GoogleInteractionContent? content;
  final List<GoogleInteractionAnnotation>? annotations;
  final int? channels;
  final int? sampleRate;
  final String? resolution;
  final JsonObject raw;
  final JsonObject extensions;
}

const Set<String> _providerDeltaTypes = {
  'code_execution_call',
  'code_execution_result',
  'file_search_call',
  'file_search_result',
  'google_maps_call',
  'google_maps_result',
  'google_search_call',
  'google_search_result',
  'url_context_call',
  'url_context_result',
};

const Set<String> _knownDeltaTypes = {
  'arguments_delta',
  'audio',
  'document',
  'function_result',
  'image',
  'text',
  'text_annotation_delta',
  'thought_signature',
  'thought_summary',
  ..._providerDeltaTypes,
};

const Set<String> _deltaFields = {
  'type',
  'text',
  'arguments',
  'data',
  'uri',
  'mime_type',
  'result',
  'is_error',
  'name',
  'signature',
  'content',
  'annotations',
  'channels',
  'sample_rate',
  'resolution',
};

GoogleInteraction _interaction(Map<String, Object?> value, String key) {
  final interaction = GoogleInteraction.fromJson(_object(value, key));
  if (interaction.id == null || interaction.id!.isEmpty) {
    throw FormatException('$key.id must be a nonempty string.');
  }
  return interaction;
}

GoogleInteractionDeltaMetadata? _metadata(Map<String, Object?> value, String key) =>
    switch (value[key]) {
      null => null,
      final Map<String, Object?> metadata => GoogleInteractionDeltaMetadata.fromJson(
        JsonObject(metadata),
      ),
      _ => throw FormatException('$key must be an object.'),
    };

GoogleInteractionUsage? _usage(Map<String, Object?> value, String key) => switch (value[key]) {
  null => null,
  final Map<String, Object?> usage => GoogleInteractionUsage.fromJson(JsonObject(usage)),
  _ => throw FormatException('$key must be an object.'),
};

GoogleInteractionError? _error(Map<String, Object?> value, String key) => switch (value[key]) {
  null => null,
  final Map<String, Object?> error => GoogleInteractionError.fromJson(JsonObject(error)),
  _ => throw FormatException('$key must be an object.'),
};

List<GoogleInteractionAnnotation>? _annotations(
  Map<String, Object?> value,
  String key,
) => switch (value[key]) {
  null => null,
  final List<Object?> annotations => List.unmodifiable(
    annotations.map(
      (annotation) => GoogleInteractionAnnotation.fromJson(
        annotation is Map<String, Object?>
            ? JsonObject(annotation)
            : throw FormatException('$key entries must be objects.'),
      ),
    ),
  ),
  _ => throw FormatException('$key must be an array.'),
};

JsonObject _object(Map<String, Object?> value, String key) => switch (value[key]) {
  final Map<String, Object?> object => JsonObject(object),
  _ => throw FormatException('$key must be an object.'),
};

String _string(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field is! String || field.isEmpty) {
    throw FormatException('$key must be a nonempty string.');
  }
  return field;
}

String? _optionalString(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field == null) return null;
  if (field is! String) throw FormatException('$key must be a string.');
  return field;
}

int _integer(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field is! int) throw FormatException('$key must be an integer.');
  return field;
}

int? _optionalInt(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field == null) return null;
  if (field is! int) throw FormatException('$key must be an integer.');
  return field;
}

bool? _optionalBool(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field == null) return null;
  if (field is! bool) throw FormatException('$key must be a boolean.');
  return field;
}

Map<String, Object?> _without(Map<String, Object?> value, Set<String> fields) =>
    Map.fromEntries(value.entries.where((entry) => !fields.contains(entry.key)));

GoogleInteractionStatus _status(String value) => switch (value) {
  'in_progress' => GoogleInteractionStatus.inProgress,
  'requires_action' => GoogleInteractionStatus.requiresAction,
  'completed' => GoogleInteractionStatus.completed,
  'failed' => GoogleInteractionStatus.failed,
  'cancelled' => GoogleInteractionStatus.cancelled,
  'incomplete' => GoogleInteractionStatus.incomplete,
  _ => GoogleInteractionStatus.unknown,
};
