// The declaration DSL relies on inferred field types for generated output.
// ignore_for_file: specify_nonobvious_property_types

import 'dart:typed_data';

import 'package:rivet/rivet.dart';

part 'generated_consumer.g.dart';

@RivetTable(schema: 'fbr116', name: 'userProfiles', renamedFrom: 'profiles')
final class UserProfiles extends RivetTableDefinition<UserProfiles> {
  static const db = _$UserProfilesDB();

  late final displayName = text()();
  late final posts = many<Posts>()();
  late final _indexes = [
    index('display_name_idx').on([displayName.asc()]),
  ];
  late final _constraints = [check('display_name_present', displayName.equals(''))];
}

@RivetTable(schema: 'fbr116')
final class Posts extends RivetTableDefinition<Posts> {
  static const db = _$PostsDB();

  late final authorName = text().references<UserProfiles>((users) => users.displayName)();
  late final author = one<UserProfiles>(
    fields: [authorName],
    references: (users) => [users.displayName],
  )();
}

final class UserCode {
  const UserCode(this.value);

  final String value;
}

final class UserCodeConverter implements RivetTypeConverter<UserCode, String> {
  const UserCodeConverter();

  @override
  UserCode fromSql(String value) => UserCode(value);

  @override
  String toSql(UserCode value) => value.value;
}

final class Preferences {
  const Preferences({required this.darkMode});

  final bool darkMode;
}

final class PreferencesConverter implements RivetTypeConverter<Preferences, JsonValue> {
  const PreferencesConverter();

  @override
  Preferences fromSql(JsonValue value) {
    final json = value.toDart();
    if (json is! Map<String, Object?> || json['darkMode'] is! bool) {
      throw const FormatException('expected preferences JSON');
    }
    return Preferences(darkMode: json['darkMode']! as bool);
  }

  @override
  JsonValue toSql(Preferences value) => JsonValue.from({'darkMode': value.darkMode});
}

@RivetTable(schema: 'fbr119')
final class ScalarValues extends RivetTableDefinition<ScalarValues> {
  static const db = _$ScalarValuesDB();

  late final id = chronoID(prefix: 'usr')();
  late final count = integer()();
  late final score = real()();
  late final active = boolean()();
  late final createdAt = dateTime()();
  late final payload = json()();
  late final preferences = json().map(const PreferencesConverter())();
  late final code = text().map(const UserCodeConverter())();
  late final optionalCode = text().map(const UserCodeConverter()).nullable()();
}

@RivetEnum(name: 'workStatus', schema: 'fbr120')
enum WorkStatus {
  @RivetEnumValue(name: 'zeta')
  queued,
  @RivetEnumValue(name: 'alpha')
  complete,
}

final class WorkState {
  const WorkState(this.value);

  final WorkStatus value;
}

final class WorkStateConverter implements RivetTypeConverter<WorkState, WorkStatus> {
  const WorkStateConverter();

  @override
  WorkState fromSql(WorkStatus value) => WorkState(value);

  @override
  WorkStatus toSql(WorkState value) => value.value;
}

@RivetTable(schema: 'fbr120')
final class EnumValues extends RivetTableDefinition<EnumValues> {
  static const db = _$EnumValuesDB();

  late final status = enumText<WorkStatus>()();
  late final optionalStatus = enumText<WorkStatus>().nullable()();
  late final nullableStatuses = enumText<WorkStatus>().nullable().array()();
  late final optionalStatuses = enumText<WorkStatus>().array().nullable()();
  late final optionalNullableStatuses = enumText<WorkStatus>().nullable().array().nullable()();
  late final mappedStatus = enumText<WorkStatus>().map(const WorkStateConverter())();
}

@RivetTable(schema: 'fbr121')
final class VectorValues extends RivetTableDefinition<VectorValues> {
  static const db = _$VectorValuesDB();

  late final embedding = vector(dimensions: 3)();
  late final optionalEmbedding = vector(dimensions: 3).nullable()();
}

@RivetTable(schema: 'fbr122')
final class ArrayValues extends RivetTableDefinition<ArrayValues> {
  static const db = _$ArrayValuesDB();

  late final ints = integer().array()();
  late final nullableInts = integer().nullable().array()();
  late final optionalInts = integer().array().nullable()();
  late final optionalNullableInts = integer().nullable().array().nullable()();
  late final jsonValues = json().nullable().array()();
  late final vectors = vector(dimensions: 3).array()();
  late final statuses = enumText<WorkStatus>().array()();
  late final codes = text().map(const UserCodeConverter()).nullable().array()();
}

@RivetTable(schema: 'fbr122')
final class MalformedArrays extends RivetTableDefinition<MalformedArrays> {
  static const db = _$MalformedArraysDB();

  late final ints = integer().array()();
}

@RivetTable(schema: 'metadata')
final class MetadataColumns extends RivetTableDefinition<MetadataColumns> {
  static const db = _$MetadataColumnsDB();

  late final count = integer().defaultSql('1').defaultValue(() => 2).nullable()();
  late final payload = json().defaultValue(() => JsonValue.from(const {}))();
  late final embedding = vector(
    dimensions: 3,
  ).onUpdate(() => Float32List.fromList([1, 2, 3]))();
  late final values = integer().array().defaultValue(() => [1])();
  late final code = chronoID(prefix: 'code')
      .map(const UserCodeConverter())
      .defaultSql("'code_default'")
      .defaultValue(() => const UserCode('code_generated'))
      .onUpdate(() => const UserCode('code_updated'))();
  late final _constraints = [check('positive', count.equals(1))];
  late final _indexes = [
    index('partial').where(count.equals(1)).on([count]),
  ];
}

@RivetTable(schema: 'metadata')
final class TextTargets extends RivetTableDefinition<TextTargets> {
  static const db = _$TextTargetsDB();

  late final value = text()();
}

@RivetTable(schema: 'metadata')
final class InvalidReferences extends RivetTableDefinition<InvalidReferences> {
  static const db = _$InvalidReferencesDB();

  late final value = integer().references<TextTargets>((target) => target.value)();
}

@RivetTable(schema: 'metadata')
final class ParameterNames extends RivetTableDefinition<ParameterNames> {
  static const db = _$ParameterNamesDB();

  late final value = text(name: 'a@value')();
}

@RivetDatabase(
  name: 'rivet_test',
  tables: [
    UserProfiles,
    Posts,
    ScalarValues,
    EnumValues,
    VectorValues,
    ArrayValues,
    MalformedArrays,
    MetadataColumns,
    ParameterNames,
  ],
)
final class RivetTestDatabase extends _$RivetTestDatabase {}
