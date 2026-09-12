// The declaration DSL relies on inferred field types for generated output.
// ignore_for_file: specify_nonobvious_property_types

import 'dart:typed_data';

import 'package:rivet/rivet.dart';

part 'generated_consumer.g.dart';

@RivetTable(schema: 'fbr116', name: 'userProfiles')
final class UserProfiles extends RivetTableDefinition<UserProfiles> {
  static const db = _$UserProfilesDB();

  late final displayName = text(name: 'displayName')();
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

@RivetTable(schema: 'fbr119')
final class ScalarValues extends RivetTableDefinition<ScalarValues> {
  static const db = _$ScalarValuesDB();

  late final id = chronoID(prefix: 'usr')();
  late final count = integer()();
  late final score = real()();
  late final active = boolean()();
  late final createdAt = dateTime()();
  late final payload = json()();
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

@RivetTable(schema: 'fbr120')
final class EnumValues extends RivetTableDefinition<EnumValues> {
  static const db = _$EnumValuesDB();

  late final status = enumText<WorkStatus>()();
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

@RivetDatabase(
  name: 'rivet_test',
  tables: [
    UserProfiles,
    Posts,
    ScalarValues,
    EnumValues,
    VectorValues,
    ArrayValues,
  ],
)
final class RivetTestDatabase extends _$RivetTestDatabase {}
