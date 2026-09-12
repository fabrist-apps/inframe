// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'generated_consumer.dart';

// **************************************************************************
// RivetTableGenerator
// **************************************************************************

/// Generated row returned by reads from `fbr116.userProfiles`.
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

final class _$UserProfilesDB extends RivetTableAccessor<UserProfiles, UserProfilesRow> {
  const _$UserProfilesDB();

  @override
  RivetTableSchema<UserProfiles, UserProfilesRow> buildSchema() {
    final definition = UserProfiles();

    return RivetTableSchema<UserProfiles, UserProfilesRow>(
      schemaName: 'fbr116',
      tableName: 'userProfiles',
      definition: definition,
      columns: [definition.displayName as RivetColumn<Object?>],
      columnNames: ['displayName'],
      decode: (values, sqlNulls) => UserProfilesRow(
        displayName: definition.displayName.decodeValue(
          values[0],
          isSqlNull: sqlNulls[0],
        ),
      ),
      indexes: definition._indexes,
      constraints: definition._constraints,
      relations: {
        'posts': definition.posts as RivetRelationDescriptor<Object?>,
      },
    );
  }
}

/// Generated row returned by reads from `fbr116.posts`.
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
}

/// Generated row returned by reads from `fbr119.scalarValues`.
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

final class _$ScalarValuesDB extends RivetTableAccessor<ScalarValues, ScalarValuesRow> {
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
}

/// Generated row returned by reads from `fbr120.enumValues`.
final class EnumValuesRow {
  /// Creates a row from decoded column and relation values.
  const EnumValuesRow({required this.status});

  /// Value read from `status`.
  final WorkStatus status;
}

final class _$EnumValuesDB extends RivetTableAccessor<EnumValues, EnumValuesRow> {
  const _$EnumValuesDB();

  @override
  RivetTableSchema<EnumValues, EnumValuesRow> buildSchema() {
    final definition = EnumValues();
    definition.status.useCodec(WorkStatusRivetEnum.codec);
    return RivetTableSchema<EnumValues, EnumValuesRow>(
      schemaName: 'fbr120',
      tableName: 'enumValues',
      definition: definition,
      columns: [definition.status as RivetColumn<Object?>],
      columnNames: ['status'],
      decode: (values, sqlNulls) => EnumValuesRow(
        status: definition.status.decodeValue(
          values[0],
          isSqlNull: sqlNulls[0],
        ),
      ),
    );
  }
}

/// Generated row returned by reads from `fbr121.vectorValues`.
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

final class _$VectorValuesDB extends RivetTableAccessor<VectorValues, VectorValuesRow> {
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
}

/// Generated row returned by reads from `fbr122.arrayValues`.
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

final class _$ArrayValuesDB extends RivetTableAccessor<ArrayValues, ArrayValuesRow> {
  const _$ArrayValuesDB();

  @override
  RivetTableSchema<ArrayValues, ArrayValuesRow> buildSchema() {
    final definition = ArrayValues();
    definition.statuses.useCodec(
      const RivetArrayCodec(WorkStatusRivetEnum.codec),
    );
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
}

// **************************************************************************
// RivetDatabaseGenerator
// **************************************************************************

abstract class _$RivetTestDatabase {
  Future<RivetDb> open({
    required RivetConnection connection,
    RivetPoolOptions pool = const RivetPoolOptions(),
  }) => RivetDb.open(
    connection: connection,
    pool: pool,
    tables: [
      UserProfiles.db.buildSchema() as RivetTableSchema<Object?, Object?>,
      Posts.db.buildSchema() as RivetTableSchema<Object?, Object?>,
      ScalarValues.db.buildSchema() as RivetTableSchema<Object?, Object?>,
      EnumValues.db.buildSchema() as RivetTableSchema<Object?, Object?>,
      VectorValues.db.buildSchema() as RivetTableSchema<Object?, Object?>,
      ArrayValues.db.buildSchema() as RivetTableSchema<Object?, Object?>,
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
