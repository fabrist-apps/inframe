// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'generated_consumer.dart';

// **************************************************************************
// RivetTableGenerator
// **************************************************************************

final class UserProfilesRow {
  const UserProfilesRow({
    required this.displayName,
    this.posts = const Relation.unloaded(),
  });

  final String displayName;
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

final class PostsRow {
  const PostsRow({
    required this.authorName,
    this.author = const Relation.unloaded(),
  });

  final String authorName;
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
      indexes: const <RivetIndex>[],
      constraints: const <RivetConstraint>[],
      relations: {
        'author': definition.author as RivetRelationDescriptor<Object?>,
      },
    );
  }
}

final class ScalarValuesRow {
  const ScalarValuesRow({
    required this.id,
    required this.count,
    required this.score,
    required this.active,
    required this.createdAt,
    required this.payload,
    required this.code,
    required this.optionalCode,
  });

  final String id;
  final int count;
  final double score;
  final bool active;
  final DateTime createdAt;
  final JsonValue payload;
  final UserCode code;
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
        code: definition.code.decodeValue(values[6], isSqlNull: sqlNulls[6]),
        optionalCode: definition.optionalCode.decodeValue(
          values[7],
          isSqlNull: sqlNulls[7],
        ),
      ),
      indexes: const <RivetIndex>[],
      constraints: const <RivetConstraint>[],
      relations: {},
    );
  }
}

final class EnumValuesRow {
  const EnumValuesRow({required this.status});

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
      indexes: const <RivetIndex>[],
      constraints: const <RivetConstraint>[],
      relations: {},
    );
  }
}

final class VectorValuesRow {
  const VectorValuesRow({
    required this.embedding,
    required this.optionalEmbedding,
  });

  final Float32List embedding;
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
      indexes: const <RivetIndex>[],
      constraints: const <RivetConstraint>[],
      relations: {},
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
    ],
  );
}

// **************************************************************************
// RivetEnumGenerator
// **************************************************************************

abstract final class WorkStatusRivetEnum {
  static const codec = RivetEnumCodec<WorkStatus>(
    values: [WorkStatus.queued, WorkStatus.complete],
    labels: ['zeta', 'alpha'],
  );
}
