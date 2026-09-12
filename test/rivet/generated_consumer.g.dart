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
    ],
  );
}
