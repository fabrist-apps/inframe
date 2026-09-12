// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

part of 'generated_consumer.dart';

// **************************************************************************
// RivetTableGenerator
// **************************************************************************

/// Generated row returned by reads from 'fbr116.userProfiles'.
final class UserProfilesRow {
  /// Creates a row from decoded column and relation values.
  const UserProfilesRow({
    required this.displayName,
    this.posts = const Relation.unloaded(),
  });

  /// Value read from `displayName`.
  final String displayName;

  /// Loaded or unloaded `posts` relation.
  final Relation<List<PostsRow>> posts;
}

/// Generated values accepted by mutations of 'fbr116.userProfiles'.
final class UserProfilesCompanion implements RivetCompanion<UserProfiles> {
  const UserProfilesCompanion._({required this.displayName});

  /// Creates values for an insert, leaving defaulted columns absent.
  factory UserProfilesCompanion.insert({
    required RivetValue<UserProfiles, String, String> displayName,
  }) => UserProfilesCompanion._(displayName: displayName);

  /// Mutation value for `displayName`.
  final RivetValue<UserProfiles, String, String> displayName;

  /// The generated column assignments in declaration order.
  @override
  List<RivetAssignment<UserProfiles>> get assignments => [
    RivetAssignment('displayName', displayName),
  ];
}

final class _$UserProfilesDB
    extends RivetTableAccessor<UserProfiles, UserProfilesRow> {
  const _$UserProfilesDB();

  @override
  RivetTableSchema<UserProfiles, UserProfilesRow> buildSchema() {
    final definition = UserProfiles();

    return RivetTableSchema<UserProfiles, UserProfilesRow>(
      schemaName: 'fbr116',
      tableName: 'userProfiles',
      renamedFrom: 'profiles',
      definition: definition,
      columns: [definition.displayName as RivetColumn<Object?>],
      columnNames: ['displayName'],
      decode: (values, sqlNulls) => UserProfilesRow(
        displayName: definition.displayName.decodeValue(
          values[0],
          isSqlNull: sqlNulls[0],
        ),
      ),
      indexes: () => definition._indexes,
      constraints: () => definition._constraints,
      relations: {
        'posts': definition.posts as RivetRelationDescriptor<Object?>,
      },
    );
  }

  /// Creates a reusable insert plan.
  RivetInsert<UserProfiles, UserProfilesRow> insert(
    UserProfilesCompanion companion,
  ) => RivetInsert(buildSchema(), companion);
}

/// Generated row returned by reads from 'fbr116.posts'.
final class PostsRow {
  /// Creates a row from decoded column and relation values.
  const PostsRow({
    required this.authorName,
    this.author = const Relation.unloaded(),
  });

  /// Value read from `authorName`.
  final String authorName;

  /// Loaded or unloaded `author` relation.
  final Relation<UserProfilesRow?> author;
}

/// Generated values accepted by mutations of 'fbr116.posts'.
final class PostsCompanion implements RivetCompanion<Posts> {
  const PostsCompanion._({required this.authorName});

  /// Creates values for an insert, leaving defaulted columns absent.
  factory PostsCompanion.insert({
    required RivetValue<Posts, String, String> authorName,
  }) => PostsCompanion._(authorName: authorName);

  /// Mutation value for `authorName`.
  final RivetValue<Posts, String, String> authorName;

  /// The generated column assignments in declaration order.
  @override
  List<RivetAssignment<Posts>> get assignments => [
    RivetAssignment('authorName', authorName),
  ];
}

final class _$PostsDB extends RivetTableAccessor<Posts, PostsRow> {
  const _$PostsDB();

  @override
  RivetTableSchema<Posts, PostsRow> buildSchema() {
    final definition = Posts();

    return RivetTableSchema<Posts, PostsRow>(
      schemaName: 'fbr116',
      tableName: 'posts',
      definition: definition,
      columns: [definition.authorName as RivetColumn<Object?>],
      columnNames: ['authorName'],
      decode: (values, sqlNulls) => PostsRow(
        authorName: definition.authorName.decodeValue(
          values[0],
          isSqlNull: sqlNulls[0],
        ),
      ),
      relations: {
        'author': definition.author as RivetRelationDescriptor<Object?>,
      },
    );
  }

  /// Creates a reusable insert plan.
  RivetInsert<Posts, PostsRow> insert(PostsCompanion companion) =>
      RivetInsert(buildSchema(), companion);
}

/// Generated row returned by reads from 'fbr119.scalarValues'.
final class ScalarValuesRow {
  /// Creates a row from decoded column and relation values.
  const ScalarValuesRow({
    required this.id,
    required this.count,
    required this.score,
    required this.active,
    required this.createdAt,
    required this.payload,
    required this.preferences,
    required this.code,
    required this.optionalCode,
  });

  /// Value read from `id`.
  final String id;

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

  /// Value read from `preferences`.
  final Preferences preferences;

  /// Value read from `code`.
  final UserCode code;

  /// Value read from `optionalCode`.
  final UserCode? optionalCode;
}

/// Generated values accepted by mutations of 'fbr119.scalarValues'.
final class ScalarValuesCompanion implements RivetCompanion<ScalarValues> {
  const ScalarValuesCompanion._({
    required this.id,
    required this.count,
    required this.score,
    required this.active,
    required this.createdAt,
    required this.payload,
    required this.preferences,
    required this.code,
    required this.optionalCode,
  });

  /// Creates values for an insert, leaving defaulted columns absent.
  factory ScalarValuesCompanion.insert({
    required RivetValue<ScalarValues, int, int> count,
    required RivetValue<ScalarValues, double, double> score,
    required RivetValue<ScalarValues, bool, bool> active,
    required RivetValue<ScalarValues, DateTime, DateTime> createdAt,
    required RivetValue<ScalarValues, JsonValue, JsonValue> payload,
    required RivetValue<ScalarValues, Preferences, JsonValue> preferences,
    required RivetValue<ScalarValues, UserCode, String> code,
    RivetValue<ScalarValues, String, String> id = const RivetValue.absent(),
    RivetValue<ScalarValues, UserCode?, String?> optionalCode =
        const RivetValue.absent(),
  }) => ScalarValuesCompanion._(
    id: id,
    count: count,
    score: score,
    active: active,
    createdAt: createdAt,
    payload: payload,
    preferences: preferences,
    code: code,
    optionalCode: optionalCode,
  );

  /// Mutation value for `id`.
  final RivetValue<ScalarValues, String, String> id;

  /// Mutation value for `count`.
  final RivetValue<ScalarValues, int, int> count;

  /// Mutation value for `score`.
  final RivetValue<ScalarValues, double, double> score;

  /// Mutation value for `active`.
  final RivetValue<ScalarValues, bool, bool> active;

  /// Mutation value for `createdAt`.
  final RivetValue<ScalarValues, DateTime, DateTime> createdAt;

  /// Mutation value for `payload`.
  final RivetValue<ScalarValues, JsonValue, JsonValue> payload;

  /// Mutation value for `preferences`.
  final RivetValue<ScalarValues, Preferences, JsonValue> preferences;

  /// Mutation value for `code`.
  final RivetValue<ScalarValues, UserCode, String> code;

  /// Mutation value for `optionalCode`.
  final RivetValue<ScalarValues, UserCode?, String?> optionalCode;

  /// The generated column assignments in declaration order.
  @override
  List<RivetAssignment<ScalarValues>> get assignments => [
    RivetAssignment('id', id),
    RivetAssignment('count', count),
    RivetAssignment('score', score),
    RivetAssignment('active', active),
    RivetAssignment('createdAt', createdAt),
    RivetAssignment('payload', payload),
    RivetAssignment('preferences', preferences),
    RivetAssignment('code', code),
    RivetAssignment('optionalCode', optionalCode),
  ];
}

final class _$ScalarValuesDB
    extends RivetTableAccessor<ScalarValues, ScalarValuesRow> {
  const _$ScalarValuesDB();

  @override
  RivetTableSchema<ScalarValues, ScalarValuesRow> buildSchema() {
    final definition = ScalarValues();

    return RivetTableSchema<ScalarValues, ScalarValuesRow>(
      schemaName: 'fbr119',
      tableName: 'scalarValues',
      definition: definition,
      columns: [
        definition.id as RivetColumn<Object?>,
        definition.count as RivetColumn<Object?>,
        definition.score as RivetColumn<Object?>,
        definition.active as RivetColumn<Object?>,
        definition.createdAt as RivetColumn<Object?>,
        definition.payload as RivetColumn<Object?>,
        definition.preferences as RivetColumn<Object?>,
        definition.code as RivetColumn<Object?>,
        definition.optionalCode as RivetColumn<Object?>,
      ],
      columnNames: [
        'id',
        'count',
        'score',
        'active',
        'createdAt',
        'payload',
        'preferences',
        'code',
        'optionalCode',
      ],
      decode: (values, sqlNulls) => ScalarValuesRow(
        id: definition.id.decodeValue(values[0], isSqlNull: sqlNulls[0]),
        count: definition.count.decodeValue(values[1], isSqlNull: sqlNulls[1]),
        score: definition.score.decodeValue(values[2], isSqlNull: sqlNulls[2]),
        active: definition.active.decodeValue(
          values[3],
          isSqlNull: sqlNulls[3],
        ),
        createdAt: definition.createdAt.decodeValue(
          values[4],
          isSqlNull: sqlNulls[4],
        ),
        payload: definition.payload.decodeValue(
          values[5],
          isSqlNull: sqlNulls[5],
        ),
        preferences: definition.preferences.decodeValue(
          values[6],
          isSqlNull: sqlNulls[6],
        ),
        code: definition.code.decodeValue(values[7], isSqlNull: sqlNulls[7]),
        optionalCode: definition.optionalCode.decodeValue(
          values[8],
          isSqlNull: sqlNulls[8],
        ),
      ),
    );
  }

  /// Creates a reusable insert plan.
  RivetInsert<ScalarValues, ScalarValuesRow> insert(
    ScalarValuesCompanion companion,
  ) => RivetInsert(buildSchema(), companion);
}

/// Generated row returned by reads from 'fbr120.enumValues'.
final class EnumValuesRow {
  /// Creates a row from decoded column and relation values.
  const EnumValuesRow({
    required this.status,
    required this.optionalStatus,
    required this.nullableStatuses,
    required this.optionalStatuses,
    required this.optionalNullableStatuses,
    required this.mappedStatus,
  });

  /// Value read from `status`.
  final WorkStatus status;

  /// Value read from `optionalStatus`.
  final WorkStatus? optionalStatus;

  /// Value read from `nullableStatuses`.
  final List<WorkStatus?> nullableStatuses;

  /// Value read from `optionalStatuses`.
  final List<WorkStatus>? optionalStatuses;

  /// Value read from `optionalNullableStatuses`.
  final List<WorkStatus?>? optionalNullableStatuses;

  /// Value read from `mappedStatus`.
  final WorkState mappedStatus;
}

/// Generated values accepted by mutations of 'fbr120.enumValues'.
final class EnumValuesCompanion implements RivetCompanion<EnumValues> {
  const EnumValuesCompanion._({
    required this.status,
    required this.optionalStatus,
    required this.nullableStatuses,
    required this.optionalStatuses,
    required this.optionalNullableStatuses,
    required this.mappedStatus,
  });

  /// Creates values for an insert, leaving defaulted columns absent.
  factory EnumValuesCompanion.insert({
    required RivetValue<EnumValues, WorkStatus, WorkStatus> status,
    required RivetValue<EnumValues, List<WorkStatus?>, List<WorkStatus?>>
    nullableStatuses,
    required RivetValue<EnumValues, WorkState, WorkStatus> mappedStatus,
    RivetValue<EnumValues, WorkStatus?, WorkStatus?> optionalStatus =
        const RivetValue.absent(),
    RivetValue<EnumValues, List<WorkStatus>?, List<WorkStatus>?>
        optionalStatuses =
        const RivetValue.absent(),
    RivetValue<EnumValues, List<WorkStatus?>?, List<WorkStatus?>?>
        optionalNullableStatuses =
        const RivetValue.absent(),
  }) => EnumValuesCompanion._(
    status: status,
    optionalStatus: optionalStatus,
    nullableStatuses: nullableStatuses,
    optionalStatuses: optionalStatuses,
    optionalNullableStatuses: optionalNullableStatuses,
    mappedStatus: mappedStatus,
  );

  /// Mutation value for `status`.
  final RivetValue<EnumValues, WorkStatus, WorkStatus> status;

  /// Mutation value for `optionalStatus`.
  final RivetValue<EnumValues, WorkStatus?, WorkStatus?> optionalStatus;

  /// Mutation value for `nullableStatuses`.
  final RivetValue<EnumValues, List<WorkStatus?>, List<WorkStatus?>>
  nullableStatuses;

  /// Mutation value for `optionalStatuses`.
  final RivetValue<EnumValues, List<WorkStatus>?, List<WorkStatus>?>
  optionalStatuses;

  /// Mutation value for `optionalNullableStatuses`.
  final RivetValue<EnumValues, List<WorkStatus?>?, List<WorkStatus?>?>
  optionalNullableStatuses;

  /// Mutation value for `mappedStatus`.
  final RivetValue<EnumValues, WorkState, WorkStatus> mappedStatus;

  /// The generated column assignments in declaration order.
  @override
  List<RivetAssignment<EnumValues>> get assignments => [
    RivetAssignment('status', status),
    RivetAssignment('optionalStatus', optionalStatus),
    RivetAssignment('nullableStatuses', nullableStatuses),
    RivetAssignment('optionalStatuses', optionalStatuses),
    RivetAssignment('optionalNullableStatuses', optionalNullableStatuses),
    RivetAssignment('mappedStatus', mappedStatus),
  ];
}

final class _$EnumValuesDB
    extends RivetTableAccessor<EnumValues, EnumValuesRow> {
  const _$EnumValuesDB();

  @override
  RivetTableSchema<EnumValues, EnumValuesRow> buildSchema() {
    final definition = EnumValues();
    definition.status.configureEnum(WorkStatusRivetEnum.codec);
    definition.optionalStatus.configureEnum(WorkStatusRivetEnum.codec);
    definition.nullableStatuses.configureEnum(WorkStatusRivetEnum.codec);
    definition.optionalStatuses.configureEnum(WorkStatusRivetEnum.codec);
    definition.optionalNullableStatuses.configureEnum(
      WorkStatusRivetEnum.codec,
    );
    definition.mappedStatus.configureEnum(WorkStatusRivetEnum.codec);
    return RivetTableSchema<EnumValues, EnumValuesRow>(
      schemaName: 'fbr120',
      tableName: 'enumValues',
      definition: definition,
      columns: [
        definition.status as RivetColumn<Object?>,
        definition.optionalStatus as RivetColumn<Object?>,
        definition.nullableStatuses as RivetColumn<Object?>,
        definition.optionalStatuses as RivetColumn<Object?>,
        definition.optionalNullableStatuses as RivetColumn<Object?>,
        definition.mappedStatus as RivetColumn<Object?>,
      ],
      columnNames: [
        'status',
        'optionalStatus',
        'nullableStatuses',
        'optionalStatuses',
        'optionalNullableStatuses',
        'mappedStatus',
      ],
      decode: (values, sqlNulls) => EnumValuesRow(
        status: definition.status.decodeValue(
          values[0],
          isSqlNull: sqlNulls[0],
        ),
        optionalStatus: definition.optionalStatus.decodeValue(
          values[1],
          isSqlNull: sqlNulls[1],
        ),
        nullableStatuses: definition.nullableStatuses.decodeValue(
          values[2],
          isSqlNull: sqlNulls[2],
        ),
        optionalStatuses: definition.optionalStatuses.decodeValue(
          values[3],
          isSqlNull: sqlNulls[3],
        ),
        optionalNullableStatuses: definition.optionalNullableStatuses
            .decodeValue(values[4], isSqlNull: sqlNulls[4]),
        mappedStatus: definition.mappedStatus.decodeValue(
          values[5],
          isSqlNull: sqlNulls[5],
        ),
      ),
    );
  }

  /// Creates a reusable insert plan.
  RivetInsert<EnumValues, EnumValuesRow> insert(
    EnumValuesCompanion companion,
  ) => RivetInsert(buildSchema(), companion);
}

/// Generated row returned by reads from 'fbr121.vectorValues'.
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

/// Generated values accepted by mutations of 'fbr121.vectorValues'.
final class VectorValuesCompanion implements RivetCompanion<VectorValues> {
  const VectorValuesCompanion._({
    required this.embedding,
    required this.optionalEmbedding,
  });

  /// Creates values for an insert, leaving defaulted columns absent.
  factory VectorValuesCompanion.insert({
    required RivetValue<VectorValues, Float32List, Float32List> embedding,
    RivetValue<VectorValues, Float32List?, Float32List?> optionalEmbedding =
        const RivetValue.absent(),
  }) => VectorValuesCompanion._(
    embedding: embedding,
    optionalEmbedding: optionalEmbedding,
  );

  /// Mutation value for `embedding`.
  final RivetValue<VectorValues, Float32List, Float32List> embedding;

  /// Mutation value for `optionalEmbedding`.
  final RivetValue<VectorValues, Float32List?, Float32List?> optionalEmbedding;

  /// The generated column assignments in declaration order.
  @override
  List<RivetAssignment<VectorValues>> get assignments => [
    RivetAssignment('embedding', embedding),
    RivetAssignment('optionalEmbedding', optionalEmbedding),
  ];
}

final class _$VectorValuesDB
    extends RivetTableAccessor<VectorValues, VectorValuesRow> {
  const _$VectorValuesDB();

  @override
  RivetTableSchema<VectorValues, VectorValuesRow> buildSchema() {
    final definition = VectorValues();

    return RivetTableSchema<VectorValues, VectorValuesRow>(
      schemaName: 'fbr121',
      tableName: 'vectorValues',
      definition: definition,
      columns: [
        definition.embedding as RivetColumn<Object?>,
        definition.optionalEmbedding as RivetColumn<Object?>,
      ],
      columnNames: ['embedding', 'optionalEmbedding'],
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

  /// Creates a reusable insert plan.
  RivetInsert<VectorValues, VectorValuesRow> insert(
    VectorValuesCompanion companion,
  ) => RivetInsert(buildSchema(), companion);
}

/// Generated row returned by reads from 'fbr122.arrayValues'.
final class ArrayValuesRow {
  /// Creates a row from decoded column and relation values.
  const ArrayValuesRow({
    required this.ints,
    required this.nullableInts,
    required this.optionalInts,
    required this.optionalNullableInts,
    required this.jsonValues,
    required this.vectors,
    required this.statuses,
    required this.codes,
  });

  /// Value read from `ints`.
  final List<int> ints;

  /// Value read from `nullableInts`.
  final List<int?> nullableInts;

  /// Value read from `optionalInts`.
  final List<int>? optionalInts;

  /// Value read from `optionalNullableInts`.
  final List<int?>? optionalNullableInts;

  /// Value read from `jsonValues`.
  final List<JsonValue?> jsonValues;

  /// Value read from `vectors`.
  final List<Float32List> vectors;

  /// Value read from `statuses`.
  final List<WorkStatus> statuses;

  /// Value read from `codes`.
  final List<UserCode?> codes;
}

/// Generated values accepted by mutations of 'fbr122.arrayValues'.
final class ArrayValuesCompanion implements RivetCompanion<ArrayValues> {
  const ArrayValuesCompanion._({
    required this.ints,
    required this.nullableInts,
    required this.optionalInts,
    required this.optionalNullableInts,
    required this.jsonValues,
    required this.vectors,
    required this.statuses,
    required this.codes,
  });

  /// Creates values for an insert, leaving defaulted columns absent.
  factory ArrayValuesCompanion.insert({
    required RivetValue<ArrayValues, List<int>, List<int>> ints,
    required RivetValue<ArrayValues, List<int?>, List<int?>> nullableInts,
    required RivetValue<ArrayValues, List<JsonValue?>, List<JsonValue?>>
    jsonValues,
    required RivetValue<ArrayValues, List<Float32List>, List<Float32List>>
    vectors,
    required RivetValue<ArrayValues, List<WorkStatus>, List<WorkStatus>>
    statuses,
    required RivetValue<ArrayValues, List<UserCode?>, List<String?>> codes,
    RivetValue<ArrayValues, List<int>?, List<int>?> optionalInts =
        const RivetValue.absent(),
    RivetValue<ArrayValues, List<int?>?, List<int?>?> optionalNullableInts =
        const RivetValue.absent(),
  }) => ArrayValuesCompanion._(
    ints: ints,
    nullableInts: nullableInts,
    optionalInts: optionalInts,
    optionalNullableInts: optionalNullableInts,
    jsonValues: jsonValues,
    vectors: vectors,
    statuses: statuses,
    codes: codes,
  );

  /// Mutation value for `ints`.
  final RivetValue<ArrayValues, List<int>, List<int>> ints;

  /// Mutation value for `nullableInts`.
  final RivetValue<ArrayValues, List<int?>, List<int?>> nullableInts;

  /// Mutation value for `optionalInts`.
  final RivetValue<ArrayValues, List<int>?, List<int>?> optionalInts;

  /// Mutation value for `optionalNullableInts`.
  final RivetValue<ArrayValues, List<int?>?, List<int?>?> optionalNullableInts;

  /// Mutation value for `jsonValues`.
  final RivetValue<ArrayValues, List<JsonValue?>, List<JsonValue?>> jsonValues;

  /// Mutation value for `vectors`.
  final RivetValue<ArrayValues, List<Float32List>, List<Float32List>> vectors;

  /// Mutation value for `statuses`.
  final RivetValue<ArrayValues, List<WorkStatus>, List<WorkStatus>> statuses;

  /// Mutation value for `codes`.
  final RivetValue<ArrayValues, List<UserCode?>, List<String?>> codes;

  /// The generated column assignments in declaration order.
  @override
  List<RivetAssignment<ArrayValues>> get assignments => [
    RivetAssignment('ints', ints),
    RivetAssignment('nullableInts', nullableInts),
    RivetAssignment('optionalInts', optionalInts),
    RivetAssignment('optionalNullableInts', optionalNullableInts),
    RivetAssignment('jsonValues', jsonValues),
    RivetAssignment('vectors', vectors),
    RivetAssignment('statuses', statuses),
    RivetAssignment('codes', codes),
  ];
}

final class _$ArrayValuesDB
    extends RivetTableAccessor<ArrayValues, ArrayValuesRow> {
  const _$ArrayValuesDB();

  @override
  RivetTableSchema<ArrayValues, ArrayValuesRow> buildSchema() {
    final definition = ArrayValues();
    definition.statuses.configureEnum(WorkStatusRivetEnum.codec);
    return RivetTableSchema<ArrayValues, ArrayValuesRow>(
      schemaName: 'fbr122',
      tableName: 'arrayValues',
      definition: definition,
      columns: [
        definition.ints as RivetColumn<Object?>,
        definition.nullableInts as RivetColumn<Object?>,
        definition.optionalInts as RivetColumn<Object?>,
        definition.optionalNullableInts as RivetColumn<Object?>,
        definition.jsonValues as RivetColumn<Object?>,
        definition.vectors as RivetColumn<Object?>,
        definition.statuses as RivetColumn<Object?>,
        definition.codes as RivetColumn<Object?>,
      ],
      columnNames: [
        'ints',
        'nullableInts',
        'optionalInts',
        'optionalNullableInts',
        'jsonValues',
        'vectors',
        'statuses',
        'codes',
      ],
      decode: (values, sqlNulls) => ArrayValuesRow(
        ints: definition.ints.decodeValue(values[0], isSqlNull: sqlNulls[0]),
        nullableInts: definition.nullableInts.decodeValue(
          values[1],
          isSqlNull: sqlNulls[1],
        ),
        optionalInts: definition.optionalInts.decodeValue(
          values[2],
          isSqlNull: sqlNulls[2],
        ),
        optionalNullableInts: definition.optionalNullableInts.decodeValue(
          values[3],
          isSqlNull: sqlNulls[3],
        ),
        jsonValues: definition.jsonValues.decodeValue(
          values[4],
          isSqlNull: sqlNulls[4],
        ),
        vectors: definition.vectors.decodeValue(
          values[5],
          isSqlNull: sqlNulls[5],
        ),
        statuses: definition.statuses.decodeValue(
          values[6],
          isSqlNull: sqlNulls[6],
        ),
        codes: definition.codes.decodeValue(values[7], isSqlNull: sqlNulls[7]),
      ),
    );
  }

  /// Creates a reusable insert plan.
  RivetInsert<ArrayValues, ArrayValuesRow> insert(
    ArrayValuesCompanion companion,
  ) => RivetInsert(buildSchema(), companion);
}

/// Generated row returned by reads from 'fbr122.malformedArrays'.
final class MalformedArraysRow {
  /// Creates a row from decoded column and relation values.
  const MalformedArraysRow({required this.ints});

  /// Value read from `ints`.
  final List<int> ints;
}

/// Generated values accepted by mutations of 'fbr122.malformedArrays'.
final class MalformedArraysCompanion
    implements RivetCompanion<MalformedArrays> {
  const MalformedArraysCompanion._({required this.ints});

  /// Creates values for an insert, leaving defaulted columns absent.
  factory MalformedArraysCompanion.insert({
    required RivetValue<MalformedArrays, List<int>, List<int>> ints,
  }) => MalformedArraysCompanion._(ints: ints);

  /// Mutation value for `ints`.
  final RivetValue<MalformedArrays, List<int>, List<int>> ints;

  /// The generated column assignments in declaration order.
  @override
  List<RivetAssignment<MalformedArrays>> get assignments => [
    RivetAssignment('ints', ints),
  ];
}

final class _$MalformedArraysDB
    extends RivetTableAccessor<MalformedArrays, MalformedArraysRow> {
  const _$MalformedArraysDB();

  @override
  RivetTableSchema<MalformedArrays, MalformedArraysRow> buildSchema() {
    final definition = MalformedArrays();

    return RivetTableSchema<MalformedArrays, MalformedArraysRow>(
      schemaName: 'fbr122',
      tableName: 'malformedArrays',
      definition: definition,
      columns: [definition.ints as RivetColumn<Object?>],
      columnNames: ['ints'],
      decode: (values, sqlNulls) => MalformedArraysRow(
        ints: definition.ints.decodeValue(values[0], isSqlNull: sqlNulls[0]),
      ),
    );
  }

  /// Creates a reusable insert plan.
  RivetInsert<MalformedArrays, MalformedArraysRow> insert(
    MalformedArraysCompanion companion,
  ) => RivetInsert(buildSchema(), companion);
}

/// Generated row returned by reads from 'metadata.metadataColumns'.
final class MetadataColumnsRow {
  /// Creates a row from decoded column and relation values.
  const MetadataColumnsRow({
    required this.count,
    required this.payload,
    required this.embedding,
    required this.values,
    required this.code,
  });

  /// Value read from `count`.
  final int? count;

  /// Value read from `payload`.
  final JsonValue payload;

  /// Value read from `embedding`.
  final Float32List embedding;

  /// Value read from `values`.
  final List<int> values;

  /// Value read from `code`.
  final UserCode code;
}

/// Generated values accepted by mutations of 'metadata.metadataColumns'.
final class MetadataColumnsCompanion
    implements RivetCompanion<MetadataColumns> {
  const MetadataColumnsCompanion._({
    required this.count,
    required this.payload,
    required this.embedding,
    required this.values,
    required this.code,
  });

  /// Creates values for an insert, leaving defaulted columns absent.
  factory MetadataColumnsCompanion.insert({
    RivetValue<MetadataColumns, int?, int?> count = const RivetValue.absent(),
    RivetValue<MetadataColumns, JsonValue, JsonValue> payload =
        const RivetValue.absent(),
    RivetValue<MetadataColumns, Float32List, Float32List> embedding =
        const RivetValue.absent(),
    RivetValue<MetadataColumns, List<int>, List<int>> values =
        const RivetValue.absent(),
    RivetValue<MetadataColumns, UserCode, String> code =
        const RivetValue.absent(),
  }) => MetadataColumnsCompanion._(
    count: count,
    payload: payload,
    embedding: embedding,
    values: values,
    code: code,
  );

  /// Mutation value for `count`.
  final RivetValue<MetadataColumns, int?, int?> count;

  /// Mutation value for `payload`.
  final RivetValue<MetadataColumns, JsonValue, JsonValue> payload;

  /// Mutation value for `embedding`.
  final RivetValue<MetadataColumns, Float32List, Float32List> embedding;

  /// Mutation value for `values`.
  final RivetValue<MetadataColumns, List<int>, List<int>> values;

  /// Mutation value for `code`.
  final RivetValue<MetadataColumns, UserCode, String> code;

  /// The generated column assignments in declaration order.
  @override
  List<RivetAssignment<MetadataColumns>> get assignments => [
    RivetAssignment('count', count),
    RivetAssignment('payload', payload),
    RivetAssignment('embedding', embedding),
    RivetAssignment('values', values),
    RivetAssignment('code', code),
  ];
}

final class _$MetadataColumnsDB
    extends RivetTableAccessor<MetadataColumns, MetadataColumnsRow> {
  const _$MetadataColumnsDB();

  @override
  RivetTableSchema<MetadataColumns, MetadataColumnsRow> buildSchema() {
    final definition = MetadataColumns();

    return RivetTableSchema<MetadataColumns, MetadataColumnsRow>(
      schemaName: 'metadata',
      tableName: 'metadataColumns',
      definition: definition,
      columns: [
        definition.count as RivetColumn<Object?>,
        definition.payload as RivetColumn<Object?>,
        definition.embedding as RivetColumn<Object?>,
        definition.values as RivetColumn<Object?>,
        definition.code as RivetColumn<Object?>,
      ],
      columnNames: ['count', 'payload', 'embedding', 'values', 'code'],
      decode: (values, sqlNulls) => MetadataColumnsRow(
        count: definition.count.decodeValue(values[0], isSqlNull: sqlNulls[0]),
        payload: definition.payload.decodeValue(
          values[1],
          isSqlNull: sqlNulls[1],
        ),
        embedding: definition.embedding.decodeValue(
          values[2],
          isSqlNull: sqlNulls[2],
        ),
        values: definition.values.decodeValue(
          values[3],
          isSqlNull: sqlNulls[3],
        ),
        code: definition.code.decodeValue(values[4], isSqlNull: sqlNulls[4]),
      ),
      indexes: () => definition._indexes,
      constraints: () => definition._constraints,
    );
  }

  /// Creates a reusable insert plan.
  RivetInsert<MetadataColumns, MetadataColumnsRow> insert(
    MetadataColumnsCompanion companion,
  ) => RivetInsert(buildSchema(), companion);
}

/// Generated row returned by reads from 'metadata.textTargets'.
final class TextTargetsRow {
  /// Creates a row from decoded column and relation values.
  const TextTargetsRow({required this.value});

  /// Value read from `value`.
  final String value;
}

/// Generated values accepted by mutations of 'metadata.textTargets'.
final class TextTargetsCompanion implements RivetCompanion<TextTargets> {
  const TextTargetsCompanion._({required this.value});

  /// Creates values for an insert, leaving defaulted columns absent.
  factory TextTargetsCompanion.insert({
    required RivetValue<TextTargets, String, String> value,
  }) => TextTargetsCompanion._(value: value);

  /// Mutation value for `value`.
  final RivetValue<TextTargets, String, String> value;

  /// The generated column assignments in declaration order.
  @override
  List<RivetAssignment<TextTargets>> get assignments => [
    RivetAssignment('value', value),
  ];
}

final class _$TextTargetsDB
    extends RivetTableAccessor<TextTargets, TextTargetsRow> {
  const _$TextTargetsDB();

  @override
  RivetTableSchema<TextTargets, TextTargetsRow> buildSchema() {
    final definition = TextTargets();

    return RivetTableSchema<TextTargets, TextTargetsRow>(
      schemaName: 'metadata',
      tableName: 'textTargets',
      definition: definition,
      columns: [definition.value as RivetColumn<Object?>],
      columnNames: ['value'],
      decode: (values, sqlNulls) => TextTargetsRow(
        value: definition.value.decodeValue(values[0], isSqlNull: sqlNulls[0]),
      ),
    );
  }

  /// Creates a reusable insert plan.
  RivetInsert<TextTargets, TextTargetsRow> insert(
    TextTargetsCompanion companion,
  ) => RivetInsert(buildSchema(), companion);
}

/// Generated row returned by reads from 'metadata.invalidReferences'.
final class InvalidReferencesRow {
  /// Creates a row from decoded column and relation values.
  const InvalidReferencesRow({required this.value});

  /// Value read from `value`.
  final int value;
}

/// Generated values accepted by mutations of 'metadata.invalidReferences'.
final class InvalidReferencesCompanion
    implements RivetCompanion<InvalidReferences> {
  const InvalidReferencesCompanion._({required this.value});

  /// Creates values for an insert, leaving defaulted columns absent.
  factory InvalidReferencesCompanion.insert({
    required RivetValue<InvalidReferences, int, int> value,
  }) => InvalidReferencesCompanion._(value: value);

  /// Mutation value for `value`.
  final RivetValue<InvalidReferences, int, int> value;

  /// The generated column assignments in declaration order.
  @override
  List<RivetAssignment<InvalidReferences>> get assignments => [
    RivetAssignment('value', value),
  ];
}

final class _$InvalidReferencesDB
    extends RivetTableAccessor<InvalidReferences, InvalidReferencesRow> {
  const _$InvalidReferencesDB();

  @override
  RivetTableSchema<InvalidReferences, InvalidReferencesRow> buildSchema() {
    final definition = InvalidReferences();

    return RivetTableSchema<InvalidReferences, InvalidReferencesRow>(
      schemaName: 'metadata',
      tableName: 'invalidReferences',
      definition: definition,
      columns: [definition.value as RivetColumn<Object?>],
      columnNames: ['value'],
      decode: (values, sqlNulls) => InvalidReferencesRow(
        value: definition.value.decodeValue(values[0], isSqlNull: sqlNulls[0]),
      ),
    );
  }

  /// Creates a reusable insert plan.
  RivetInsert<InvalidReferences, InvalidReferencesRow> insert(
    InvalidReferencesCompanion companion,
  ) => RivetInsert(buildSchema(), companion);
}

/// Generated row returned by reads from 'metadata.parameterNames'.
final class ParameterNamesRow {
  /// Creates a row from decoded column and relation values.
  const ParameterNamesRow({required this.value});

  /// Value read from `value`.
  final String value;
}

/// Generated values accepted by mutations of 'metadata.parameterNames'.
final class ParameterNamesCompanion implements RivetCompanion<ParameterNames> {
  const ParameterNamesCompanion._({required this.value});

  /// Creates values for an insert, leaving defaulted columns absent.
  factory ParameterNamesCompanion.insert({
    required RivetValue<ParameterNames, String, String> value,
  }) => ParameterNamesCompanion._(value: value);

  /// Mutation value for `value`.
  final RivetValue<ParameterNames, String, String> value;

  /// The generated column assignments in declaration order.
  @override
  List<RivetAssignment<ParameterNames>> get assignments => [
    RivetAssignment('value', value),
  ];
}

final class _$ParameterNamesDB
    extends RivetTableAccessor<ParameterNames, ParameterNamesRow> {
  const _$ParameterNamesDB();

  @override
  RivetTableSchema<ParameterNames, ParameterNamesRow> buildSchema() {
    final definition = ParameterNames();

    return RivetTableSchema<ParameterNames, ParameterNamesRow>(
      schemaName: 'metadata',
      tableName: 'parameterNames',
      definition: definition,
      columns: [definition.value as RivetColumn<Object?>],
      columnNames: ['value'],
      decode: (values, sqlNulls) => ParameterNamesRow(
        value: definition.value.decodeValue(values[0], isSqlNull: sqlNulls[0]),
      ),
    );
  }

  /// Creates a reusable insert plan.
  RivetInsert<ParameterNames, ParameterNamesRow> insert(
    ParameterNamesCompanion companion,
  ) => RivetInsert(buildSchema(), companion);
}

/// Generated row returned by reads from 'fbr139.mutationCatalog'.
final class MutationCatalogRow {
  /// Creates a row from decoded column and relation values.
  const MutationCatalogRow({
    required this.id,
    required this.textValue,
    required this.count,
    required this.score,
    required this.active,
    required this.createdAt,
    required this.payload,
    required this.nullablePayload,
    required this.preferences,
    required this.code,
    required this.optionalCode,
    required this.status,
    required this.statuses,
    required this.timestamps,
    required this.nullableInts,
    required this.optionalInts,
    required this.jsonValues,
    required this.mappedCodes,
    required this.embedding,
    required this.embeddings,
  });

  /// Value read from `id`.
  final int id;

  /// Value read from `textValue`.
  final String textValue;

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

  /// Value read from `nullablePayload`.
  final JsonValue? nullablePayload;

  /// Value read from `preferences`.
  final Preferences preferences;

  /// Value read from `code`.
  final MutationCode code;

  /// Value read from `optionalCode`.
  final MutationCode? optionalCode;

  /// Value read from `status`.
  final MutationStatus status;

  /// Value read from `statuses`.
  final List<MutationStatus> statuses;

  /// Value read from `timestamps`.
  final List<DateTime> timestamps;

  /// Value read from `nullableInts`.
  final List<int?> nullableInts;

  /// Value read from `optionalInts`.
  final List<int>? optionalInts;

  /// Value read from `jsonValues`.
  final List<JsonValue?> jsonValues;

  /// Value read from `mappedCodes`.
  final List<MutationCode?> mappedCodes;

  /// Value read from `embedding`.
  final Float32List embedding;

  /// Value read from `embeddings`.
  final List<Float32List> embeddings;
}

/// Generated values accepted by mutations of 'fbr139.mutationCatalog'.
final class MutationCatalogCompanion
    implements RivetCompanion<MutationCatalog> {
  const MutationCatalogCompanion._({
    required this.id,
    required this.textValue,
    required this.count,
    required this.score,
    required this.active,
    required this.createdAt,
    required this.payload,
    required this.nullablePayload,
    required this.preferences,
    required this.code,
    required this.optionalCode,
    required this.status,
    required this.statuses,
    required this.timestamps,
    required this.nullableInts,
    required this.optionalInts,
    required this.jsonValues,
    required this.mappedCodes,
    required this.embedding,
    required this.embeddings,
  });

  /// Creates values for an insert, leaving defaulted columns absent.
  factory MutationCatalogCompanion.insert({
    required RivetValue<MutationCatalog, int, int> id,
    required RivetValue<MutationCatalog, String, String> textValue,
    required RivetValue<MutationCatalog, int, int> count,
    required RivetValue<MutationCatalog, double, double> score,
    required RivetValue<MutationCatalog, bool, bool> active,
    required RivetValue<MutationCatalog, JsonValue, JsonValue> payload,
    required RivetValue<MutationCatalog, Preferences, JsonValue> preferences,
    required RivetValue<MutationCatalog, List<DateTime>, List<DateTime>>
    timestamps,
    required RivetValue<MutationCatalog, List<int?>, List<int?>> nullableInts,
    required RivetValue<MutationCatalog, List<JsonValue?>, List<JsonValue?>>
    jsonValues,
    required RivetValue<MutationCatalog, Float32List, Float32List> embedding,
    required RivetValue<MutationCatalog, List<Float32List>, List<Float32List>>
    embeddings,
    RivetValue<MutationCatalog, DateTime, DateTime> createdAt =
        const RivetValue.absent(),
    RivetValue<MutationCatalog, JsonValue?, JsonValue?> nullablePayload =
        const RivetValue.absent(),
    RivetValue<MutationCatalog, MutationCode, String> code =
        const RivetValue.absent(),
    RivetValue<MutationCatalog, MutationCode?, String?> optionalCode =
        const RivetValue.absent(),
    RivetValue<MutationCatalog, MutationStatus, MutationStatus> status =
        const RivetValue.absent(),
    RivetValue<MutationCatalog, List<MutationStatus>, List<MutationStatus>>
        statuses =
        const RivetValue.absent(),
    RivetValue<MutationCatalog, List<int>?, List<int>?> optionalInts =
        const RivetValue.absent(),
    RivetValue<MutationCatalog, List<MutationCode?>, List<String?>>
        mappedCodes =
        const RivetValue.absent(),
  }) => MutationCatalogCompanion._(
    id: id,
    textValue: textValue,
    count: count,
    score: score,
    active: active,
    createdAt: createdAt,
    payload: payload,
    nullablePayload: nullablePayload,
    preferences: preferences,
    code: code,
    optionalCode: optionalCode,
    status: status,
    statuses: statuses,
    timestamps: timestamps,
    nullableInts: nullableInts,
    optionalInts: optionalInts,
    jsonValues: jsonValues,
    mappedCodes: mappedCodes,
    embedding: embedding,
    embeddings: embeddings,
  );

  /// Mutation value for `id`.
  final RivetValue<MutationCatalog, int, int> id;

  /// Mutation value for `textValue`.
  final RivetValue<MutationCatalog, String, String> textValue;

  /// Mutation value for `count`.
  final RivetValue<MutationCatalog, int, int> count;

  /// Mutation value for `score`.
  final RivetValue<MutationCatalog, double, double> score;

  /// Mutation value for `active`.
  final RivetValue<MutationCatalog, bool, bool> active;

  /// Mutation value for `createdAt`.
  final RivetValue<MutationCatalog, DateTime, DateTime> createdAt;

  /// Mutation value for `payload`.
  final RivetValue<MutationCatalog, JsonValue, JsonValue> payload;

  /// Mutation value for `nullablePayload`.
  final RivetValue<MutationCatalog, JsonValue?, JsonValue?> nullablePayload;

  /// Mutation value for `preferences`.
  final RivetValue<MutationCatalog, Preferences, JsonValue> preferences;

  /// Mutation value for `code`.
  final RivetValue<MutationCatalog, MutationCode, String> code;

  /// Mutation value for `optionalCode`.
  final RivetValue<MutationCatalog, MutationCode?, String?> optionalCode;

  /// Mutation value for `status`.
  final RivetValue<MutationCatalog, MutationStatus, MutationStatus> status;

  /// Mutation value for `statuses`.
  final RivetValue<MutationCatalog, List<MutationStatus>, List<MutationStatus>>
  statuses;

  /// Mutation value for `timestamps`.
  final RivetValue<MutationCatalog, List<DateTime>, List<DateTime>> timestamps;

  /// Mutation value for `nullableInts`.
  final RivetValue<MutationCatalog, List<int?>, List<int?>> nullableInts;

  /// Mutation value for `optionalInts`.
  final RivetValue<MutationCatalog, List<int>?, List<int>?> optionalInts;

  /// Mutation value for `jsonValues`.
  final RivetValue<MutationCatalog, List<JsonValue?>, List<JsonValue?>>
  jsonValues;

  /// Mutation value for `mappedCodes`.
  final RivetValue<MutationCatalog, List<MutationCode?>, List<String?>>
  mappedCodes;

  /// Mutation value for `embedding`.
  final RivetValue<MutationCatalog, Float32List, Float32List> embedding;

  /// Mutation value for `embeddings`.
  final RivetValue<MutationCatalog, List<Float32List>, List<Float32List>>
  embeddings;

  /// The generated column assignments in declaration order.
  @override
  List<RivetAssignment<MutationCatalog>> get assignments => [
    RivetAssignment('id', id),
    RivetAssignment('textValue', textValue),
    RivetAssignment('count', count),
    RivetAssignment('score', score),
    RivetAssignment('active', active),
    RivetAssignment('createdAt', createdAt),
    RivetAssignment('payload', payload),
    RivetAssignment('nullablePayload', nullablePayload),
    RivetAssignment('preferences', preferences),
    RivetAssignment('code', code),
    RivetAssignment('optionalCode', optionalCode),
    RivetAssignment('status', status),
    RivetAssignment('statuses', statuses),
    RivetAssignment('timestamps', timestamps),
    RivetAssignment('nullableInts', nullableInts),
    RivetAssignment('optionalInts', optionalInts),
    RivetAssignment('jsonValues', jsonValues),
    RivetAssignment('mappedCodes', mappedCodes),
    RivetAssignment('embedding', embedding),
    RivetAssignment('embeddings', embeddings),
  ];
}

final class _$MutationCatalogDB
    extends RivetTableAccessor<MutationCatalog, MutationCatalogRow> {
  const _$MutationCatalogDB();

  @override
  RivetTableSchema<MutationCatalog, MutationCatalogRow> buildSchema() {
    final definition = MutationCatalog();
    definition.status.configureEnum(MutationStatusRivetEnum.codec);
    definition.statuses.configureEnum(MutationStatusRivetEnum.codec);
    return RivetTableSchema<MutationCatalog, MutationCatalogRow>(
      schemaName: 'fbr139',
      tableName: 'mutationCatalog',
      definition: definition,
      columns: [
        definition.id as RivetColumn<Object?>,
        definition.textValue as RivetColumn<Object?>,
        definition.count as RivetColumn<Object?>,
        definition.score as RivetColumn<Object?>,
        definition.active as RivetColumn<Object?>,
        definition.createdAt as RivetColumn<Object?>,
        definition.payload as RivetColumn<Object?>,
        definition.nullablePayload as RivetColumn<Object?>,
        definition.preferences as RivetColumn<Object?>,
        definition.code as RivetColumn<Object?>,
        definition.optionalCode as RivetColumn<Object?>,
        definition.status as RivetColumn<Object?>,
        definition.statuses as RivetColumn<Object?>,
        definition.timestamps as RivetColumn<Object?>,
        definition.nullableInts as RivetColumn<Object?>,
        definition.optionalInts as RivetColumn<Object?>,
        definition.jsonValues as RivetColumn<Object?>,
        definition.mappedCodes as RivetColumn<Object?>,
        definition.embedding as RivetColumn<Object?>,
        definition.embeddings as RivetColumn<Object?>,
      ],
      columnNames: [
        'id',
        'textValue',
        'count',
        'score',
        'active',
        'createdAt',
        'payload',
        'nullablePayload',
        'preferences',
        'code',
        'optionalCode',
        'status',
        'statuses',
        'timestamps',
        'nullableInts',
        'optionalInts',
        'jsonValues',
        'mappedCodes',
        'embedding',
        'embeddings',
      ],
      decode: (values, sqlNulls) => MutationCatalogRow(
        id: definition.id.decodeValue(values[0], isSqlNull: sqlNulls[0]),
        textValue: definition.textValue.decodeValue(
          values[1],
          isSqlNull: sqlNulls[1],
        ),
        count: definition.count.decodeValue(values[2], isSqlNull: sqlNulls[2]),
        score: definition.score.decodeValue(values[3], isSqlNull: sqlNulls[3]),
        active: definition.active.decodeValue(
          values[4],
          isSqlNull: sqlNulls[4],
        ),
        createdAt: definition.createdAt.decodeValue(
          values[5],
          isSqlNull: sqlNulls[5],
        ),
        payload: definition.payload.decodeValue(
          values[6],
          isSqlNull: sqlNulls[6],
        ),
        nullablePayload: definition.nullablePayload.decodeValue(
          values[7],
          isSqlNull: sqlNulls[7],
        ),
        preferences: definition.preferences.decodeValue(
          values[8],
          isSqlNull: sqlNulls[8],
        ),
        code: definition.code.decodeValue(values[9], isSqlNull: sqlNulls[9]),
        optionalCode: definition.optionalCode.decodeValue(
          values[10],
          isSqlNull: sqlNulls[10],
        ),
        status: definition.status.decodeValue(
          values[11],
          isSqlNull: sqlNulls[11],
        ),
        statuses: definition.statuses.decodeValue(
          values[12],
          isSqlNull: sqlNulls[12],
        ),
        timestamps: definition.timestamps.decodeValue(
          values[13],
          isSqlNull: sqlNulls[13],
        ),
        nullableInts: definition.nullableInts.decodeValue(
          values[14],
          isSqlNull: sqlNulls[14],
        ),
        optionalInts: definition.optionalInts.decodeValue(
          values[15],
          isSqlNull: sqlNulls[15],
        ),
        jsonValues: definition.jsonValues.decodeValue(
          values[16],
          isSqlNull: sqlNulls[16],
        ),
        mappedCodes: definition.mappedCodes.decodeValue(
          values[17],
          isSqlNull: sqlNulls[17],
        ),
        embedding: definition.embedding.decodeValue(
          values[18],
          isSqlNull: sqlNulls[18],
        ),
        embeddings: definition.embeddings.decodeValue(
          values[19],
          isSqlNull: sqlNulls[19],
        ),
      ),
    );
  }

  /// Creates a reusable insert plan.
  RivetInsert<MutationCatalog, MutationCatalogRow> insert(
    MutationCatalogCompanion companion,
  ) => RivetInsert(buildSchema(), companion);
}

/// Generated row returned by reads from 'fbr138.mutationUsers'.
final class MutationUsersRow {
  /// Creates a row from decoded column and relation values.
  const MutationUsersRow({
    required this.id,
    required this.name,
    required this.nickname,
    required this.createdAt,
    required this.updatedAt,
    required this.nullableDefault,
    required this.serverValue,
  });

  /// Value read from `id`.
  final int id;

  /// Value read from `name`.
  final String name;

  /// Value read from `nickname`.
  final String? nickname;

  /// Value read from `createdAt`.
  final DateTime createdAt;

  /// Value read from `updatedAt`.
  final DateTime updatedAt;

  /// Value read from `nullableDefault`.
  final String? nullableDefault;

  /// Value read from `serverValue`.
  final int serverValue;
}

/// Generated values accepted by mutations of 'fbr138.mutationUsers'.
final class MutationUsersCompanion implements RivetCompanion<MutationUsers> {
  const MutationUsersCompanion._({
    required this.id,
    required this.name,
    required this.nickname,
    required this.createdAt,
    required this.updatedAt,
    required this.nullableDefault,
    required this.serverValue,
  });

  /// Creates values for an insert, leaving defaulted columns absent.
  factory MutationUsersCompanion.insert({
    required RivetValue<MutationUsers, int, int> id,
    required RivetValue<MutationUsers, String, String> name,
    RivetValue<MutationUsers, String?, String?> nickname =
        const RivetValue.absent(),
    RivetValue<MutationUsers, DateTime, DateTime> createdAt =
        const RivetValue.absent(),
    RivetValue<MutationUsers, DateTime, DateTime> updatedAt =
        const RivetValue.absent(),
    RivetValue<MutationUsers, String?, String?> nullableDefault =
        const RivetValue.absent(),
    RivetValue<MutationUsers, int, int> serverValue = const RivetValue.absent(),
  }) => MutationUsersCompanion._(
    id: id,
    name: name,
    nickname: nickname,
    createdAt: createdAt,
    updatedAt: updatedAt,
    nullableDefault: nullableDefault,
    serverValue: serverValue,
  );

  /// Mutation value for `id`.
  final RivetValue<MutationUsers, int, int> id;

  /// Mutation value for `name`.
  final RivetValue<MutationUsers, String, String> name;

  /// Mutation value for `nickname`.
  final RivetValue<MutationUsers, String?, String?> nickname;

  /// Mutation value for `createdAt`.
  final RivetValue<MutationUsers, DateTime, DateTime> createdAt;

  /// Mutation value for `updatedAt`.
  final RivetValue<MutationUsers, DateTime, DateTime> updatedAt;

  /// Mutation value for `nullableDefault`.
  final RivetValue<MutationUsers, String?, String?> nullableDefault;

  /// Mutation value for `serverValue`.
  final RivetValue<MutationUsers, int, int> serverValue;

  /// The generated column assignments in declaration order.
  @override
  List<RivetAssignment<MutationUsers>> get assignments => [
    RivetAssignment('id', id),
    RivetAssignment('name', name),
    RivetAssignment('nickname', nickname),
    RivetAssignment('createdAt', createdAt),
    RivetAssignment('updatedAt', updatedAt),
    RivetAssignment('nullableDefault', nullableDefault),
    RivetAssignment('serverValue', serverValue),
  ];
}

final class _$MutationUsersDB
    extends RivetTableAccessor<MutationUsers, MutationUsersRow> {
  const _$MutationUsersDB();

  @override
  RivetTableSchema<MutationUsers, MutationUsersRow> buildSchema() {
    final definition = MutationUsers();

    return RivetTableSchema<MutationUsers, MutationUsersRow>(
      schemaName: 'fbr138',
      tableName: 'mutationUsers',
      definition: definition,
      columns: [
        definition.id as RivetColumn<Object?>,
        definition.name as RivetColumn<Object?>,
        definition.nickname as RivetColumn<Object?>,
        definition.createdAt as RivetColumn<Object?>,
        definition.updatedAt as RivetColumn<Object?>,
        definition.nullableDefault as RivetColumn<Object?>,
        definition.serverValue as RivetColumn<Object?>,
      ],
      columnNames: [
        'id',
        'name',
        'nickname',
        'createdAt',
        'updatedAt',
        'nullableDefault',
        'serverValue',
      ],
      decode: (values, sqlNulls) => MutationUsersRow(
        id: definition.id.decodeValue(values[0], isSqlNull: sqlNulls[0]),
        name: definition.name.decodeValue(values[1], isSqlNull: sqlNulls[1]),
        nickname: definition.nickname.decodeValue(
          values[2],
          isSqlNull: sqlNulls[2],
        ),
        createdAt: definition.createdAt.decodeValue(
          values[3],
          isSqlNull: sqlNulls[3],
        ),
        updatedAt: definition.updatedAt.decodeValue(
          values[4],
          isSqlNull: sqlNulls[4],
        ),
        nullableDefault: definition.nullableDefault.decodeValue(
          values[5],
          isSqlNull: sqlNulls[5],
        ),
        serverValue: definition.serverValue.decodeValue(
          values[6],
          isSqlNull: sqlNulls[6],
        ),
      ),
    );
  }

  /// Creates a reusable insert plan.
  RivetInsert<MutationUsers, MutationUsersRow> insert(
    MutationUsersCompanion companion,
  ) => RivetInsert(buildSchema(), companion);
}

/// Generated row returned by reads from 'fbr138.mutationParents'.
final class MutationParentsRow {
  /// Creates a row from decoded column and relation values.
  const MutationParentsRow({
    required this.id,
    required this.name,
    this.children = const Relation.unloaded(),
  });

  /// Value read from `id`.
  final int id;

  /// Value read from `name`.
  final String name;

  /// Loaded or unloaded `children` relation.
  final Relation<List<MutationChildrenRow>> children;
}

/// Generated values accepted by mutations of 'fbr138.mutationParents'.
final class MutationParentsCompanion
    implements RivetCompanion<MutationParents> {
  const MutationParentsCompanion._({required this.id, required this.name});

  /// Creates values for an insert, leaving defaulted columns absent.
  factory MutationParentsCompanion.insert({
    required RivetValue<MutationParents, int, int> id,
    required RivetValue<MutationParents, String, String> name,
  }) => MutationParentsCompanion._(id: id, name: name);

  /// Mutation value for `id`.
  final RivetValue<MutationParents, int, int> id;

  /// Mutation value for `name`.
  final RivetValue<MutationParents, String, String> name;

  /// The generated column assignments in declaration order.
  @override
  List<RivetAssignment<MutationParents>> get assignments => [
    RivetAssignment('id', id),
    RivetAssignment('name', name),
  ];
}

final class _$MutationParentsDB
    extends RivetTableAccessor<MutationParents, MutationParentsRow> {
  const _$MutationParentsDB();

  @override
  RivetTableSchema<MutationParents, MutationParentsRow> buildSchema() {
    final definition = MutationParents();

    return RivetTableSchema<MutationParents, MutationParentsRow>(
      schemaName: 'fbr138',
      tableName: 'mutationParents',
      definition: definition,
      columns: [
        definition.id as RivetColumn<Object?>,
        definition.name as RivetColumn<Object?>,
      ],
      columnNames: ['id', 'name'],
      decode: (values, sqlNulls) => MutationParentsRow(
        id: definition.id.decodeValue(values[0], isSqlNull: sqlNulls[0]),
        name: definition.name.decodeValue(values[1], isSqlNull: sqlNulls[1]),
      ),
      relations: {
        'children': definition.children as RivetRelationDescriptor<Object?>,
      },
    );
  }

  /// Creates a reusable insert plan.
  RivetInsert<MutationParents, MutationParentsRow> insert(
    MutationParentsCompanion companion,
  ) => RivetInsert(buildSchema(), companion);
}

/// Generated row returned by reads from 'fbr138.mutationChildren'.
final class MutationChildrenRow {
  /// Creates a row from decoded column and relation values.
  const MutationChildrenRow({
    required this.id,
    required this.parentId,
    this.parent = const Relation.unloaded(),
  });

  /// Value read from `id`.
  final int id;

  /// Value read from `parentId`.
  final int parentId;

  /// Loaded or unloaded `parent` relation.
  final Relation<MutationParentsRow?> parent;
}

/// Generated values accepted by mutations of 'fbr138.mutationChildren'.
final class MutationChildrenCompanion
    implements RivetCompanion<MutationChildren> {
  const MutationChildrenCompanion._({required this.id, required this.parentId});

  /// Creates values for an insert, leaving defaulted columns absent.
  factory MutationChildrenCompanion.insert({
    required RivetValue<MutationChildren, int, int> id,
    required RivetValue<MutationChildren, int, int> parentId,
  }) => MutationChildrenCompanion._(id: id, parentId: parentId);

  /// Mutation value for `id`.
  final RivetValue<MutationChildren, int, int> id;

  /// Mutation value for `parentId`.
  final RivetValue<MutationChildren, int, int> parentId;

  /// The generated column assignments in declaration order.
  @override
  List<RivetAssignment<MutationChildren>> get assignments => [
    RivetAssignment('id', id),
    RivetAssignment('parentId', parentId),
  ];
}

final class _$MutationChildrenDB
    extends RivetTableAccessor<MutationChildren, MutationChildrenRow> {
  const _$MutationChildrenDB();

  @override
  RivetTableSchema<MutationChildren, MutationChildrenRow> buildSchema() {
    final definition = MutationChildren();

    return RivetTableSchema<MutationChildren, MutationChildrenRow>(
      schemaName: 'fbr138',
      tableName: 'mutationChildren',
      definition: definition,
      columns: [
        definition.id as RivetColumn<Object?>,
        definition.parentId as RivetColumn<Object?>,
      ],
      columnNames: ['id', 'parentId'],
      decode: (values, sqlNulls) => MutationChildrenRow(
        id: definition.id.decodeValue(values[0], isSqlNull: sqlNulls[0]),
        parentId: definition.parentId.decodeValue(
          values[1],
          isSqlNull: sqlNulls[1],
        ),
      ),
      relations: {
        'parent': definition.parent as RivetRelationDescriptor<Object?>,
      },
    );
  }

  /// Creates a reusable insert plan.
  RivetInsert<MutationChildren, MutationChildrenRow> insert(
    MutationChildrenCompanion companion,
  ) => RivetInsert(buildSchema(), companion);
}

// **************************************************************************
// RivetDatabaseGenerator
// **************************************************************************

abstract class _$RivetTestDatabase {
  Future<RivetDb> open({
    required RivetConnection connection,
    RivetPoolOptions pool = const RivetPoolOptions(),
  }) => RivetDb.open(
    name: 'rivet_test',
    connection: connection,
    pool: pool,
    tables: [
      UserProfiles.db.buildSchema() as RivetTableSchema<Object?, Object?>,
      Posts.db.buildSchema() as RivetTableSchema<Object?, Object?>,
      ScalarValues.db.buildSchema() as RivetTableSchema<Object?, Object?>,
      EnumValues.db.buildSchema() as RivetTableSchema<Object?, Object?>,
      VectorValues.db.buildSchema() as RivetTableSchema<Object?, Object?>,
      ArrayValues.db.buildSchema() as RivetTableSchema<Object?, Object?>,
      MalformedArrays.db.buildSchema() as RivetTableSchema<Object?, Object?>,
      MetadataColumns.db.buildSchema() as RivetTableSchema<Object?, Object?>,
      ParameterNames.db.buildSchema() as RivetTableSchema<Object?, Object?>,
      MutationUsers.db.buildSchema() as RivetTableSchema<Object?, Object?>,
      MutationParents.db.buildSchema() as RivetTableSchema<Object?, Object?>,
      MutationChildren.db.buildSchema() as RivetTableSchema<Object?, Object?>,
      MutationCatalog.db.buildSchema() as RivetTableSchema<Object?, Object?>,
    ],
  );
}

// **************************************************************************
// RivetEnumGenerator
// **************************************************************************

/// Generated PostgreSQL metadata and codec for [WorkStatus].
abstract final class WorkStatusRivetEnum {
  /// Converts [WorkStatus] values to and from their stored labels.
  static const codec = RivetEnumCodec<WorkStatus>(
    schemaName: 'fbr120',
    typeName: 'workStatus',

    values: [WorkStatus.queued, WorkStatus.complete],
    labels: ['zeta', 'alpha'],
  );
}

/// Generated PostgreSQL metadata and codec for [MutationStatus].
abstract final class MutationStatusRivetEnum {
  /// Converts [MutationStatus] values to and from their stored labels.
  static const codec = RivetEnumCodec<MutationStatus>(
    schemaName: 'fbr139',
    typeName: 'mutationStatus',

    values: [MutationStatus.queued, MutationStatus.complete],
    labels: ['waiting', 'finished'],
  );
}
