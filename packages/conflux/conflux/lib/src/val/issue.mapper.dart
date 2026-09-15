// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'issue.dart';

class IssueKindMapper extends EnumMapper<IssueKind> {
  IssueKindMapper._();

  static IssueKindMapper? _instance;
  static IssueKindMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = IssueKindMapper._());
    }
    return _instance!;
  }

  static IssueKind fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  IssueKind decode(dynamic value) {
    switch (value) {
      case 'missing':
        return IssueKind.missing;
      case 'invalidType':
        return IssueKind.invalidType;
      case 'invalidValue':
        return IssueKind.invalidValue;
      case 'invalidFormat':
        return IssueKind.invalidFormat;
      case 'tooSmall':
        return IssueKind.tooSmall;
      case 'tooBig':
        return IssueKind.tooBig;
      case 'invalidLength':
        return IssueKind.invalidLength;
      case 'notMultipleOf':
        return IssueKind.notMultipleOf;
      case 'unsafeInteger':
        return IssueKind.unsafeInteger;
      case 'notFinite':
        return IssueKind.notFinite;
      case 'notUnique':
        return IssueKind.notUnique;
      case 'unrecognizedKey':
        return IssueKind.unrecognizedKey;
      case 'invalidUnion':
        return IssueKind.invalidUnion;
      case 'invalidDiscriminator':
        return IssueKind.invalidDiscriminator;
      case 'maxDepth':
        return IssueKind.maxDepth;
      case 'custom':
        return IssueKind.custom;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(IssueKind self) {
    switch (self) {
      case IssueKind.missing:
        return 'missing';
      case IssueKind.invalidType:
        return 'invalidType';
      case IssueKind.invalidValue:
        return 'invalidValue';
      case IssueKind.invalidFormat:
        return 'invalidFormat';
      case IssueKind.tooSmall:
        return 'tooSmall';
      case IssueKind.tooBig:
        return 'tooBig';
      case IssueKind.invalidLength:
        return 'invalidLength';
      case IssueKind.notMultipleOf:
        return 'notMultipleOf';
      case IssueKind.unsafeInteger:
        return 'unsafeInteger';
      case IssueKind.notFinite:
        return 'notFinite';
      case IssueKind.notUnique:
        return 'notUnique';
      case IssueKind.unrecognizedKey:
        return 'unrecognizedKey';
      case IssueKind.invalidUnion:
        return 'invalidUnion';
      case IssueKind.invalidDiscriminator:
        return 'invalidDiscriminator';
      case IssueKind.maxDepth:
        return 'maxDepth';
      case IssueKind.custom:
        return 'custom';
    }
  }
}

extension IssueKindMapperExtension on IssueKind {
  dynamic toValue() {
    IssueKindMapper.ensureInitialized();
    return MapperContainer.globals.toValue<IssueKind>(this);
  }
}

class ValidationIssueMapper extends ClassMapperBase<ValidationIssue> {
  ValidationIssueMapper._();

  static ValidationIssueMapper? _instance;
  static ValidationIssueMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ValidationIssueMapper._());
      MapperContainer.globals.useAll([_PathSegmentMapper()]);
      IssueKindMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'ValidationIssue';

  static String _$code(ValidationIssue v) => v.code;
  static const Field<ValidationIssue, String> _f$code = Field('code', _$code);
  static String _$message(ValidationIssue v) => v.message;
  static const Field<ValidationIssue, String> _f$message = Field(
    'message',
    _$message,
  );
  static IssueKind _$kind(ValidationIssue v) => v.kind;
  static const Field<ValidationIssue, IssueKind> _f$kind = Field(
    'kind',
    _$kind,
  );
  static List<PathSegment> _$path(ValidationIssue v) => v.path;
  static const Field<ValidationIssue, List<PathSegment>> _f$path = Field(
    'path',
    _$path,
  );

  @override
  final MappableFields<ValidationIssue> fields = const {
    #code: _f$code,
    #message: _f$message,
    #kind: _f$kind,
    #path: _f$path,
  };

  @override
  final MappingHook hook = const _IssueWireHook();
  static ValidationIssue _instantiate(DecodingData data) {
    return ValidationIssue(
      code: data.dec(_f$code),
      message: data.dec(_f$message),
      kind: data.dec(_f$kind),
      path: data.dec(_f$path),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ValidationIssue fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ValidationIssue>(map);
  }

  static ValidationIssue fromJson(String json) {
    return ensureInitialized().decodeJson<ValidationIssue>(json);
  }
}

mixin ValidationIssueMappable {
  String toJson() {
    return ValidationIssueMapper.ensureInitialized()
        .encodeJson<ValidationIssue>(this as ValidationIssue);
  }

  Map<String, dynamic> toMap() {
    return ValidationIssueMapper.ensureInitialized().encodeMap<ValidationIssue>(
      this as ValidationIssue,
    );
  }

  ValidationIssueCopyWith<ValidationIssue, ValidationIssue, ValidationIssue>
  get copyWith =>
      _ValidationIssueCopyWithImpl<ValidationIssue, ValidationIssue>(
        this as ValidationIssue,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return ValidationIssueMapper.ensureInitialized().stringifyValue(
      this as ValidationIssue,
    );
  }

  @override
  bool operator ==(Object other) {
    return ValidationIssueMapper.ensureInitialized().equalsValue(
      this as ValidationIssue,
      other,
    );
  }

  @override
  int get hashCode {
    return ValidationIssueMapper.ensureInitialized().hashValue(
      this as ValidationIssue,
    );
  }
}

extension ValidationIssueValueCopy<$R, $Out>
    on ObjectCopyWith<$R, ValidationIssue, $Out> {
  ValidationIssueCopyWith<$R, ValidationIssue, $Out> get $asValidationIssue =>
      $base.as((v, t, t2) => _ValidationIssueCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class ValidationIssueCopyWith<$R, $In extends ValidationIssue, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<$R, PathSegment, ObjectCopyWith<$R, PathSegment, PathSegment>>
  get path;
  $R call({
    String? code,
    String? message,
    IssueKind? kind,
    List<PathSegment>? path,
  });
  ValidationIssueCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _ValidationIssueCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, ValidationIssue, $Out>
    implements ValidationIssueCopyWith<$R, ValidationIssue, $Out> {
  _ValidationIssueCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<ValidationIssue> $mapper =
      ValidationIssueMapper.ensureInitialized();
  @override
  ListCopyWith<$R, PathSegment, ObjectCopyWith<$R, PathSegment, PathSegment>>
  get path => ListCopyWith(
    $value.path,
    (v, t) => ObjectCopyWith(v, $identity, t),
    (v) => call(path: v),
  );
  @override
  $R call({
    String? code,
    String? message,
    IssueKind? kind,
    List<PathSegment>? path,
  }) => $apply(
    FieldCopyWithData({
      if (code != null) #code: code,
      if (message != null) #message: message,
      if (kind != null) #kind: kind,
      if (path != null) #path: path,
    }),
  );
  @override
  ValidationIssue $make(CopyWithData data) => ValidationIssue(
    code: data.get(#code, or: $value.code),
    message: data.get(#message, or: $value.message),
    kind: data.get(#kind, or: $value.kind),
    path: data.get(#path, or: $value.path),
  );

  @override
  ValidationIssueCopyWith<$R2, ValidationIssue, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _ValidationIssueCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

