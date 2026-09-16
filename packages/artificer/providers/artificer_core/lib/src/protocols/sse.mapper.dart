// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'sse.dart';

class SseEventMapper extends ClassMapperBase<SseEvent> {
  SseEventMapper._();

  static SseEventMapper? _instance;
  static SseEventMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = SseEventMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'SseEvent';

  static String _$data(SseEvent v) => v.data;
  static const Field<SseEvent, String> _f$data = Field('data', _$data);
  static String? _$event(SseEvent v) => v.event;
  static const Field<SseEvent, String> _f$event = Field(
    'event',
    _$event,
    opt: true,
  );
  static String? _$id(SseEvent v) => v.id;
  static const Field<SseEvent, String> _f$id = Field('id', _$id, opt: true);
  static int? _$retry(SseEvent v) => v.retry;
  static const Field<SseEvent, int> _f$retry = Field(
    'retry',
    _$retry,
    opt: true,
  );

  @override
  final MappableFields<SseEvent> fields = const {
    #data: _f$data,
    #event: _f$event,
    #id: _f$id,
    #retry: _f$retry,
  };

  static SseEvent _instantiate(DecodingData data) {
    return SseEvent(
      data: data.dec(_f$data),
      event: data.dec(_f$event),
      id: data.dec(_f$id),
      retry: data.dec(_f$retry),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static SseEvent fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<SseEvent>(map);
  }

  static SseEvent fromJson(String json) {
    return ensureInitialized().decodeJson<SseEvent>(json);
  }
}

mixin SseEventMappable {
  String toJson() {
    return SseEventMapper.ensureInitialized().encodeJson<SseEvent>(
      this as SseEvent,
    );
  }

  Map<String, dynamic> toMap() {
    return SseEventMapper.ensureInitialized().encodeMap<SseEvent>(
      this as SseEvent,
    );
  }

  SseEventCopyWith<SseEvent, SseEvent, SseEvent> get copyWith =>
      _SseEventCopyWithImpl<SseEvent, SseEvent>(
        this as SseEvent,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return SseEventMapper.ensureInitialized().stringifyValue(this as SseEvent);
  }

  @override
  bool operator ==(Object other) {
    return SseEventMapper.ensureInitialized().equalsValue(
      this as SseEvent,
      other,
    );
  }

  @override
  int get hashCode {
    return SseEventMapper.ensureInitialized().hashValue(this as SseEvent);
  }
}

extension SseEventValueCopy<$R, $Out> on ObjectCopyWith<$R, SseEvent, $Out> {
  SseEventCopyWith<$R, SseEvent, $Out> get $asSseEvent =>
      $base.as((v, t, t2) => _SseEventCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class SseEventCopyWith<$R, $In extends SseEvent, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({String? data, String? event, String? id, int? retry});
  SseEventCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _SseEventCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, SseEvent, $Out>
    implements SseEventCopyWith<$R, SseEvent, $Out> {
  _SseEventCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<SseEvent> $mapper =
      SseEventMapper.ensureInitialized();
  @override
  $R call({
    String? data,
    Object? event = $none,
    Object? id = $none,
    Object? retry = $none,
  }) => $apply(
    FieldCopyWithData({
      if (data != null) #data: data,
      if (event != $none) #event: event,
      if (id != $none) #id: id,
      if (retry != $none) #retry: retry,
    }),
  );
  @override
  SseEvent $make(CopyWithData data) => SseEvent(
    data: data.get(#data, or: $value.data),
    event: data.get(#event, or: $value.event),
    id: data.get(#id, or: $value.id),
    retry: data.get(#retry, or: $value.retry),
  );

  @override
  SseEventCopyWith<$R2, SseEvent, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _SseEventCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

