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

/// Generated row returned by reads from 'codec.vectorValues'.
final class VectorValuesRow {
  /// Creates a row from decoded column and relation values.
  const VectorValuesRow({
    required this.embedding,
    required this.optionalEmbedding,
  });

  /// Value read from `embedding`.
  final Float32List embedding;

  /// Value read from `optionalEmbedding`.
  final Float32List? optionalEmbedding;
}

/// Generated values accepted by mutations of 'codec.vectorValues'.
final class VectorValuesCompanion implements VoxelCompanion<VectorValues> {
  const VectorValuesCompanion._({
    required this.embedding,
    required this.optionalEmbedding,
  });

  /// Creates values for an insert, leaving defaulted columns absent.
  factory VectorValuesCompanion.insert({
    required VoxelValue<VectorValues, Float32List, Float32List> embedding,
    VoxelValue<VectorValues, Float32List?, Float32List?> optionalEmbedding =
        const VoxelValue.absent(),
  }) => VectorValuesCompanion._(
    embedding: embedding,
    optionalEmbedding: optionalEmbedding,
  );

  /// Creates values for an update, leaving untouched columns absent.
  factory VectorValuesCompanion.update({
    VoxelValue<VectorValues, Float32List, Float32List> embedding =
        const VoxelValue.absent(),
    VoxelValue<VectorValues, Float32List?, Float32List?> optionalEmbedding =
        const VoxelValue.absent(),
  }) => VectorValuesCompanion._(
    embedding: embedding,
    optionalEmbedding: optionalEmbedding,
  );

  /// Mutation value for `embedding`.
  final VoxelValue<VectorValues, Float32List, Float32List> embedding;

  /// Mutation value for `optionalEmbedding`.
  final VoxelValue<VectorValues, Float32List?, Float32List?> optionalEmbedding;

  /// The generated column assignments in declaration order.
  @override
  List<VoxelAssignment<VectorValues>> operator [](VoxelCompanionKey key) => [
    VoxelAssignment('embedding', embedding),
    VoxelAssignment('optionalEmbedding', optionalEmbedding),
  ];
}

final class _$VectorValuesDB
    extends VoxelTableAccessor<VectorValues, VectorValuesRow> {
  const _$VectorValuesDB();

  @override
  VoxelTableSchema<VectorValues, VectorValuesRow> buildSchema() {
    VectorValues createDefinition() {
      final definition = VectorValues();

      return definition;
    }

    final definition = createDefinition();
    return VoxelTableSchema<VectorValues, VectorValuesRow>(
      schemaName: 'codec',
      tableName: 'vectorValues',
      definition: definition,
      definitionType: VectorValues,
      rowType: VectorValuesRow,
      columns: [
        definition.embedding as VoxelColumn<Object?>,
        definition.optionalEmbedding as VoxelColumn<Object?>,
      ],
      columnNames: ['embedding', 'optionalEmbedding'],
      createDefinition: createDefinition,
      columnsFor: (definition) => [
        definition.embedding as VoxelColumn<Object?>,
        definition.optionalEmbedding as VoxelColumn<Object?>,
      ],
      decode: (values, sqlNulls) => VectorValuesRow(
        embedding: definition.embedding.decodeValue(
          values[0],
          isSqlNull: sqlNulls[0],
        ),
        optionalEmbedding: definition.optionalEmbedding.decodeValue(
          values[1],
          isSqlNull: sqlNulls[1],
        ),
      ),
    );
  }
}

/// Generated row returned by reads from 'codec.arrayValues'.
final class ArrayValuesRow {
  /// Creates a row from decoded column and relation values.
  const ArrayValuesRow({
    required this.texts,
    required this.nullableElements,
    required this.nullableArray,
    required this.nullableElementsAndArray,
    required this.integers,
    required this.reals,
    required this.booleans,
    required this.timestamps,
    required this.jsonValues,
    required this.nullableJsonValues,
    required this.statuses,
    required this.vectors,
    required this.codes,
    required this.nullableCodes,
    required this.counts,
    required this.preferencesList,
  });

  /// Value read from `texts`.
  final List<String> texts;

  /// Value read from `nullableElements`.
  final List<String?> nullableElements;

  /// Value read from `nullableArray`.
  final List<String>? nullableArray;

  /// Value read from `nullableElementsAndArray`.
  final List<String?>? nullableElementsAndArray;

  /// Value read from `integers`.
  final List<int> integers;

  /// Value read from `reals`.
  final List<double> reals;

  /// Value read from `booleans`.
  final List<bool> booleans;

  /// Value read from `timestamps`.
  final List<DateTime> timestamps;

  /// Value read from `jsonValues`.
  final List<JsonValue> jsonValues;

  /// Value read from `nullableJsonValues`.
  final List<JsonValue?> nullableJsonValues;

  /// Value read from `statuses`.
  final List<schema.PostStatus> statuses;

  /// Value read from `vectors`.
  final List<Float32List> vectors;

  /// Value read from `codes`.
  final List<UserCode> codes;

  /// Value read from `nullableCodes`.
  final List<UserCode?> nullableCodes;

  /// Value read from `counts`.
  final List<CountValue> counts;

  /// Value read from `preferencesList`.
  final List<Preferences> preferencesList;
}

/// Generated values accepted by mutations of 'codec.arrayValues'.
final class ArrayValuesCompanion implements VoxelCompanion<ArrayValues> {
  const ArrayValuesCompanion._({
    required this.texts,
    required this.nullableElements,
    required this.nullableArray,
    required this.nullableElementsAndArray,
    required this.integers,
    required this.reals,
    required this.booleans,
    required this.timestamps,
    required this.jsonValues,
    required this.nullableJsonValues,
    required this.statuses,
    required this.vectors,
    required this.codes,
    required this.nullableCodes,
    required this.counts,
    required this.preferencesList,
  });

  /// Creates values for an insert, leaving defaulted columns absent.
  factory ArrayValuesCompanion.insert({
    required VoxelValue<ArrayValues, List<String>, List<String>> texts,
    required VoxelValue<ArrayValues, List<String?>, List<String?>>
    nullableElements,
    required VoxelValue<ArrayValues, List<int>, List<int>> integers,
    required VoxelValue<ArrayValues, List<double>, List<double>> reals,
    required VoxelValue<ArrayValues, List<bool>, List<bool>> booleans,
    required VoxelValue<ArrayValues, List<DateTime>, List<DateTime>> timestamps,
    required VoxelValue<ArrayValues, List<JsonValue>, List<JsonValue>>
    jsonValues,
    required VoxelValue<ArrayValues, List<JsonValue?>, List<JsonValue?>>
    nullableJsonValues,
    required VoxelValue<ArrayValues, List<Float32List>, List<Float32List>>
    vectors,
    required VoxelValue<ArrayValues, List<UserCode>, List<String>> codes,
    required VoxelValue<ArrayValues, List<UserCode?>, List<String?>>
    nullableCodes,
    required VoxelValue<ArrayValues, List<CountValue>, List<int>> counts,
    required VoxelValue<ArrayValues, List<Preferences>, List<JsonValue>>
    preferencesList,
    VoxelValue<ArrayValues, List<String>?, List<String>?> nullableArray =
        const VoxelValue.absent(),
    VoxelValue<ArrayValues, List<String?>?, List<String?>?>
        nullableElementsAndArray =
        const VoxelValue.absent(),
    VoxelValue<ArrayValues, List<schema.PostStatus>, List<schema.PostStatus>>
        statuses =
        const VoxelValue.absent(),
  }) => ArrayValuesCompanion._(
    texts: texts,
    nullableElements: nullableElements,
    nullableArray: nullableArray,
    nullableElementsAndArray: nullableElementsAndArray,
    integers: integers,
    reals: reals,
    booleans: booleans,
    timestamps: timestamps,
    jsonValues: jsonValues,
    nullableJsonValues: nullableJsonValues,
    statuses: statuses,
    vectors: vectors,
    codes: codes,
    nullableCodes: nullableCodes,
    counts: counts,
    preferencesList: preferencesList,
  );

  /// Creates values for an update, leaving untouched columns absent.
  factory ArrayValuesCompanion.update({
    VoxelValue<ArrayValues, List<String>, List<String>> texts =
        const VoxelValue.absent(),
    VoxelValue<ArrayValues, List<String?>, List<String?>> nullableElements =
        const VoxelValue.absent(),
    VoxelValue<ArrayValues, List<String>?, List<String>?> nullableArray =
        const VoxelValue.absent(),
    VoxelValue<ArrayValues, List<String?>?, List<String?>?>
        nullableElementsAndArray =
        const VoxelValue.absent(),
    VoxelValue<ArrayValues, List<int>, List<int>> integers =
        const VoxelValue.absent(),
    VoxelValue<ArrayValues, List<double>, List<double>> reals =
        const VoxelValue.absent(),
    VoxelValue<ArrayValues, List<bool>, List<bool>> booleans =
        const VoxelValue.absent(),
    VoxelValue<ArrayValues, List<DateTime>, List<DateTime>> timestamps =
        const VoxelValue.absent(),
    VoxelValue<ArrayValues, List<JsonValue>, List<JsonValue>> jsonValues =
        const VoxelValue.absent(),
    VoxelValue<ArrayValues, List<JsonValue?>, List<JsonValue?>>
        nullableJsonValues =
        const VoxelValue.absent(),
    VoxelValue<ArrayValues, List<schema.PostStatus>, List<schema.PostStatus>>
        statuses =
        const VoxelValue.absent(),
    VoxelValue<ArrayValues, List<Float32List>, List<Float32List>> vectors =
        const VoxelValue.absent(),
    VoxelValue<ArrayValues, List<UserCode>, List<String>> codes =
        const VoxelValue.absent(),
    VoxelValue<ArrayValues, List<UserCode?>, List<String?>> nullableCodes =
        const VoxelValue.absent(),
    VoxelValue<ArrayValues, List<CountValue>, List<int>> counts =
        const VoxelValue.absent(),
    VoxelValue<ArrayValues, List<Preferences>, List<JsonValue>>
        preferencesList =
        const VoxelValue.absent(),
  }) => ArrayValuesCompanion._(
    texts: texts,
    nullableElements: nullableElements,
    nullableArray: nullableArray,
    nullableElementsAndArray: nullableElementsAndArray,
    integers: integers,
    reals: reals,
    booleans: booleans,
    timestamps: timestamps,
    jsonValues: jsonValues,
    nullableJsonValues: nullableJsonValues,
    statuses: statuses,
    vectors: vectors,
    codes: codes,
    nullableCodes: nullableCodes,
    counts: counts,
    preferencesList: preferencesList,
  );

  /// Mutation value for `texts`.
  final VoxelValue<ArrayValues, List<String>, List<String>> texts;

  /// Mutation value for `nullableElements`.
  final VoxelValue<ArrayValues, List<String?>, List<String?>> nullableElements;

  /// Mutation value for `nullableArray`.
  final VoxelValue<ArrayValues, List<String>?, List<String>?> nullableArray;

  /// Mutation value for `nullableElementsAndArray`.
  final VoxelValue<ArrayValues, List<String?>?, List<String?>?>
  nullableElementsAndArray;

  /// Mutation value for `integers`.
  final VoxelValue<ArrayValues, List<int>, List<int>> integers;

  /// Mutation value for `reals`.
  final VoxelValue<ArrayValues, List<double>, List<double>> reals;

  /// Mutation value for `booleans`.
  final VoxelValue<ArrayValues, List<bool>, List<bool>> booleans;

  /// Mutation value for `timestamps`.
  final VoxelValue<ArrayValues, List<DateTime>, List<DateTime>> timestamps;

  /// Mutation value for `jsonValues`.
  final VoxelValue<ArrayValues, List<JsonValue>, List<JsonValue>> jsonValues;

  /// Mutation value for `nullableJsonValues`.
  final VoxelValue<ArrayValues, List<JsonValue?>, List<JsonValue?>>
  nullableJsonValues;

  /// Mutation value for `statuses`.
  final VoxelValue<
    ArrayValues,
    List<schema.PostStatus>,
    List<schema.PostStatus>
  >
  statuses;

  /// Mutation value for `vectors`.
  final VoxelValue<ArrayValues, List<Float32List>, List<Float32List>> vectors;

  /// Mutation value for `codes`.
  final VoxelValue<ArrayValues, List<UserCode>, List<String>> codes;

  /// Mutation value for `nullableCodes`.
  final VoxelValue<ArrayValues, List<UserCode?>, List<String?>> nullableCodes;

  /// Mutation value for `counts`.
  final VoxelValue<ArrayValues, List<CountValue>, List<int>> counts;

  /// Mutation value for `preferencesList`.
  final VoxelValue<ArrayValues, List<Preferences>, List<JsonValue>>
  preferencesList;

  /// The generated column assignments in declaration order.
  @override
  List<VoxelAssignment<ArrayValues>> operator [](VoxelCompanionKey key) => [
    VoxelAssignment('texts', texts),
    VoxelAssignment('nullableElements', nullableElements),
    VoxelAssignment('nullableArray', nullableArray),
    VoxelAssignment('nullableElementsAndArray', nullableElementsAndArray),
    VoxelAssignment('integers', integers),
    VoxelAssignment('reals', reals),
    VoxelAssignment('booleans', booleans),
    VoxelAssignment('timestamps', timestamps),
    VoxelAssignment('jsonValues', jsonValues),
    VoxelAssignment('nullableJsonValues', nullableJsonValues),
    VoxelAssignment('statuses', statuses),
    VoxelAssignment('vectors', vectors),
    VoxelAssignment('codes', codes),
    VoxelAssignment('nullableCodes', nullableCodes),
    VoxelAssignment('counts', counts),
    VoxelAssignment('preferencesList', preferencesList),
  ];
}

final class _$ArrayValuesDB
    extends VoxelTableAccessor<ArrayValues, ArrayValuesRow> {
  const _$ArrayValuesDB();

  @override
  VoxelTableSchema<ArrayValues, ArrayValuesRow> buildSchema() {
    ArrayValues createDefinition() {
      final definition = ArrayValues();
      definition.statuses.configureEnum(schema.PostStatusVoxelEnum.codec);
      return definition;
    }

    final definition = createDefinition();
    return VoxelTableSchema<ArrayValues, ArrayValuesRow>(
      schemaName: 'codec',
      tableName: 'arrayValues',
      definition: definition,
      definitionType: ArrayValues,
      rowType: ArrayValuesRow,
      columns: [
        definition.texts as VoxelColumn<Object?>,
        definition.nullableElements as VoxelColumn<Object?>,
        definition.nullableArray as VoxelColumn<Object?>,
        definition.nullableElementsAndArray as VoxelColumn<Object?>,
        definition.integers as VoxelColumn<Object?>,
        definition.reals as VoxelColumn<Object?>,
        definition.booleans as VoxelColumn<Object?>,
        definition.timestamps as VoxelColumn<Object?>,
        definition.jsonValues as VoxelColumn<Object?>,
        definition.nullableJsonValues as VoxelColumn<Object?>,
        definition.statuses as VoxelColumn<Object?>,
        definition.vectors as VoxelColumn<Object?>,
        definition.codes as VoxelColumn<Object?>,
        definition.nullableCodes as VoxelColumn<Object?>,
        definition.counts as VoxelColumn<Object?>,
        definition.preferencesList as VoxelColumn<Object?>,
      ],
      columnNames: [
        'texts',
        'nullableElements',
        'nullableArray',
        'nullableElementsAndArray',
        'integers',
        'reals',
        'booleans',
        'timestamps',
        'jsonValues',
        'nullableJsonValues',
        'statuses',
        'vectors',
        'codes',
        'nullableCodes',
        'counts',
        'preferencesList',
      ],
      createDefinition: createDefinition,
      columnsFor: (definition) => [
        definition.texts as VoxelColumn<Object?>,
        definition.nullableElements as VoxelColumn<Object?>,
        definition.nullableArray as VoxelColumn<Object?>,
        definition.nullableElementsAndArray as VoxelColumn<Object?>,
        definition.integers as VoxelColumn<Object?>,
        definition.reals as VoxelColumn<Object?>,
        definition.booleans as VoxelColumn<Object?>,
        definition.timestamps as VoxelColumn<Object?>,
        definition.jsonValues as VoxelColumn<Object?>,
        definition.nullableJsonValues as VoxelColumn<Object?>,
        definition.statuses as VoxelColumn<Object?>,
        definition.vectors as VoxelColumn<Object?>,
        definition.codes as VoxelColumn<Object?>,
        definition.nullableCodes as VoxelColumn<Object?>,
        definition.counts as VoxelColumn<Object?>,
        definition.preferencesList as VoxelColumn<Object?>,
      ],
      decode: (values, sqlNulls) => ArrayValuesRow(
        texts: definition.texts.decodeValue(values[0], isSqlNull: sqlNulls[0]),
        nullableElements: definition.nullableElements.decodeValue(
          values[1],
          isSqlNull: sqlNulls[1],
        ),
        nullableArray: definition.nullableArray.decodeValue(
          values[2],
          isSqlNull: sqlNulls[2],
        ),
        nullableElementsAndArray: definition.nullableElementsAndArray
            .decodeValue(values[3], isSqlNull: sqlNulls[3]),
        integers: definition.integers.decodeValue(
          values[4],
          isSqlNull: sqlNulls[4],
        ),
        reals: definition.reals.decodeValue(values[5], isSqlNull: sqlNulls[5]),
        booleans: definition.booleans.decodeValue(
          values[6],
          isSqlNull: sqlNulls[6],
        ),
        timestamps: definition.timestamps.decodeValue(
          values[7],
          isSqlNull: sqlNulls[7],
        ),
        jsonValues: definition.jsonValues.decodeValue(
          values[8],
          isSqlNull: sqlNulls[8],
        ),
        nullableJsonValues: definition.nullableJsonValues.decodeValue(
          values[9],
          isSqlNull: sqlNulls[9],
        ),
        statuses: definition.statuses.decodeValue(
          values[10],
          isSqlNull: sqlNulls[10],
        ),
        vectors: definition.vectors.decodeValue(
          values[11],
          isSqlNull: sqlNulls[11],
        ),
        codes: definition.codes.decodeValue(
          values[12],
          isSqlNull: sqlNulls[12],
        ),
        nullableCodes: definition.nullableCodes.decodeValue(
          values[13],
          isSqlNull: sqlNulls[13],
        ),
        counts: definition.counts.decodeValue(
          values[14],
          isSqlNull: sqlNulls[14],
        ),
        preferencesList: definition.preferencesList.decodeValue(
          values[15],
          isSqlNull: sqlNulls[15],
        ),
      ),
    );
  }
}
