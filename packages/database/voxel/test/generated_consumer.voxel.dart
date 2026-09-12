// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

part of 'generated_consumer.dart';

// **************************************************************************
// VoxelTableGenerator
// **************************************************************************

/// Generated row returned by reads from 'main.users'.
final class User {
  /// Creates a row from decoded column and relation values.
  const User({
    required this.id,
    required this.displayName,
    required this.nickname,
  });

  /// Value read from `id`.
  final String id;

  /// Value read from `displayName`.
  final String displayName;

  /// Value read from `nickname`.
  final String? nickname;
}

/// Generated values accepted by mutations of 'main.users'.
final class UsersCompanion implements VoxelCompanion<Users> {
  const UsersCompanion._({
    required this.id,
    required this.displayName,
    required this.nickname,
  });

  /// Creates values for an insert, leaving defaulted columns absent.
  factory UsersCompanion.insert({
    required VoxelValue<Users, String, String> displayName,
    VoxelValue<Users, String, String> id = const VoxelValue.absent(),
    VoxelValue<Users, String?, String?> nickname = const VoxelValue.absent(),
  }) => UsersCompanion._(id: id, displayName: displayName, nickname: nickname);

  /// Creates values for an update, leaving untouched columns absent.
  factory UsersCompanion.update({
    VoxelValue<Users, String, String> id = const VoxelValue.absent(),
    VoxelValue<Users, String, String> displayName = const VoxelValue.absent(),
    VoxelValue<Users, String?, String?> nickname = const VoxelValue.absent(),
  }) => UsersCompanion._(id: id, displayName: displayName, nickname: nickname);

  /// Mutation value for `id`.
  final VoxelValue<Users, String, String> id;

  /// Mutation value for `displayName`.
  final VoxelValue<Users, String, String> displayName;

  /// Mutation value for `nickname`.
  final VoxelValue<Users, String?, String?> nickname;

  /// The generated column assignments in declaration order.
  @override
  List<VoxelAssignment<Users>> operator [](VoxelCompanionKey key) => [
    VoxelAssignment('id', id),
    VoxelAssignment('displayName', displayName),
    VoxelAssignment('nickname', nickname),
  ];
}

final class _$UsersDB extends VoxelTableAccessor<Users, User> {
  const _$UsersDB();

  @override
  VoxelTableSchema<Users, User> buildSchema() {
    Users createDefinition() {
      final definition = Users();

      return definition;
    }

    final definition = createDefinition();
    return VoxelTableSchema<Users, User>(
      schemaName: 'main',
      tableName: 'users',
      renamedFrom: 'people',
      definition: definition,
      definitionType: Users,
      rowType: User,
      columns: [
        definition.id as VoxelColumn<Object?>,
        definition.displayName as VoxelColumn<Object?>,
        definition.nickname as VoxelColumn<Object?>,
      ],
      columnNames: ['id', 'displayName', 'nickname'],
      createDefinition: createDefinition,
      columnsFor: (definition) => [
        definition.id as VoxelColumn<Object?>,
        definition.displayName as VoxelColumn<Object?>,
        definition.nickname as VoxelColumn<Object?>,
      ],
      decode: (values, sqlNulls) => User(
        id: definition.id.decodeValue(values[0], isSqlNull: sqlNulls[0]),
        displayName: definition.displayName.decodeValue(
          values[1],
          isSqlNull: sqlNulls[1],
        ),
        nickname: definition.nickname.decodeValue(
          values[2],
          isSqlNull: sqlNulls[2],
        ),
      ),
    );
  }
}

/// Generated row returned by reads from 'other.externalTargets'.
final class ExternalTargetsRow {
  /// Creates a row from decoded column and relation values.
  const ExternalTargetsRow({required this.id});

  /// Value read from `id`.
  final String id;
}

/// Generated values accepted by mutations of 'other.externalTargets'.
final class ExternalTargetsCompanion
    implements VoxelCompanion<ExternalTargets> {
  const ExternalTargetsCompanion._({required this.id});

  /// Creates values for an insert, leaving defaulted columns absent.
  factory ExternalTargetsCompanion.insert({
    required VoxelValue<ExternalTargets, String, String> id,
  }) => ExternalTargetsCompanion._(id: id);

  /// Creates values for an update, leaving untouched columns absent.
  factory ExternalTargetsCompanion.update({
    VoxelValue<ExternalTargets, String, String> id = const VoxelValue.absent(),
  }) => ExternalTargetsCompanion._(id: id);

  /// Mutation value for `id`.
  final VoxelValue<ExternalTargets, String, String> id;

  /// The generated column assignments in declaration order.
  @override
  List<VoxelAssignment<ExternalTargets>> operator [](VoxelCompanionKey key) => [
    VoxelAssignment('id', id),
  ];
}

final class _$ExternalTargetsDB
    extends VoxelTableAccessor<ExternalTargets, ExternalTargetsRow> {
  const _$ExternalTargetsDB();

  @override
  VoxelTableSchema<ExternalTargets, ExternalTargetsRow> buildSchema() {
    ExternalTargets createDefinition() {
      final definition = ExternalTargets();

      return definition;
    }

    final definition = createDefinition();
    return VoxelTableSchema<ExternalTargets, ExternalTargetsRow>(
      schemaName: 'other',
      tableName: 'externalTargets',
      definition: definition,
      definitionType: ExternalTargets,
      rowType: ExternalTargetsRow,
      columns: [definition.id as VoxelColumn<Object?>],
      columnNames: ['id'],
      createDefinition: createDefinition,
      columnsFor: (definition) => [definition.id as VoxelColumn<Object?>],
      decode: (values, sqlNulls) => ExternalTargetsRow(
        id: definition.id.decodeValue(values[0], isSqlNull: sqlNulls[0]),
      ),
    );
  }
}

/// Generated row returned by reads from 'main.crossSchemaSources'.
final class CrossSchemaSourcesRow {
  /// Creates a row from decoded column and relation values.
  const CrossSchemaSourcesRow({required this.targetID});

  /// Value read from `targetID`.
  final String targetID;
}

/// Generated values accepted by mutations of 'main.crossSchemaSources'.
final class CrossSchemaSourcesCompanion
    implements VoxelCompanion<CrossSchemaSources> {
  const CrossSchemaSourcesCompanion._({required this.targetID});

  /// Creates values for an insert, leaving defaulted columns absent.
  factory CrossSchemaSourcesCompanion.insert({
    required VoxelValue<CrossSchemaSources, String, String> targetID,
  }) => CrossSchemaSourcesCompanion._(targetID: targetID);

  /// Creates values for an update, leaving untouched columns absent.
  factory CrossSchemaSourcesCompanion.update({
    VoxelValue<CrossSchemaSources, String, String> targetID =
        const VoxelValue.absent(),
  }) => CrossSchemaSourcesCompanion._(targetID: targetID);

  /// Mutation value for `targetID`.
  final VoxelValue<CrossSchemaSources, String, String> targetID;

  /// The generated column assignments in declaration order.
  @override
  List<VoxelAssignment<CrossSchemaSources>> operator [](
    VoxelCompanionKey key,
  ) => [VoxelAssignment('targetID', targetID)];
}

final class _$CrossSchemaSourcesDB
    extends VoxelTableAccessor<CrossSchemaSources, CrossSchemaSourcesRow> {
  const _$CrossSchemaSourcesDB();

  @override
  VoxelTableSchema<CrossSchemaSources, CrossSchemaSourcesRow> buildSchema() {
    CrossSchemaSources createDefinition() {
      final definition = CrossSchemaSources();

      return definition;
    }

    final definition = createDefinition();
    return VoxelTableSchema<CrossSchemaSources, CrossSchemaSourcesRow>(
      schemaName: 'main',
      tableName: 'crossSchemaSources',
      definition: definition,
      definitionType: CrossSchemaSources,
      rowType: CrossSchemaSourcesRow,
      columns: [definition.targetID as VoxelColumn<Object?>],
      columnNames: ['targetID'],
      createDefinition: createDefinition,
      columnsFor: (definition) => [definition.targetID as VoxelColumn<Object?>],
      decode: (values, sqlNulls) => CrossSchemaSourcesRow(
        targetID: definition.targetID.decodeValue(
          values[0],
          isSqlNull: sqlNulls[0],
        ),
      ),
    );
  }
}

/// Generated row returned by reads from 'codec.scalarValues'.
final class ScalarValuesRow {
  /// Creates a row from decoded column and relation values.
  const ScalarValuesRow({
    required this.count,
    required this.score,
    required this.active,
    required this.createdAt,
    required this.payload,
    required this.optionalPayload,
    required this.code,
    required this.optionalCode,
    required this.preferences,
  });

  /// Value read from `count`.
  final int count;

  /// Value read from `score`.
  final double score;

  /// Value read from `active`.
  final bool active;

  /// Value read from `createdAt`.
  final DateTime createdAt;

  /// Value read from `payload`.
  final JsonValue payload;

  /// Value read from `optionalPayload`.
  final JsonValue? optionalPayload;

  /// Value read from `code`.
  final UserCode code;

  /// Value read from `optionalCode`.
  final UserCode? optionalCode;

  /// Value read from `preferences`.
  final Preferences preferences;
}

/// Generated values accepted by mutations of 'codec.scalarValues'.
final class ScalarValuesCompanion implements VoxelCompanion<ScalarValues> {
  const ScalarValuesCompanion._({
    required this.count,
    required this.score,
    required this.active,
    required this.createdAt,
    required this.payload,
    required this.optionalPayload,
    required this.code,
    required this.optionalCode,
    required this.preferences,
  });

  /// Creates values for an insert, leaving defaulted columns absent.
  factory ScalarValuesCompanion.insert({
    required VoxelValue<ScalarValues, int, int> count,
    required VoxelValue<ScalarValues, double, double> score,
    required VoxelValue<ScalarValues, bool, bool> active,
    required VoxelValue<ScalarValues, DateTime, DateTime> createdAt,
    required VoxelValue<ScalarValues, JsonValue, JsonValue> payload,
    required VoxelValue<ScalarValues, UserCode, String> code,
    required VoxelValue<ScalarValues, Preferences, JsonValue> preferences,
    VoxelValue<ScalarValues, JsonValue?, JsonValue?> optionalPayload =
        const VoxelValue.absent(),
    VoxelValue<ScalarValues, UserCode?, String?> optionalCode =
        const VoxelValue.absent(),
  }) => ScalarValuesCompanion._(
    count: count,
    score: score,
    active: active,
    createdAt: createdAt,
    payload: payload,
    optionalPayload: optionalPayload,
    code: code,
    optionalCode: optionalCode,
    preferences: preferences,
  );

  /// Creates values for an update, leaving untouched columns absent.
  factory ScalarValuesCompanion.update({
    VoxelValue<ScalarValues, int, int> count = const VoxelValue.absent(),
    VoxelValue<ScalarValues, double, double> score = const VoxelValue.absent(),
    VoxelValue<ScalarValues, bool, bool> active = const VoxelValue.absent(),
    VoxelValue<ScalarValues, DateTime, DateTime> createdAt =
        const VoxelValue.absent(),
    VoxelValue<ScalarValues, JsonValue, JsonValue> payload =
        const VoxelValue.absent(),
    VoxelValue<ScalarValues, JsonValue?, JsonValue?> optionalPayload =
        const VoxelValue.absent(),
    VoxelValue<ScalarValues, UserCode, String> code = const VoxelValue.absent(),
    VoxelValue<ScalarValues, UserCode?, String?> optionalCode =
        const VoxelValue.absent(),
    VoxelValue<ScalarValues, Preferences, JsonValue> preferences =
        const VoxelValue.absent(),
  }) => ScalarValuesCompanion._(
    count: count,
    score: score,
    active: active,
    createdAt: createdAt,
    payload: payload,
    optionalPayload: optionalPayload,
    code: code,
    optionalCode: optionalCode,
    preferences: preferences,
  );

  /// Mutation value for `count`.
  final VoxelValue<ScalarValues, int, int> count;

  /// Mutation value for `score`.
  final VoxelValue<ScalarValues, double, double> score;

  /// Mutation value for `active`.
  final VoxelValue<ScalarValues, bool, bool> active;

  /// Mutation value for `createdAt`.
  final VoxelValue<ScalarValues, DateTime, DateTime> createdAt;

  /// Mutation value for `payload`.
  final VoxelValue<ScalarValues, JsonValue, JsonValue> payload;

  /// Mutation value for `optionalPayload`.
  final VoxelValue<ScalarValues, JsonValue?, JsonValue?> optionalPayload;

  /// Mutation value for `code`.
  final VoxelValue<ScalarValues, UserCode, String> code;

  /// Mutation value for `optionalCode`.
  final VoxelValue<ScalarValues, UserCode?, String?> optionalCode;

  /// Mutation value for `preferences`.
  final VoxelValue<ScalarValues, Preferences, JsonValue> preferences;

  /// The generated column assignments in declaration order.
  @override
  List<VoxelAssignment<ScalarValues>> operator [](VoxelCompanionKey key) => [
    VoxelAssignment('count', count),
    VoxelAssignment('score', score),
    VoxelAssignment('active', active),
    VoxelAssignment('createdAt', createdAt),
    VoxelAssignment('payload', payload),
    VoxelAssignment('optionalPayload', optionalPayload),
    VoxelAssignment('code', code),
    VoxelAssignment('optionalCode', optionalCode),
    VoxelAssignment('preferences', preferences),
  ];
}

final class _$ScalarValuesDB
    extends VoxelTableAccessor<ScalarValues, ScalarValuesRow> {
  const _$ScalarValuesDB();

  @override
  VoxelTableSchema<ScalarValues, ScalarValuesRow> buildSchema() {
    ScalarValues createDefinition() {
      final definition = ScalarValues();

      return definition;
    }

    final definition = createDefinition();
    return VoxelTableSchema<ScalarValues, ScalarValuesRow>(
      schemaName: 'codec',
      tableName: 'scalarValues',
      definition: definition,
      definitionType: ScalarValues,
      rowType: ScalarValuesRow,
      columns: [
        definition.count as VoxelColumn<Object?>,
        definition.score as VoxelColumn<Object?>,
        definition.active as VoxelColumn<Object?>,
        definition.createdAt as VoxelColumn<Object?>,
        definition.payload as VoxelColumn<Object?>,
        definition.optionalPayload as VoxelColumn<Object?>,
        definition.code as VoxelColumn<Object?>,
        definition.optionalCode as VoxelColumn<Object?>,
        definition.preferences as VoxelColumn<Object?>,
      ],
      columnNames: [
        'count',
        'score',
        'active',
        'createdAt',
        'payload',
        'optionalPayload',
        'code',
        'optionalCode',
        'preferences',
      ],
      createDefinition: createDefinition,
      columnsFor: (definition) => [
        definition.count as VoxelColumn<Object?>,
        definition.score as VoxelColumn<Object?>,
        definition.active as VoxelColumn<Object?>,
        definition.createdAt as VoxelColumn<Object?>,
        definition.payload as VoxelColumn<Object?>,
        definition.optionalPayload as VoxelColumn<Object?>,
        definition.code as VoxelColumn<Object?>,
        definition.optionalCode as VoxelColumn<Object?>,
        definition.preferences as VoxelColumn<Object?>,
      ],
      decode: (values, sqlNulls) => ScalarValuesRow(
        count: definition.count.decodeValue(values[0], isSqlNull: sqlNulls[0]),
        score: definition.score.decodeValue(values[1], isSqlNull: sqlNulls[1]),
        active: definition.active.decodeValue(
          values[2],
          isSqlNull: sqlNulls[2],
        ),
        createdAt: definition.createdAt.decodeValue(
          values[3],
          isSqlNull: sqlNulls[3],
        ),
        payload: definition.payload.decodeValue(
          values[4],
          isSqlNull: sqlNulls[4],
        ),
        optionalPayload: definition.optionalPayload.decodeValue(
          values[5],
          isSqlNull: sqlNulls[5],
        ),
        code: definition.code.decodeValue(values[6], isSqlNull: sqlNulls[6]),
        optionalCode: definition.optionalCode.decodeValue(
          values[7],
          isSqlNull: sqlNulls[7],
        ),
        preferences: definition.preferences.decodeValue(
          values[8],
          isSqlNull: sqlNulls[8],
        ),
      ),
    );
  }
}
