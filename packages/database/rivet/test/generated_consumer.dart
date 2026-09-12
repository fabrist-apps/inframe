// The declaration DSL relies on inferred field types for generated output.
// ignore_for_file: specify_nonobvious_property_types

import 'dart:typed_data';

import 'package:rivet/rivet.dart';

part 'generated_consumer.rivet.dart';

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

int mutationDefaultCalls = 0;
int mutationUpdateCalls = 0;
int mutationNullableCalls = 0;

DateTime mutationDefault() {
  mutationDefaultCalls++;
  return DateTime.utc(2026, 9, 12, 10, 11, mutationDefaultCalls);
}

DateTime mutationUpdate() {
  mutationUpdateCalls++;
  return DateTime.utc(2026, 9, 12, 11, 12, mutationUpdateCalls);
}

String? mutationNullableDefault() {
  mutationNullableCalls++;
  return null;
}

final class MutationCode {
  const MutationCode(this.value);

  final String value;
}

final class MutationCodeConverter implements RivetTypeConverter<MutationCode, String> {
  const MutationCodeConverter();

  @override
  MutationCode fromSql(String value) {
    if (!value.startsWith('code:')) {
      throw const FormatException('expected a code-prefixed value');
    }
    return MutationCode(value.substring(5));
  }

  @override
  String toSql(MutationCode value) {
    mutationCodeEncodeCalls++;
    return 'code:${value.value}';
  }
}

@RivetEnum(schema: 'fbr139', name: 'mutationStatus')
enum MutationStatus {
  @RivetEnumValue(name: 'waiting')
  queued,
  @RivetEnumValue(name: 'finished')
  complete,
}

int mappedCodeDefaultCalls = 0;
int mutationCodeEncodeCalls = 0;
int enumDefaultCalls = 0;
int timestampDefaultCalls = 0;
int mappedArrayDefaultCalls = 0;

MutationCode mappedCodeDefault() {
  mappedCodeDefaultCalls++;
  return const MutationCode('default');
}

MutationStatus enumDefault() {
  enumDefaultCalls++;
  return MutationStatus.complete;
}

DateTime timestampDefault() {
  timestampDefaultCalls++;
  return DateTime.utc(1969, 12, 31, 23, 59, 59, 999, 999);
}

List<MutationCode?> mappedArrayDefault() {
  mappedArrayDefaultCalls++;
  return const [MutationCode('array-default'), null];
}

@RivetTable(schema: 'fbr139')
final class MutationCatalog extends RivetTableDefinition<MutationCatalog> {
  static const db = _$MutationCatalogDB();

  late final id = integer().primaryKey()();
  late final textValue = text()();
  late final count = integer()();
  late final score = real()();
  late final active = boolean()();
  late final createdAt = dateTime().defaultValue(timestampDefault)();
  late final payload = json()();
  late final nullablePayload = json().nullable()();
  late final preferences = json().map(const PreferencesConverter())();
  late final code = text().map(const MutationCodeConverter()).defaultValue(mappedCodeDefault)();
  late final optionalCode = text().map(const MutationCodeConverter()).nullable()();
  late final status = enumText<MutationStatus>().defaultValue(enumDefault)();
  late final statuses = enumText<MutationStatus>().array().defaultValue(
    () => [MutationStatus.queued, MutationStatus.complete],
  )();
  late final timestamps = dateTime().array()();
  late final nullableInts = integer().nullable().array()();
  late final optionalInts = integer().array().nullable()();
  late final jsonValues = json().nullable().array()();
  late final mappedCodes = text()
      .map(const MutationCodeConverter())
      .nullable()
      .array()
      .defaultValue(mappedArrayDefault)();
  late final embedding = vector(dimensions: 3)();
  late final embeddings = vector(dimensions: 3).array()();
}

@RivetTable(schema: 'fbr138')
final class MutationUsers extends RivetTableDefinition<MutationUsers> {
  static const db = _$MutationUsersDB();

  late final id = integer().primaryKey()();
  late final name = text()();
  late final nickname = text().nullable()();
  late final createdAt = dateTime()
      .defaultSql('CURRENT_TIMESTAMP')
      .defaultValue(mutationDefault)
      .onUpdate(mutationUpdate)();
  late final updatedAt = dateTime().onUpdate(mutationUpdate)();
  late final nullableDefault = text().nullable().defaultValue(mutationNullableDefault)();
  late final serverValue = integer().defaultSql('40 + 2')();
}

@RivetTable(schema: 'fbr138')
final class MutationParents extends RivetTableDefinition<MutationParents> {
  static const db = _$MutationParentsDB();

  late final id = integer().primaryKey()();
  late final name = text()();
  late final children = many<MutationChildren>(relation: (child) => child.parent)();
}

@RivetTable(schema: 'fbr138')
final class MutationChildren extends RivetTableDefinition<MutationChildren> {
  static const db = _$MutationChildrenDB();

  late final id = integer().primaryKey()();
  late final parentId = integer().references<MutationParents>((parent) => parent.id)();
  late final parent = one<MutationParents>(
    fields: [parentId],
    references: (parent) => [parent.id],
  )();
}

int updateTimestampCalls = 0;
int updateNullableCalls = 0;
int updateCodeCalls = 0;
int updateDefaultOnlyCalls = 0;

DateTime updateTimestamp() {
  updateTimestampCalls++;
  return DateTime.utc(2026, 9, 12, 12, 30, updateTimestampCalls);
}

String? updateNullable() {
  updateNullableCalls++;
  return null;
}

MutationCode updateCode() {
  updateCodeCalls++;
  return MutationCode('hook-$updateCodeCalls');
}

String updateDefaultOnly() {
  updateDefaultOnlyCalls++;
  return 'default-only';
}

@RivetTable(schema: 'fbr140')
final class MutationUpdateUsers extends RivetTableDefinition<MutationUpdateUsers> {
  static const db = _$MutationUpdateUsersDB();

  late final id = integer().primaryKey()();
  late final name = text()();
  late final age = integer()();
  late final updatedAt = dateTime().onUpdate(updateTimestamp)();
  late final nullableNote = text().nullable().onUpdate(updateNullable)();
  late final code = text().map(const MutationCodeConverter()).onUpdate(updateCode)();
  late final defaultOnly = text().defaultValue(updateDefaultOnly)();
  late final serverOnly = integer().defaultSql('42')();
  late final children = many<MutationUpdateChildren>(relation: (child) => child.user)();
}

@RivetTable(schema: 'fbr140')
final class MutationUpdateChildren extends RivetTableDefinition<MutationUpdateChildren> {
  static const db = _$MutationUpdateChildrenDB();

  late final id = integer().primaryKey()();
  late final userId = integer().references<MutationUpdateUsers>((user) => user.id)();
  late final user = one<MutationUpdateUsers>(
    fields: [userId],
    references: (user) => [user.id],
  )();
}

@RivetTable(schema: 'fbr141', name: 'delete Parents')
final class MutationDeleteParents extends RivetTableDefinition<MutationDeleteParents> {
  static const db = _$MutationDeleteParentsDB();

  late final id = integer().primaryKey()();
  late final label = text(name: 'display Name')();
  late final cascadeChildren = many<MutationCascadeChildren>(
    relation: (child) => child.parent,
  )();
  late final restrictChildren = many<MutationRestrictChildren>(
    relation: (child) => child.parent,
  )();
}

@RivetTable(schema: 'fbr141', name: 'cascade Children')
final class MutationCascadeChildren extends RivetTableDefinition<MutationCascadeChildren> {
  static const db = _$MutationCascadeChildrenDB();

  late final id = integer().primaryKey()();
  late final parentId = integer().references<MutationDeleteParents>(
    (parent) => parent.id,
    onDelete: RivetReferentialAction.cascade,
  )();
  late final parent = one<MutationDeleteParents>(
    fields: [parentId],
    references: (parent) => [parent.id],
  )();
}

@RivetTable(schema: 'fbr141', name: 'restrict Children')
final class MutationRestrictChildren extends RivetTableDefinition<MutationRestrictChildren> {
  static const db = _$MutationRestrictChildrenDB();

  late final id = integer().primaryKey()();
  late final parentId = integer().references<MutationDeleteParents>(
    (parent) => parent.id,
  )();
  late final parent = one<MutationDeleteParents>(
    fields: [parentId],
    references: (parent) => [parent.id],
  )();
}

int batchCreatedCalls = 0;

DateTime batchCreated() {
  batchCreatedCalls++;
  return DateTime.utc(2026, 9, 12, 14, 0, batchCreatedCalls);
}

@RivetTable(schema: 'fbr142')
final class MutationBatchParents extends RivetTableDefinition<MutationBatchParents> {
  static const db = _$MutationBatchParentsDB();

  late final id = integer().primaryKey()();
  late final name = text()();
  late final createdAt = dateTime().defaultValue(batchCreated)();
  late final nickname = text().nullable()();
  late final serverValue = integer().defaultSql('42')();
  late final children = many<MutationBatchChildren>(relation: (child) => child.parent)();
}

@RivetTable(schema: 'fbr142')
final class MutationBatchChildren extends RivetTableDefinition<MutationBatchChildren> {
  static const db = _$MutationBatchChildrenDB();

  late final id = integer().primaryKey()();
  late final parentId = integer().references<MutationBatchParents>((parent) => parent.id)();
  late final parent = one<MutationBatchParents>(
    fields: [parentId],
    references: (parent) => [parent.id],
  )();
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
    MutationUsers,
    MutationParents,
    MutationChildren,
    MutationCatalog,
    MutationUpdateUsers,
    MutationUpdateChildren,
    MutationDeleteParents,
    MutationCascadeChildren,
    MutationRestrictChildren,
    MutationBatchParents,
    MutationBatchChildren,
  ],
)
final class RivetTestDatabase extends _$RivetTestDatabase {}
