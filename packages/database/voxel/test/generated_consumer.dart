// The declaration DSL relies on inferred field types for generated output.
// ignore_for_file: specify_nonobvious_property_types

import 'dart:typed_data';

import 'package:voxel/voxel.dart';
import 'package:voxel_fixture_schema/authors.dart' as schema;

part 'generated_consumer.voxel.dart';

@VoxelTable(name: 'users', renamedFrom: 'people', rowName: 'User')
final class Users extends VoxelTableDefinition<Users> {
  static const db = _$UsersDB();

  late final id = chronoID(prefix: 'usr').primaryKey()();
  late final displayName = text(name: 'displayName', renamedFrom: 'name')();
  late final nickname = text().nullable()();
}

@VoxelTable(schema: 'other')
final class ExternalTargets extends VoxelTableDefinition<ExternalTargets> {
  static const db = _$ExternalTargetsDB();

  late final id = text().primaryKey()();
}

@VoxelTable(schema: 'main')
final class CrossSchemaSources extends VoxelTableDefinition<CrossSchemaSources> {
  static const db = _$CrossSchemaSourcesDB();

  late final targetID = text().references<ExternalTargets>((target) => target.id)();
}

final class UserCode {
  const UserCode(this.value);

  final String value;
}

final class UserCodeConverter implements VoxelTypeConverter<UserCode, String> {
  const UserCodeConverter();

  @override
  UserCode fromSql(String value) {
    if (value == 'secret') throw FormatException('invalid domain value $value');
    return UserCode(value);
  }

  @override
  String toSql(UserCode value) {
    if (value.value == 'secret') throw FormatException('invalid domain value ${value.value}');
    return value.value;
  }
}

final class Preferences {
  const Preferences({required this.darkMode});

  final bool darkMode;
}

final class PreferencesConverter implements VoxelTypeConverter<Preferences, JsonValue> {
  const PreferencesConverter();

  @override
  Preferences fromSql(JsonValue value) {
    final data = value.toDart();
    if (data is! Map<String, Object?> || data['darkMode'] is! bool) {
      throw const FormatException('invalid preferences');
    }
    return Preferences(darkMode: data['darkMode']! as bool);
  }

  @override
  JsonValue toSql(Preferences value) => JsonValue.from({'darkMode': value.darkMode});
}

final class CountValue {
  const CountValue(this.value);

  final int value;
}

final class CountValueConverter implements VoxelTypeConverter<CountValue, int> {
  const CountValueConverter();

  @override
  CountValue fromSql(int value) => CountValue(value);

  @override
  int toSql(CountValue value) => value.value;
}

@VoxelTable(schema: 'codec')
final class ScalarValues extends VoxelTableDefinition<ScalarValues> {
  static const db = _$ScalarValuesDB();

  late final count = integer()();
  late final score = real()();
  late final active = boolean()();
  late final createdAt = dateTime()();
  late final payload = json()();
  late final optionalPayload = json().nullable()();
  late final code = text().map(const UserCodeConverter())();
  late final optionalCode = text().map(const UserCodeConverter()).nullable()();
  late final preferences = json().map(const PreferencesConverter())();
}

@VoxelTable(schema: 'codec')
final class VectorValues extends VoxelTableDefinition<VectorValues> {
  static const db = _$VectorValuesDB();

  late final embedding = vector(dimensions: 3)();
  late final optionalEmbedding = vector(dimensions: 3).nullable()();
}

@VoxelTable(schema: 'codec')
final class ArrayValues extends VoxelTableDefinition<ArrayValues> {
  static const db = _$ArrayValuesDB();

  late final texts = text().array()();
  late final nullableElements = text().nullable().array()();
  late final nullableArray = text().array().nullable()();
  late final nullableElementsAndArray = text().nullable().array().nullable()();
  late final integers = integer().array()();
  late final reals = real().array()();
  late final booleans = boolean().array()();
  late final timestamps = dateTime().array()();
  late final jsonValues = json().array()();
  late final nullableJsonValues = json().nullable().array()();
  late final VoxelColumn<List<schema.PostStatus>> statuses = enumText<schema.PostStatus>()
      .array()
      .defaultValue(() => [schema.PostStatus.draft])();
  late final vectors = vector(dimensions: 3).array()();
  late final codes = text().map(const UserCodeConverter()).array()();
  late final nullableCodes = text().map(const UserCodeConverter()).nullable().array()();
  late final counts = integer().map(const CountValueConverter()).array()();
  late final preferencesList = json().map(const PreferencesConverter()).array()();
}
