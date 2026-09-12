// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

part of 'generated_consumer.dart';

// **************************************************************************
// RivetTableGenerator
// **************************************************************************

/// Typed relation include scope for [UserProfiles].
final class UserProfilesInclude {
  /// Creates the generated include scope.
  const UserProfilesInclude(this._schema, {this.path = ''});

  final RivetTableSchema<UserProfiles, UserProfilesRow> _schema;

  /// Full relation path used in diagnostics.
  final String path;

  /// Includes the [posts] relation.
  RivetInclude<Posts, PostsRow> posts({
    RivetWhere<Posts>? where,
    RivetOrderBy<Posts>? orderBy,
    int? limit,

    RivetIncludes<PostsInclude>? include,
  }) {
    final target = Posts.db.buildSchema();

    final relationPath = path.isEmpty ? 'posts' : '$path.posts';
    return RivetInclude<Posts, PostsRow>(
      name: 'posts',
      path: relationPath,
      relation: _schema.relations['posts']!,
      targetSchema: target,

      where: where,
      orderBy: orderBy,
      limit: limit,

      includes:
          include?.call(PostsInclude(target, path: relationPath)) ?? const [],
    );
  }
}

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

  /// Creates values for an update, leaving untouched columns absent.
  factory UserProfilesCompanion.update({
    RivetValue<UserProfiles, String, String> displayName =
        const RivetValue.absent(),
  }) => UserProfilesCompanion._(displayName: displayName);

  /// Mutation value for `displayName`.
  final RivetValue<UserProfiles, String, String> displayName;

  /// The generated column assignments in declaration order.
  @override
  List<RivetAssignment<UserProfiles>> operator [](RivetCompanionKey key) => [
    RivetAssignment('displayName', displayName),
  ];
}

final class _$UserProfilesDB
    extends RivetTableAccessor<UserProfiles, UserProfilesRow> {
  const _$UserProfilesDB();

  @override
  RivetTableSchema<UserProfiles, UserProfilesRow> buildSchema() {
    UserProfiles createDefinition() {
      final definition = UserProfiles();

      return definition;
    }

    final definition = createDefinition();
    UserProfilesRow decodeRow(
      List<Object?> values,
      List<bool> sqlNulls,
      RivetRelationValues relations, {
      required bool transport,
    }) => UserProfilesRow(
      displayName: transport
          ? definition.displayName.decodeTransportValue(
              values[0],
              isSqlNull: sqlNulls[0],
            )
          : definition.displayName.decodeValue(
              values[0],
              isSqlNull: sqlNulls[0],
            ),
      posts: relations.read('posts'),
    );

    final builtSchema = RivetTableSchema<UserProfiles, UserProfilesRow>(
      schemaName: 'fbr116',
      tableName: 'userProfiles',
      renamedFrom: 'profiles',
      definition: definition,
      columns: [definition.displayName as RivetColumn<Object?>],
      columnNames: ['displayName'],
      createDefinition: createDefinition,
      columnsFor: (definition) => [
        definition.displayName as RivetColumn<Object?>,
      ],
      decode: (values, sqlNulls) => decodeRow(
        values,
        sqlNulls,
        const RivetRelationValues(),
        transport: false,
      ),
      decodeRelated: decodeRow,

      indexes: () => definition._indexes,
      constraints: () => definition._constraints,
      relations: {
        'posts': definition.posts as RivetRelationDescriptor<Object?>,
      },
    );
    definition.posts.bind(
      name: 'posts',
      ownerSchema: builtSchema,
      targetSchema: () => Posts.db.buildSchema(),
    );
    return builtSchema;
  }

  /// Creates a reusable read plan with typed relation includes.
  RivetFind<UserProfiles, UserProfilesRow> find({
    RivetWhere<UserProfiles>? where,
    RivetOrderBy<UserProfiles>? orderBy,
    int? limit,
    int? offset,
    RivetIncludes<UserProfilesInclude>? include,
  }) {
    final schema = buildSchema();
    return RivetFind(
      schema,
      where: where,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
      includes: include?.call(UserProfilesInclude(schema)) ?? const [],
    );
  }

  /// Creates a reusable insert plan.
  RivetInsert<UserProfiles, UserProfilesRow> insert(
    UserProfilesCompanion companion, {
    RivetOnConflict<UserProfiles>? onConflict,
  }) => RivetInsert(buildSchema(), companion, onConflict: onConflict);

  /// Creates a reusable batch insert plan.
  RivetInsertMany<UserProfiles, UserProfilesRow> insertMany(
    Iterable<UserProfilesCompanion> companions, {
    RivetOnConflict<UserProfiles>? onConflict,
  }) => RivetInsertMany(buildSchema(), companions, onConflict: onConflict);

  /// Creates a reusable update plan.
  RivetUpdate<UserProfiles, UserProfilesRow> update(
    UserProfilesCompanion companion, {
    RivetWhere<UserProfiles>? where,
  }) => RivetUpdate(buildSchema(), companion, where: where);

  /// Creates a reusable delete plan.
  RivetDelete<UserProfiles, UserProfilesRow> delete({
    RivetWhere<UserProfiles>? where,
  }) => RivetDelete(buildSchema(), where: where);
}

/// Typed relation include scope for [Posts].
final class PostsInclude {
  /// Creates the generated include scope.
  const PostsInclude(this._schema, {this.path = ''});

  final RivetTableSchema<Posts, PostsRow> _schema;

  /// Full relation path used in diagnostics.
  final String path;

  /// Includes the [author] relation.
  RivetInclude<UserProfiles, UserProfilesRow> author({
    RivetWhere<UserProfiles>? where,

    RivetIncludes<UserProfilesInclude>? include,
  }) {
    final target = UserProfiles.db.buildSchema();

    final relationPath = path.isEmpty ? 'author' : '$path.author';
    return RivetInclude<UserProfiles, UserProfilesRow>(
      name: 'author',
      path: relationPath,
      relation: _schema.relations['author']!,
      targetSchema: target,

      where: where,

      includes:
          include?.call(UserProfilesInclude(target, path: relationPath)) ??
          const [],
    );
  }
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

  /// Creates values for an update, leaving untouched columns absent.
  factory PostsCompanion.update({
    RivetValue<Posts, String, String> authorName = const RivetValue.absent(),
  }) => PostsCompanion._(authorName: authorName);

  /// Mutation value for `authorName`.
  final RivetValue<Posts, String, String> authorName;

  /// The generated column assignments in declaration order.
  @override
  List<RivetAssignment<Posts>> operator [](RivetCompanionKey key) => [
    RivetAssignment('authorName', authorName),
  ];
}

final class _$PostsDB extends RivetTableAccessor<Posts, PostsRow> {
  const _$PostsDB();

  @override
  RivetTableSchema<Posts, PostsRow> buildSchema() {
    Posts createDefinition() {
      final definition = Posts();

      return definition;
    }

    final definition = createDefinition();
    PostsRow decodeRow(
      List<Object?> values,
      List<bool> sqlNulls,
      RivetRelationValues relations, {
      required bool transport,
    }) => PostsRow(
      authorName: transport
          ? definition.authorName.decodeTransportValue(
              values[0],
              isSqlNull: sqlNulls[0],
            )
          : definition.authorName.decodeValue(
              values[0],
              isSqlNull: sqlNulls[0],
            ),
      author: relations.read('author'),
    );

    final builtSchema = RivetTableSchema<Posts, PostsRow>(
      schemaName: 'fbr116',
      tableName: 'posts',
      definition: definition,
      columns: [definition.authorName as RivetColumn<Object?>],
      columnNames: ['authorName'],
      createDefinition: createDefinition,
      columnsFor: (definition) => [
        definition.authorName as RivetColumn<Object?>,
      ],
      decode: (values, sqlNulls) => decodeRow(
        values,
        sqlNulls,
        const RivetRelationValues(),
        transport: false,
      ),
      decodeRelated: decodeRow,

      relations: {
        'author': definition.author as RivetRelationDescriptor<Object?>,
      },
    );
    definition.author.bind(
      name: 'author',
      ownerSchema: builtSchema,
      targetSchema: () => UserProfiles.db.buildSchema(),
    );
    return builtSchema;
  }

  /// Creates a reusable read plan with typed relation includes.
  RivetFind<Posts, PostsRow> find({
    RivetWhere<Posts>? where,
    RivetOrderBy<Posts>? orderBy,
    int? limit,
    int? offset,
    RivetIncludes<PostsInclude>? include,
  }) {
    final schema = buildSchema();
    return RivetFind(
      schema,
      where: where,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
      includes: include?.call(PostsInclude(schema)) ?? const [],
    );
  }

  /// Creates a reusable insert plan.
  RivetInsert<Posts, PostsRow> insert(
    PostsCompanion companion, {
    RivetOnConflict<Posts>? onConflict,
  }) => RivetInsert(buildSchema(), companion, onConflict: onConflict);

  /// Creates a reusable batch insert plan.
  RivetInsertMany<Posts, PostsRow> insertMany(
    Iterable<PostsCompanion> companions, {
    RivetOnConflict<Posts>? onConflict,
  }) => RivetInsertMany(buildSchema(), companions, onConflict: onConflict);

  /// Creates a reusable update plan.
  RivetUpdate<Posts, PostsRow> update(
    PostsCompanion companion, {
    RivetWhere<Posts>? where,
  }) => RivetUpdate(buildSchema(), companion, where: where);

  /// Creates a reusable delete plan.
  RivetDelete<Posts, PostsRow> delete({RivetWhere<Posts>? where}) =>
      RivetDelete(buildSchema(), where: where);
}

/// Typed relation include scope for [RelationalUsers].
final class RelationalUsersInclude {
  /// Creates the generated include scope.
  const RelationalUsersInclude(this._schema, {this.path = ''});

  final RivetTableSchema<RelationalUsers, RelationalUsersRow> _schema;

  /// Full relation path used in diagnostics.
  final String path;

  /// Includes the [authoredPosts] relation.
  RivetInclude<RelationalPosts, RelationalPostsRow> authoredPosts({
    RivetWhere<RelationalPosts>? where,
    RivetOrderBy<RelationalPosts>? orderBy,
    int? limit,

    RivetIncludes<RelationalPostsInclude>? include,
  }) {
    final target = RelationalPosts.db.buildSchema();

    final relationPath = path.isEmpty ? 'authoredPosts' : '$path.authoredPosts';
    return RivetInclude<RelationalPosts, RelationalPostsRow>(
      name: 'authoredPosts',
      path: relationPath,
      relation: _schema.relations['authoredPosts']!,
      targetSchema: target,

      where: where,
      orderBy: orderBy,
      limit: limit,

      includes:
          include?.call(RelationalPostsInclude(target, path: relationPath)) ??
          const [],
    );
  }

  /// Includes the [reviewedPosts] relation.
  RivetInclude<RelationalPosts, RelationalPostsRow> reviewedPosts({
    RivetWhere<RelationalPosts>? where,
    RivetOrderBy<RelationalPosts>? orderBy,
    int? limit,

    RivetIncludes<RelationalPostsInclude>? include,
  }) {
    final target = RelationalPosts.db.buildSchema();

    final relationPath = path.isEmpty ? 'reviewedPosts' : '$path.reviewedPosts';
    return RivetInclude<RelationalPosts, RelationalPostsRow>(
      name: 'reviewedPosts',
      path: relationPath,
      relation: _schema.relations['reviewedPosts']!,
      targetSchema: target,

      where: where,
      orderBy: orderBy,
      limit: limit,

      includes:
          include?.call(RelationalPostsInclude(target, path: relationPath)) ??
          const [],
    );
  }

  /// Includes the [manager] relation.
  RivetInclude<RelationalUsers, RelationalUsersRow> manager({
    RivetWhere<RelationalUsers>? where,

    RivetIncludes<RelationalUsersInclude>? include,
  }) {
    final target = RelationalUsers.db.buildSchema();

    final relationPath = path.isEmpty ? 'manager' : '$path.manager';
    return RivetInclude<RelationalUsers, RelationalUsersRow>(
      name: 'manager',
      path: relationPath,
      relation: _schema.relations['manager']!,
      targetSchema: target,

      where: where,

      includes:
          include?.call(RelationalUsersInclude(target, path: relationPath)) ??
          const [],
    );
  }

  /// Includes the [reports] relation.
  RivetInclude<RelationalUsers, RelationalUsersRow> reports({
    RivetWhere<RelationalUsers>? where,
    RivetOrderBy<RelationalUsers>? orderBy,
    int? limit,

    RivetIncludes<RelationalUsersInclude>? include,
  }) {
    final target = RelationalUsers.db.buildSchema();

    final relationPath = path.isEmpty ? 'reports' : '$path.reports';
    return RivetInclude<RelationalUsers, RelationalUsersRow>(
      name: 'reports',
      path: relationPath,
      relation: _schema.relations['reports']!,
      targetSchema: target,

      where: where,
      orderBy: orderBy,
      limit: limit,

      includes:
          include?.call(RelationalUsersInclude(target, path: relationPath)) ??
          const [],
    );
  }
}

/// Generated row returned by reads from 'fbr146.relationalUsers'.
final class RelationalUsersRow {
  /// Creates a row from decoded column and relation values.
  const RelationalUsersRow({
    required this.id,
    required this.name,
    required this.managerId,
    this.authoredPosts = const Relation.unloaded(),
    this.reviewedPosts = const Relation.unloaded(),
    this.manager = const Relation.unloaded(),
    this.reports = const Relation.unloaded(),
  });

  /// Value read from `id`.
  final int id;

  /// Value read from `name`.
  final String name;

  /// Value read from `managerId`.
  final int? managerId;

  /// Loaded or unloaded `authoredPosts` relation.
  final Relation<List<RelationalPostsRow>> authoredPosts;

  /// Loaded or unloaded `reviewedPosts` relation.
  final Relation<List<RelationalPostsRow>> reviewedPosts;

  /// Loaded or unloaded `manager` relation.
  final Relation<RelationalUsersRow?> manager;

  /// Loaded or unloaded `reports` relation.
  final Relation<List<RelationalUsersRow>> reports;
}

/// Generated values accepted by mutations of 'fbr146.relationalUsers'.
final class RelationalUsersCompanion
    implements RivetCompanion<RelationalUsers> {
  const RelationalUsersCompanion._({
    required this.id,
    required this.name,
    required this.managerId,
  });

  /// Creates values for an insert, leaving defaulted columns absent.
  factory RelationalUsersCompanion.insert({
    required RivetValue<RelationalUsers, int, int> id,
    required RivetValue<RelationalUsers, String, String> name,
    RivetValue<RelationalUsers, int?, int?> managerId =
        const RivetValue.absent(),
  }) => RelationalUsersCompanion._(id: id, name: name, managerId: managerId);

  /// Creates values for an update, leaving untouched columns absent.
  factory RelationalUsersCompanion.update({
    RivetValue<RelationalUsers, int, int> id = const RivetValue.absent(),
    RivetValue<RelationalUsers, String, String> name =
        const RivetValue.absent(),
    RivetValue<RelationalUsers, int?, int?> managerId =
        const RivetValue.absent(),
  }) => RelationalUsersCompanion._(id: id, name: name, managerId: managerId);

  /// Mutation value for `id`.
  final RivetValue<RelationalUsers, int, int> id;

  /// Mutation value for `name`.
  final RivetValue<RelationalUsers, String, String> name;

  /// Mutation value for `managerId`.
  final RivetValue<RelationalUsers, int?, int?> managerId;

  /// The generated column assignments in declaration order.
  @override
  List<RivetAssignment<RelationalUsers>> operator [](RivetCompanionKey key) => [
    RivetAssignment('id', id),
    RivetAssignment('name', name),
    RivetAssignment('managerId', managerId),
  ];
}

final class _$RelationalUsersDB
    extends RivetTableAccessor<RelationalUsers, RelationalUsersRow> {
  const _$RelationalUsersDB();

  @override
  RivetTableSchema<RelationalUsers, RelationalUsersRow> buildSchema() {
    RelationalUsers createDefinition() {
      final definition = RelationalUsers();

      return definition;
    }

    final definition = createDefinition();
    RelationalUsersRow decodeRow(
      List<Object?> values,
      List<bool> sqlNulls,
      RivetRelationValues relations, {
      required bool transport,
    }) => RelationalUsersRow(
      id: transport
          ? definition.id.decodeTransportValue(
              values[0],
              isSqlNull: sqlNulls[0],
            )
          : definition.id.decodeValue(values[0], isSqlNull: sqlNulls[0]),
      name: transport
          ? definition.name.decodeTransportValue(
              values[1],
              isSqlNull: sqlNulls[1],
            )
          : definition.name.decodeValue(values[1], isSqlNull: sqlNulls[1]),
      managerId: transport
          ? definition.managerId.decodeTransportValue(
              values[2],
              isSqlNull: sqlNulls[2],
            )
          : definition.managerId.decodeValue(values[2], isSqlNull: sqlNulls[2]),
      authoredPosts: relations.read('authoredPosts'),
      reviewedPosts: relations.read('reviewedPosts'),
      manager: relations.read('manager'),
      reports: relations.read('reports'),
    );

    final builtSchema = RivetTableSchema<RelationalUsers, RelationalUsersRow>(
      schemaName: 'fbr146',
      tableName: 'relationalUsers',
      definition: definition,
      columns: [
        definition.id as RivetColumn<Object?>,
        definition.name as RivetColumn<Object?>,
        definition.managerId as RivetColumn<Object?>,
      ],
      columnNames: ['id', 'name', 'managerId'],
      createDefinition: createDefinition,
      columnsFor: (definition) => [
        definition.id as RivetColumn<Object?>,
        definition.name as RivetColumn<Object?>,
        definition.managerId as RivetColumn<Object?>,
      ],
      decode: (values, sqlNulls) => decodeRow(
        values,
        sqlNulls,
        const RivetRelationValues(),
        transport: false,
      ),
      decodeRelated: decodeRow,

      relations: {
        'authoredPosts':
            definition.authoredPosts as RivetRelationDescriptor<Object?>,
        'reviewedPosts':
            definition.reviewedPosts as RivetRelationDescriptor<Object?>,
        'manager': definition.manager as RivetRelationDescriptor<Object?>,
        'reports': definition.reports as RivetRelationDescriptor<Object?>,
      },
    );
    definition.authoredPosts.bind(
      name: 'authoredPosts',
      ownerSchema: builtSchema,
      targetSchema: () => RelationalPosts.db.buildSchema(),
    );
    definition.reviewedPosts.bind(
      name: 'reviewedPosts',
      ownerSchema: builtSchema,
      targetSchema: () => RelationalPosts.db.buildSchema(),
    );
    definition.manager.bind(
      name: 'manager',
      ownerSchema: builtSchema,
      targetSchema: () => RelationalUsers.db.buildSchema(),
    );
    definition.reports.bind(
      name: 'reports',
      ownerSchema: builtSchema,
      targetSchema: () => RelationalUsers.db.buildSchema(),
    );
    return builtSchema;
  }

  /// Creates a reusable read plan with typed relation includes.
  RivetFind<RelationalUsers, RelationalUsersRow> find({
    RivetWhere<RelationalUsers>? where,
    RivetOrderBy<RelationalUsers>? orderBy,
    int? limit,
    int? offset,
    RivetIncludes<RelationalUsersInclude>? include,
  }) {
    final schema = buildSchema();
    return RivetFind(
      schema,
      where: where,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
      includes: include?.call(RelationalUsersInclude(schema)) ?? const [],
    );
  }

  /// Creates a reusable insert plan.
  RivetInsert<RelationalUsers, RelationalUsersRow> insert(
    RelationalUsersCompanion companion, {
    RivetOnConflict<RelationalUsers>? onConflict,
  }) => RivetInsert(buildSchema(), companion, onConflict: onConflict);

  /// Creates a reusable batch insert plan.
  RivetInsertMany<RelationalUsers, RelationalUsersRow> insertMany(
    Iterable<RelationalUsersCompanion> companions, {
    RivetOnConflict<RelationalUsers>? onConflict,
  }) => RivetInsertMany(buildSchema(), companions, onConflict: onConflict);

  /// Creates a reusable update plan.
  RivetUpdate<RelationalUsers, RelationalUsersRow> update(
    RelationalUsersCompanion companion, {
    RivetWhere<RelationalUsers>? where,
  }) => RivetUpdate(buildSchema(), companion, where: where);

  /// Creates a reusable delete plan.
  RivetDelete<RelationalUsers, RelationalUsersRow> delete({
    RivetWhere<RelationalUsers>? where,
  }) => RivetDelete(buildSchema(), where: where);
}

/// Typed relation include scope for [RelationalPosts].
final class RelationalPostsInclude {
  /// Creates the generated include scope.
  const RelationalPostsInclude(this._schema, {this.path = ''});

  final RivetTableSchema<RelationalPosts, RelationalPostsRow> _schema;

  /// Full relation path used in diagnostics.
  final String path;

  /// Includes the [author] relation.
  RivetInclude<RelationalUsers, RelationalUsersRow> author({
    RivetWhere<RelationalUsers>? where,

    RivetIncludes<RelationalUsersInclude>? include,
  }) {
    final target = RelationalUsers.db.buildSchema();

    final relationPath = path.isEmpty ? 'author' : '$path.author';
    return RivetInclude<RelationalUsers, RelationalUsersRow>(
      name: 'author',
      path: relationPath,
      relation: _schema.relations['author']!,
      targetSchema: target,

      where: where,

      includes:
          include?.call(RelationalUsersInclude(target, path: relationPath)) ??
          const [],
    );
  }

  /// Includes the [reviewer] relation.
  RivetInclude<RelationalUsers, RelationalUsersRow> reviewer({
    RivetWhere<RelationalUsers>? where,

    RivetIncludes<RelationalUsersInclude>? include,
  }) {
    final target = RelationalUsers.db.buildSchema();

    final relationPath = path.isEmpty ? 'reviewer' : '$path.reviewer';
    return RivetInclude<RelationalUsers, RelationalUsersRow>(
      name: 'reviewer',
      path: relationPath,
      relation: _schema.relations['reviewer']!,
      targetSchema: target,

      where: where,

      includes:
          include?.call(RelationalUsersInclude(target, path: relationPath)) ??
          const [],
    );
  }

  /// Includes the [comments] relation.
  RivetInclude<RelationalComments, RelationalCommentsRow> comments({
    RivetWhere<RelationalComments>? where,
    RivetOrderBy<RelationalComments>? orderBy,
    int? limit,

    RivetIncludes<RelationalCommentsInclude>? include,
  }) {
    final target = RelationalComments.db.buildSchema();

    final relationPath = path.isEmpty ? 'comments' : '$path.comments';
    return RivetInclude<RelationalComments, RelationalCommentsRow>(
      name: 'comments',
      path: relationPath,
      relation: _schema.relations['comments']!,
      targetSchema: target,

      where: where,
      orderBy: orderBy,
      limit: limit,

      includes:
          include?.call(
            RelationalCommentsInclude(target, path: relationPath),
          ) ??
          const [],
    );
  }
}

/// Generated row returned by reads from 'fbr146.relationalPosts'.
final class RelationalPostsRow {
  /// Creates a row from decoded column and relation values.
  const RelationalPostsRow({
    required this.id,
    required this.authorId,
    required this.reviewerId,
    required this.title,
    required this.rank,
    this.author = const Relation.unloaded(),
    this.reviewer = const Relation.unloaded(),
    this.comments = const Relation.unloaded(),
  });

  /// Value read from `id`.
  final int id;

  /// Value read from `authorId`.
  final int authorId;

  /// Value read from `reviewerId`.
  final int? reviewerId;

  /// Value read from `title`.
  final String title;

  /// Value read from `rank`.
  final int rank;

  /// Loaded or unloaded `author` relation.
  final Relation<RelationalUsersRow?> author;

  /// Loaded or unloaded `reviewer` relation.
  final Relation<RelationalUsersRow?> reviewer;

  /// Loaded or unloaded `comments` relation.
  final Relation<List<RelationalCommentsRow>> comments;
}

/// Generated values accepted by mutations of 'fbr146.relationalPosts'.
final class RelationalPostsCompanion
    implements RivetCompanion<RelationalPosts> {
  const RelationalPostsCompanion._({
    required this.id,
    required this.authorId,
    required this.reviewerId,
    required this.title,
    required this.rank,
  });

  /// Creates values for an insert, leaving defaulted columns absent.
  factory RelationalPostsCompanion.insert({
    required RivetValue<RelationalPosts, int, int> id,
    required RivetValue<RelationalPosts, int, int> authorId,
    required RivetValue<RelationalPosts, String, String> title,
    required RivetValue<RelationalPosts, int, int> rank,
    RivetValue<RelationalPosts, int?, int?> reviewerId =
        const RivetValue.absent(),
  }) => RelationalPostsCompanion._(
    id: id,
    authorId: authorId,
    reviewerId: reviewerId,
    title: title,
    rank: rank,
  );

  /// Creates values for an update, leaving untouched columns absent.
  factory RelationalPostsCompanion.update({
    RivetValue<RelationalPosts, int, int> id = const RivetValue.absent(),
    RivetValue<RelationalPosts, int, int> authorId = const RivetValue.absent(),
    RivetValue<RelationalPosts, int?, int?> reviewerId =
        const RivetValue.absent(),
    RivetValue<RelationalPosts, String, String> title =
        const RivetValue.absent(),
    RivetValue<RelationalPosts, int, int> rank = const RivetValue.absent(),
  }) => RelationalPostsCompanion._(
    id: id,
    authorId: authorId,
    reviewerId: reviewerId,
    title: title,
    rank: rank,
  );

  /// Mutation value for `id`.
  final RivetValue<RelationalPosts, int, int> id;

  /// Mutation value for `authorId`.
  final RivetValue<RelationalPosts, int, int> authorId;

  /// Mutation value for `reviewerId`.
  final RivetValue<RelationalPosts, int?, int?> reviewerId;

  /// Mutation value for `title`.
  final RivetValue<RelationalPosts, String, String> title;

  /// Mutation value for `rank`.
  final RivetValue<RelationalPosts, int, int> rank;

  /// The generated column assignments in declaration order.
  @override
  List<RivetAssignment<RelationalPosts>> operator [](RivetCompanionKey key) => [
    RivetAssignment('id', id),
    RivetAssignment('authorId', authorId),
    RivetAssignment('reviewerId', reviewerId),
    RivetAssignment('title', title),
    RivetAssignment('rank', rank),
  ];
}

final class _$RelationalPostsDB
    extends RivetTableAccessor<RelationalPosts, RelationalPostsRow> {
  const _$RelationalPostsDB();

  @override
  RivetTableSchema<RelationalPosts, RelationalPostsRow> buildSchema() {
    RelationalPosts createDefinition() {
      final definition = RelationalPosts();

      return definition;
    }

    final definition = createDefinition();
    RelationalPostsRow decodeRow(
      List<Object?> values,
      List<bool> sqlNulls,
      RivetRelationValues relations, {
      required bool transport,
    }) => RelationalPostsRow(
      id: transport
          ? definition.id.decodeTransportValue(
              values[0],
              isSqlNull: sqlNulls[0],
            )
          : definition.id.decodeValue(values[0], isSqlNull: sqlNulls[0]),
      authorId: transport
          ? definition.authorId.decodeTransportValue(
              values[1],
              isSqlNull: sqlNulls[1],
            )
          : definition.authorId.decodeValue(values[1], isSqlNull: sqlNulls[1]),
      reviewerId: transport
          ? definition.reviewerId.decodeTransportValue(
              values[2],
              isSqlNull: sqlNulls[2],
            )
          : definition.reviewerId.decodeValue(
              values[2],
              isSqlNull: sqlNulls[2],
            ),
      title: transport
          ? definition.title.decodeTransportValue(
              values[3],
              isSqlNull: sqlNulls[3],
            )
          : definition.title.decodeValue(values[3], isSqlNull: sqlNulls[3]),
      rank: transport
          ? definition.rank.decodeTransportValue(
              values[4],
              isSqlNull: sqlNulls[4],
            )
          : definition.rank.decodeValue(values[4], isSqlNull: sqlNulls[4]),
      author: relations.read('author'),
      reviewer: relations.read('reviewer'),
      comments: relations.read('comments'),
    );

    final builtSchema = RivetTableSchema<RelationalPosts, RelationalPostsRow>(
      schemaName: 'fbr146',
      tableName: 'relationalPosts',
      definition: definition,
      columns: [
        definition.id as RivetColumn<Object?>,
        definition.authorId as RivetColumn<Object?>,
        definition.reviewerId as RivetColumn<Object?>,
        definition.title as RivetColumn<Object?>,
        definition.rank as RivetColumn<Object?>,
      ],
      columnNames: ['id', 'authorId', 'reviewerId', 'title', 'rank'],
      createDefinition: createDefinition,
      columnsFor: (definition) => [
        definition.id as RivetColumn<Object?>,
        definition.authorId as RivetColumn<Object?>,
        definition.reviewerId as RivetColumn<Object?>,
        definition.title as RivetColumn<Object?>,
        definition.rank as RivetColumn<Object?>,
      ],
      decode: (values, sqlNulls) => decodeRow(
        values,
        sqlNulls,
        const RivetRelationValues(),
        transport: false,
      ),
      decodeRelated: decodeRow,

      relations: {
        'author': definition.author as RivetRelationDescriptor<Object?>,
        'reviewer': definition.reviewer as RivetRelationDescriptor<Object?>,
        'comments': definition.comments as RivetRelationDescriptor<Object?>,
      },
    );
    definition.author.bind(
      name: 'author',
      ownerSchema: builtSchema,
      targetSchema: () => RelationalUsers.db.buildSchema(),
    );
    definition.reviewer.bind(
      name: 'reviewer',
      ownerSchema: builtSchema,
      targetSchema: () => RelationalUsers.db.buildSchema(),
    );
    definition.comments.bind(
      name: 'comments',
      ownerSchema: builtSchema,
      targetSchema: () => RelationalComments.db.buildSchema(),
    );
    return builtSchema;
  }

  /// Creates a reusable read plan with typed relation includes.
  RivetFind<RelationalPosts, RelationalPostsRow> find({
    RivetWhere<RelationalPosts>? where,
    RivetOrderBy<RelationalPosts>? orderBy,
    int? limit,
    int? offset,
    RivetIncludes<RelationalPostsInclude>? include,
  }) {
    final schema = buildSchema();
    return RivetFind(
      schema,
      where: where,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
      includes: include?.call(RelationalPostsInclude(schema)) ?? const [],
    );
  }

  /// Creates a reusable insert plan.
  RivetInsert<RelationalPosts, RelationalPostsRow> insert(
    RelationalPostsCompanion companion, {
    RivetOnConflict<RelationalPosts>? onConflict,
  }) => RivetInsert(buildSchema(), companion, onConflict: onConflict);

  /// Creates a reusable batch insert plan.
  RivetInsertMany<RelationalPosts, RelationalPostsRow> insertMany(
    Iterable<RelationalPostsCompanion> companions, {
    RivetOnConflict<RelationalPosts>? onConflict,
  }) => RivetInsertMany(buildSchema(), companions, onConflict: onConflict);

  /// Creates a reusable update plan.
  RivetUpdate<RelationalPosts, RelationalPostsRow> update(
    RelationalPostsCompanion companion, {
    RivetWhere<RelationalPosts>? where,
  }) => RivetUpdate(buildSchema(), companion, where: where);

  /// Creates a reusable delete plan.
  RivetDelete<RelationalPosts, RelationalPostsRow> delete({
    RivetWhere<RelationalPosts>? where,
  }) => RivetDelete(buildSchema(), where: where);
}

/// Typed relation include scope for [RelationalComments].
final class RelationalCommentsInclude {
  /// Creates the generated include scope.
  const RelationalCommentsInclude(this._schema, {this.path = ''});

  final RivetTableSchema<RelationalComments, RelationalCommentsRow> _schema;

  /// Full relation path used in diagnostics.
  final String path;

  /// Includes the [post] relation.
  RivetInclude<RelationalPosts, RelationalPostsRow> post({
    RivetWhere<RelationalPosts>? where,

    RivetIncludes<RelationalPostsInclude>? include,
  }) {
    final target = RelationalPosts.db.buildSchema();

    final relationPath = path.isEmpty ? 'post' : '$path.post';
    return RivetInclude<RelationalPosts, RelationalPostsRow>(
      name: 'post',
      path: relationPath,
      relation: _schema.relations['post']!,
      targetSchema: target,

      where: where,

      includes:
          include?.call(RelationalPostsInclude(target, path: relationPath)) ??
          const [],
    );
  }
}

/// Generated row returned by reads from 'fbr146.relationalComments'.
final class RelationalCommentsRow {
  /// Creates a row from decoded column and relation values.
  const RelationalCommentsRow({
    required this.id,
    required this.postId,
    required this.body,
    this.post = const Relation.unloaded(),
  });

  /// Value read from `id`.
  final int id;

  /// Value read from `postId`.
  final int postId;

  /// Value read from `body`.
  final String body;

  /// Loaded or unloaded `post` relation.
  final Relation<RelationalPostsRow?> post;
}

/// Generated values accepted by mutations of 'fbr146.relationalComments'.
final class RelationalCommentsCompanion
    implements RivetCompanion<RelationalComments> {
  const RelationalCommentsCompanion._({
    required this.id,
    required this.postId,
    required this.body,
  });

  /// Creates values for an insert, leaving defaulted columns absent.
  factory RelationalCommentsCompanion.insert({
    required RivetValue<RelationalComments, int, int> id,
    required RivetValue<RelationalComments, int, int> postId,
    required RivetValue<RelationalComments, String, String> body,
  }) => RelationalCommentsCompanion._(id: id, postId: postId, body: body);

  /// Creates values for an update, leaving untouched columns absent.
  factory RelationalCommentsCompanion.update({
    RivetValue<RelationalComments, int, int> id = const RivetValue.absent(),
    RivetValue<RelationalComments, int, int> postId = const RivetValue.absent(),
    RivetValue<RelationalComments, String, String> body =
        const RivetValue.absent(),
  }) => RelationalCommentsCompanion._(id: id, postId: postId, body: body);

  /// Mutation value for `id`.
  final RivetValue<RelationalComments, int, int> id;

  /// Mutation value for `postId`.
  final RivetValue<RelationalComments, int, int> postId;

  /// Mutation value for `body`.
  final RivetValue<RelationalComments, String, String> body;

  /// The generated column assignments in declaration order.
  @override
  List<RivetAssignment<RelationalComments>> operator [](
    RivetCompanionKey key,
  ) => [
    RivetAssignment('id', id),
    RivetAssignment('postId', postId),
    RivetAssignment('body', body),
  ];
}

final class _$RelationalCommentsDB
    extends RivetTableAccessor<RelationalComments, RelationalCommentsRow> {
  const _$RelationalCommentsDB();

  @override
  RivetTableSchema<RelationalComments, RelationalCommentsRow> buildSchema() {
    RelationalComments createDefinition() {
      final definition = RelationalComments();

      return definition;
    }

    final definition = createDefinition();
    RelationalCommentsRow decodeRow(
      List<Object?> values,
      List<bool> sqlNulls,
      RivetRelationValues relations, {
      required bool transport,
    }) => RelationalCommentsRow(
      id: transport
          ? definition.id.decodeTransportValue(
              values[0],
              isSqlNull: sqlNulls[0],
            )
          : definition.id.decodeValue(values[0], isSqlNull: sqlNulls[0]),
      postId: transport
          ? definition.postId.decodeTransportValue(
              values[1],
              isSqlNull: sqlNulls[1],
            )
          : definition.postId.decodeValue(values[1], isSqlNull: sqlNulls[1]),
      body: transport
          ? definition.body.decodeTransportValue(
              values[2],
              isSqlNull: sqlNulls[2],
            )
          : definition.body.decodeValue(values[2], isSqlNull: sqlNulls[2]),
      post: relations.read('post'),
    );

    final builtSchema =
        RivetTableSchema<RelationalComments, RelationalCommentsRow>(
          schemaName: 'fbr146',
          tableName: 'relationalComments',
          definition: definition,
          columns: [
            definition.id as RivetColumn<Object?>,
            definition.postId as RivetColumn<Object?>,
            definition.body as RivetColumn<Object?>,
          ],
          columnNames: ['id', 'postId', 'body'],
          createDefinition: createDefinition,
          columnsFor: (definition) => [
            definition.id as RivetColumn<Object?>,
            definition.postId as RivetColumn<Object?>,
            definition.body as RivetColumn<Object?>,
          ],
          decode: (values, sqlNulls) => decodeRow(
            values,
            sqlNulls,
            const RivetRelationValues(),
            transport: false,
          ),
          decodeRelated: decodeRow,

          relations: {
            'post': definition.post as RivetRelationDescriptor<Object?>,
          },
        );
    definition.post.bind(
      name: 'post',
      ownerSchema: builtSchema,
      targetSchema: () => RelationalPosts.db.buildSchema(),
    );
    return builtSchema;
  }

  /// Creates a reusable read plan with typed relation includes.
  RivetFind<RelationalComments, RelationalCommentsRow> find({
    RivetWhere<RelationalComments>? where,
    RivetOrderBy<RelationalComments>? orderBy,
    int? limit,
    int? offset,
    RivetIncludes<RelationalCommentsInclude>? include,
  }) {
    final schema = buildSchema();
    return RivetFind(
      schema,
      where: where,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
      includes: include?.call(RelationalCommentsInclude(schema)) ?? const [],
    );
  }

  /// Creates a reusable insert plan.
  RivetInsert<RelationalComments, RelationalCommentsRow> insert(
    RelationalCommentsCompanion companion, {
    RivetOnConflict<RelationalComments>? onConflict,
  }) => RivetInsert(buildSchema(), companion, onConflict: onConflict);

  /// Creates a reusable batch insert plan.
  RivetInsertMany<RelationalComments, RelationalCommentsRow> insertMany(
    Iterable<RelationalCommentsCompanion> companions, {
    RivetOnConflict<RelationalComments>? onConflict,
  }) => RivetInsertMany(buildSchema(), companions, onConflict: onConflict);

  /// Creates a reusable update plan.
  RivetUpdate<RelationalComments, RelationalCommentsRow> update(
    RelationalCommentsCompanion companion, {
    RivetWhere<RelationalComments>? where,
  }) => RivetUpdate(buildSchema(), companion, where: where);

  /// Creates a reusable delete plan.
  RivetDelete<RelationalComments, RelationalCommentsRow> delete({
    RivetWhere<RelationalComments>? where,
  }) => RivetDelete(buildSchema(), where: where);
}

/// Typed relation include scope for [ThroughBooks].
final class ThroughBooksInclude {
  /// Creates the generated include scope.
  const ThroughBooksInclude(this._schema, {this.path = ''});

  final RivetTableSchema<ThroughBooks, ThroughBooksRow> _schema;

  /// Full relation path used in diagnostics.
  final String path;

  /// Includes the [tags] relation.
  RivetInclude<ThroughTags, ThroughTagsRow> tags({
    RivetWhere<ThroughTags>? where,
    RivetOrderBy<ThroughTags>? orderBy,
    int? limit,

    RivetIncludes<ThroughTagsInclude>? include,
  }) {
    final target = ThroughTags.db.buildSchema();
    final through = ThroughBookTags.db.buildSchema();

    final relationPath = path.isEmpty ? 'tags' : '$path.tags';
    return RivetInclude<ThroughTags, ThroughTagsRow>(
      name: 'tags',
      path: relationPath,
      relation: _schema.relations['tags']!,
      targetSchema: target,
      throughSchema: through,

      where: where,
      orderBy: orderBy,
      limit: limit,

      includes:
          include?.call(ThroughTagsInclude(target, path: relationPath)) ??
          const [],
    );
  }

  /// Includes the [reviews] relation.
  RivetInclude<ThroughReviews, ThroughReviewsRow> reviews({
    RivetWhere<ThroughReviews>? where,
    RivetOrderBy<ThroughReviews>? orderBy,
    int? limit,

    RivetIncludes<ThroughReviewsInclude>? include,
  }) {
    final target = ThroughReviews.db.buildSchema();

    final relationPath = path.isEmpty ? 'reviews' : '$path.reviews';
    return RivetInclude<ThroughReviews, ThroughReviewsRow>(
      name: 'reviews',
      path: relationPath,
      relation: _schema.relations['reviews']!,
      targetSchema: target,

      where: where,
      orderBy: orderBy,
      limit: limit,

      includes:
          include?.call(ThroughReviewsInclude(target, path: relationPath)) ??
          const [],
    );
  }
}

/// Generated row returned by reads from 'fbr147.throughBooks'.
final class ThroughBooksRow {
  /// Creates a row from decoded column and relation values.
  const ThroughBooksRow({
    required this.tenant,
    required this.id,
    required this.title,
    this.tags = const Relation.unloaded(),
    this.reviews = const Relation.unloaded(),
  });

  /// Value read from `tenant`.
  final int tenant;

  /// Value read from `id`.
  final int id;

  /// Value read from `title`.
  final String title;

  /// Loaded or unloaded `tags` relation.
  final Relation<List<ThroughTagsRow>> tags;

  /// Loaded or unloaded `reviews` relation.
  final Relation<List<ThroughReviewsRow>> reviews;
}

/// Generated values accepted by mutations of 'fbr147.throughBooks'.
final class ThroughBooksCompanion implements RivetCompanion<ThroughBooks> {
  const ThroughBooksCompanion._({
    required this.tenant,
    required this.id,
    required this.title,
  });

  /// Creates values for an insert, leaving defaulted columns absent.
  factory ThroughBooksCompanion.insert({
    required RivetValue<ThroughBooks, int, int> tenant,
    required RivetValue<ThroughBooks, int, int> id,
    required RivetValue<ThroughBooks, String, String> title,
  }) => ThroughBooksCompanion._(tenant: tenant, id: id, title: title);

  /// Creates values for an update, leaving untouched columns absent.
  factory ThroughBooksCompanion.update({
    RivetValue<ThroughBooks, int, int> tenant = const RivetValue.absent(),
    RivetValue<ThroughBooks, int, int> id = const RivetValue.absent(),
    RivetValue<ThroughBooks, String, String> title = const RivetValue.absent(),
  }) => ThroughBooksCompanion._(tenant: tenant, id: id, title: title);

  /// Mutation value for `tenant`.
  final RivetValue<ThroughBooks, int, int> tenant;

  /// Mutation value for `id`.
  final RivetValue<ThroughBooks, int, int> id;

  /// Mutation value for `title`.
  final RivetValue<ThroughBooks, String, String> title;

  /// The generated column assignments in declaration order.
  @override
  List<RivetAssignment<ThroughBooks>> operator [](RivetCompanionKey key) => [
    RivetAssignment('tenant', tenant),
    RivetAssignment('id', id),
    RivetAssignment('title', title),
  ];
}

final class _$ThroughBooksDB
    extends RivetTableAccessor<ThroughBooks, ThroughBooksRow> {
  const _$ThroughBooksDB();

  @override
  RivetTableSchema<ThroughBooks, ThroughBooksRow> buildSchema() {
    ThroughBooks createDefinition() {
      final definition = ThroughBooks();

      return definition;
    }

    final definition = createDefinition();
    ThroughBooksRow decodeRow(
      List<Object?> values,
      List<bool> sqlNulls,
      RivetRelationValues relations, {
      required bool transport,
    }) => ThroughBooksRow(
      tenant: transport
          ? definition.tenant.decodeTransportValue(
              values[0],
              isSqlNull: sqlNulls[0],
            )
          : definition.tenant.decodeValue(values[0], isSqlNull: sqlNulls[0]),
      id: transport
          ? definition.id.decodeTransportValue(
              values[1],
              isSqlNull: sqlNulls[1],
            )
          : definition.id.decodeValue(values[1], isSqlNull: sqlNulls[1]),
      title: transport
          ? definition.title.decodeTransportValue(
              values[2],
              isSqlNull: sqlNulls[2],
            )
          : definition.title.decodeValue(values[2], isSqlNull: sqlNulls[2]),
      tags: relations.read('tags'),
      reviews: relations.read('reviews'),
    );

    final builtSchema = RivetTableSchema<ThroughBooks, ThroughBooksRow>(
      schemaName: 'fbr147',
      tableName: 'throughBooks',
      definition: definition,
      columns: [
        definition.tenant as RivetColumn<Object?>,
        definition.id as RivetColumn<Object?>,
        definition.title as RivetColumn<Object?>,
      ],
      columnNames: ['tenant', 'id', 'title'],
      createDefinition: createDefinition,
      columnsFor: (definition) => [
        definition.tenant as RivetColumn<Object?>,
        definition.id as RivetColumn<Object?>,
        definition.title as RivetColumn<Object?>,
      ],
      decode: (values, sqlNulls) => decodeRow(
        values,
        sqlNulls,
        const RivetRelationValues(),
        transport: false,
      ),
      decodeRelated: decodeRow,

      relations: {
        'tags': definition.tags as RivetRelationDescriptor<Object?>,
        'reviews': definition.reviews as RivetRelationDescriptor<Object?>,
      },
    );
    definition.tags.bind(
      name: 'tags',
      ownerSchema: builtSchema,
      targetSchema: () => ThroughTags.db.buildSchema(),
      throughSchema: () => ThroughBookTags.db.buildSchema(),
    );
    definition.reviews.bind(
      name: 'reviews',
      ownerSchema: builtSchema,
      targetSchema: () => ThroughReviews.db.buildSchema(),
    );
    return builtSchema;
  }

  /// Creates a reusable read plan with typed relation includes.
  RivetFind<ThroughBooks, ThroughBooksRow> find({
    RivetWhere<ThroughBooks>? where,
    RivetOrderBy<ThroughBooks>? orderBy,
    int? limit,
    int? offset,
    RivetIncludes<ThroughBooksInclude>? include,
  }) {
    final schema = buildSchema();
    return RivetFind(
      schema,
      where: where,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
      includes: include?.call(ThroughBooksInclude(schema)) ?? const [],
    );
  }

  /// Creates a reusable insert plan.
  RivetInsert<ThroughBooks, ThroughBooksRow> insert(
    ThroughBooksCompanion companion, {
    RivetOnConflict<ThroughBooks>? onConflict,
  }) => RivetInsert(buildSchema(), companion, onConflict: onConflict);

  /// Creates a reusable batch insert plan.
  RivetInsertMany<ThroughBooks, ThroughBooksRow> insertMany(
    Iterable<ThroughBooksCompanion> companions, {
    RivetOnConflict<ThroughBooks>? onConflict,
  }) => RivetInsertMany(buildSchema(), companions, onConflict: onConflict);

  /// Creates a reusable update plan.
  RivetUpdate<ThroughBooks, ThroughBooksRow> update(
    ThroughBooksCompanion companion, {
    RivetWhere<ThroughBooks>? where,
  }) => RivetUpdate(buildSchema(), companion, where: where);

  /// Creates a reusable delete plan.
  RivetDelete<ThroughBooks, ThroughBooksRow> delete({
    RivetWhere<ThroughBooks>? where,
  }) => RivetDelete(buildSchema(), where: where);
}

/// Typed relation include scope for [ThroughTags].
final class ThroughTagsInclude {
  /// Creates the generated include scope.
  const ThroughTagsInclude(this._schema, {this.path = ''});

  final RivetTableSchema<ThroughTags, ThroughTagsRow> _schema;

  /// Full relation path used in diagnostics.
  final String path;

  /// Includes the [notes] relation.
  RivetInclude<ThroughTagNotes, ThroughTagNotesRow> notes({
    RivetWhere<ThroughTagNotes>? where,
    RivetOrderBy<ThroughTagNotes>? orderBy,
    int? limit,

    RivetIncludes<ThroughTagNotesInclude>? include,
  }) {
    final target = ThroughTagNotes.db.buildSchema();

    final relationPath = path.isEmpty ? 'notes' : '$path.notes';
    return RivetInclude<ThroughTagNotes, ThroughTagNotesRow>(
      name: 'notes',
      path: relationPath,
      relation: _schema.relations['notes']!,
      targetSchema: target,

      where: where,
      orderBy: orderBy,
      limit: limit,

      includes:
          include?.call(ThroughTagNotesInclude(target, path: relationPath)) ??
          const [],
    );
  }
}

/// Generated row returned by reads from 'fbr147.throughTags'.
final class ThroughTagsRow {
  /// Creates a row from decoded column and relation values.
  const ThroughTagsRow({
    required this.namespace,
    required this.code,
    required this.name,
    this.notes = const Relation.unloaded(),
  });

  /// Value read from `namespace`.
  final String namespace;

  /// Value read from `code`.
  final String code;

  /// Value read from `name`.
  final String name;

  /// Loaded or unloaded `notes` relation.
  final Relation<List<ThroughTagNotesRow>> notes;
}

/// Generated values accepted by mutations of 'fbr147.throughTags'.
final class ThroughTagsCompanion implements RivetCompanion<ThroughTags> {
  const ThroughTagsCompanion._({
    required this.namespace,
    required this.code,
    required this.name,
  });

  /// Creates values for an insert, leaving defaulted columns absent.
  factory ThroughTagsCompanion.insert({
    required RivetValue<ThroughTags, String, String> namespace,
    required RivetValue<ThroughTags, String, String> code,
    required RivetValue<ThroughTags, String, String> name,
  }) => ThroughTagsCompanion._(namespace: namespace, code: code, name: name);

  /// Creates values for an update, leaving untouched columns absent.
  factory ThroughTagsCompanion.update({
    RivetValue<ThroughTags, String, String> namespace =
        const RivetValue.absent(),
    RivetValue<ThroughTags, String, String> code = const RivetValue.absent(),
    RivetValue<ThroughTags, String, String> name = const RivetValue.absent(),
  }) => ThroughTagsCompanion._(namespace: namespace, code: code, name: name);

  /// Mutation value for `namespace`.
  final RivetValue<ThroughTags, String, String> namespace;

  /// Mutation value for `code`.
  final RivetValue<ThroughTags, String, String> code;

  /// Mutation value for `name`.
  final RivetValue<ThroughTags, String, String> name;

  /// The generated column assignments in declaration order.
  @override
  List<RivetAssignment<ThroughTags>> operator [](RivetCompanionKey key) => [
    RivetAssignment('namespace', namespace),
    RivetAssignment('code', code),
    RivetAssignment('name', name),
  ];
}

final class _$ThroughTagsDB
    extends RivetTableAccessor<ThroughTags, ThroughTagsRow> {
  const _$ThroughTagsDB();

  @override
  RivetTableSchema<ThroughTags, ThroughTagsRow> buildSchema() {
    ThroughTags createDefinition() {
      final definition = ThroughTags();

      return definition;
    }

    final definition = createDefinition();
    ThroughTagsRow decodeRow(
      List<Object?> values,
      List<bool> sqlNulls,
      RivetRelationValues relations, {
      required bool transport,
    }) => ThroughTagsRow(
      namespace: transport
          ? definition.namespace.decodeTransportValue(
              values[0],
              isSqlNull: sqlNulls[0],
            )
          : definition.namespace.decodeValue(values[0], isSqlNull: sqlNulls[0]),
      code: transport
          ? definition.code.decodeTransportValue(
              values[1],
              isSqlNull: sqlNulls[1],
            )
          : definition.code.decodeValue(values[1], isSqlNull: sqlNulls[1]),
      name: transport
          ? definition.name.decodeTransportValue(
              values[2],
              isSqlNull: sqlNulls[2],
            )
          : definition.name.decodeValue(values[2], isSqlNull: sqlNulls[2]),
      notes: relations.read('notes'),
    );

    final builtSchema = RivetTableSchema<ThroughTags, ThroughTagsRow>(
      schemaName: 'fbr147',
      tableName: 'throughTags',
      definition: definition,
      columns: [
        definition.namespace as RivetColumn<Object?>,
        definition.code as RivetColumn<Object?>,
        definition.name as RivetColumn<Object?>,
      ],
      columnNames: ['namespace', 'code', 'name'],
      createDefinition: createDefinition,
      columnsFor: (definition) => [
        definition.namespace as RivetColumn<Object?>,
        definition.code as RivetColumn<Object?>,
        definition.name as RivetColumn<Object?>,
      ],
      decode: (values, sqlNulls) => decodeRow(
        values,
        sqlNulls,
        const RivetRelationValues(),
        transport: false,
      ),
      decodeRelated: decodeRow,

      relations: {
        'notes': definition.notes as RivetRelationDescriptor<Object?>,
      },
    );
    definition.notes.bind(
      name: 'notes',
      ownerSchema: builtSchema,
      targetSchema: () => ThroughTagNotes.db.buildSchema(),
    );
    return builtSchema;
  }

  /// Creates a reusable read plan with typed relation includes.
  RivetFind<ThroughTags, ThroughTagsRow> find({
    RivetWhere<ThroughTags>? where,
    RivetOrderBy<ThroughTags>? orderBy,
    int? limit,
    int? offset,
    RivetIncludes<ThroughTagsInclude>? include,
  }) {
    final schema = buildSchema();
    return RivetFind(
      schema,
      where: where,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
      includes: include?.call(ThroughTagsInclude(schema)) ?? const [],
    );
  }

  /// Creates a reusable insert plan.
  RivetInsert<ThroughTags, ThroughTagsRow> insert(
    ThroughTagsCompanion companion, {
    RivetOnConflict<ThroughTags>? onConflict,
  }) => RivetInsert(buildSchema(), companion, onConflict: onConflict);

  /// Creates a reusable batch insert plan.
  RivetInsertMany<ThroughTags, ThroughTagsRow> insertMany(
    Iterable<ThroughTagsCompanion> companions, {
    RivetOnConflict<ThroughTags>? onConflict,
  }) => RivetInsertMany(buildSchema(), companions, onConflict: onConflict);

  /// Creates a reusable update plan.
  RivetUpdate<ThroughTags, ThroughTagsRow> update(
    ThroughTagsCompanion companion, {
    RivetWhere<ThroughTags>? where,
  }) => RivetUpdate(buildSchema(), companion, where: where);

  /// Creates a reusable delete plan.
  RivetDelete<ThroughTags, ThroughTagsRow> delete({
    RivetWhere<ThroughTags>? where,
  }) => RivetDelete(buildSchema(), where: where);
}

/// Typed relation include scope for [ThroughBookTags].
final class ThroughBookTagsInclude {
  /// Creates the generated include scope.
  const ThroughBookTagsInclude(this._schema, {this.path = ''});

  final RivetTableSchema<ThroughBookTags, ThroughBookTagRecord> _schema;

  /// Full relation path used in diagnostics.
  final String path;

  /// Includes the [book] relation.
  RivetInclude<ThroughBooks, ThroughBooksRow> book({
    RivetWhere<ThroughBooks>? where,

    RivetIncludes<ThroughBooksInclude>? include,
  }) {
    final target = ThroughBooks.db.buildSchema();

    final relationPath = path.isEmpty ? 'book' : '$path.book';
    return RivetInclude<ThroughBooks, ThroughBooksRow>(
      name: 'book',
      path: relationPath,
      relation: _schema.relations['book']!,
      targetSchema: target,

      where: where,

      includes:
          include?.call(ThroughBooksInclude(target, path: relationPath)) ??
          const [],
    );
  }

  /// Includes the [tag] relation.
  RivetInclude<ThroughTags, ThroughTagsRow> tag({
    RivetWhere<ThroughTags>? where,

    RivetIncludes<ThroughTagsInclude>? include,
  }) {
    final target = ThroughTags.db.buildSchema();

    final relationPath = path.isEmpty ? 'tag' : '$path.tag';
    return RivetInclude<ThroughTags, ThroughTagsRow>(
      name: 'tag',
      path: relationPath,
      relation: _schema.relations['tag']!,
      targetSchema: target,

      where: where,

      includes:
          include?.call(ThroughTagsInclude(target, path: relationPath)) ??
          const [],
    );
  }
}

/// Generated row returned by reads from 'fbr147.throughBookTags'.
final class ThroughBookTagRecord {
  /// Creates a row from decoded column and relation values.
  const ThroughBookTagRecord({
    required this.bookTenant,
    required this.bookId,
    required this.tagNamespace,
    required this.tagCode,
    required this.position,
    this.book = const Relation.unloaded(),
    this.tag = const Relation.unloaded(),
  });

  /// Value read from `bookTenant`.
  final int bookTenant;

  /// Value read from `bookId`.
  final int bookId;

  /// Value read from `tagNamespace`.
  final String tagNamespace;

  /// Value read from `tagCode`.
  final String tagCode;

  /// Value read from `position`.
  final int position;

  /// Loaded or unloaded `book` relation.
  final Relation<ThroughBooksRow?> book;

  /// Loaded or unloaded `tag` relation.
  final Relation<ThroughTagsRow?> tag;
}

/// Generated values accepted by mutations of 'fbr147.throughBookTags'.
final class ThroughBookTagsCompanion
    implements RivetCompanion<ThroughBookTags> {
  const ThroughBookTagsCompanion._({
    required this.bookTenant,
    required this.bookId,
    required this.tagNamespace,
    required this.tagCode,
    required this.position,
  });

  /// Creates values for an insert, leaving defaulted columns absent.
  factory ThroughBookTagsCompanion.insert({
    required RivetValue<ThroughBookTags, int, int> bookTenant,
    required RivetValue<ThroughBookTags, int, int> bookId,
    required RivetValue<ThroughBookTags, String, String> tagNamespace,
    required RivetValue<ThroughBookTags, String, String> tagCode,
    required RivetValue<ThroughBookTags, int, int> position,
  }) => ThroughBookTagsCompanion._(
    bookTenant: bookTenant,
    bookId: bookId,
    tagNamespace: tagNamespace,
    tagCode: tagCode,
    position: position,
  );

  /// Creates values for an update, leaving untouched columns absent.
  factory ThroughBookTagsCompanion.update({
    RivetValue<ThroughBookTags, int, int> bookTenant =
        const RivetValue.absent(),
    RivetValue<ThroughBookTags, int, int> bookId = const RivetValue.absent(),
    RivetValue<ThroughBookTags, String, String> tagNamespace =
        const RivetValue.absent(),
    RivetValue<ThroughBookTags, String, String> tagCode =
        const RivetValue.absent(),
    RivetValue<ThroughBookTags, int, int> position = const RivetValue.absent(),
  }) => ThroughBookTagsCompanion._(
    bookTenant: bookTenant,
    bookId: bookId,
    tagNamespace: tagNamespace,
    tagCode: tagCode,
    position: position,
  );

  /// Mutation value for `bookTenant`.
  final RivetValue<ThroughBookTags, int, int> bookTenant;

  /// Mutation value for `bookId`.
  final RivetValue<ThroughBookTags, int, int> bookId;

  /// Mutation value for `tagNamespace`.
  final RivetValue<ThroughBookTags, String, String> tagNamespace;

  /// Mutation value for `tagCode`.
  final RivetValue<ThroughBookTags, String, String> tagCode;

  /// Mutation value for `position`.
  final RivetValue<ThroughBookTags, int, int> position;

  /// The generated column assignments in declaration order.
  @override
  List<RivetAssignment<ThroughBookTags>> operator [](RivetCompanionKey key) => [
    RivetAssignment('bookTenant', bookTenant),
    RivetAssignment('bookId', bookId),
    RivetAssignment('tagNamespace', tagNamespace),
    RivetAssignment('tagCode', tagCode),
    RivetAssignment('position', position),
  ];
}

final class _$ThroughBookTagsDB
    extends RivetTableAccessor<ThroughBookTags, ThroughBookTagRecord> {
  const _$ThroughBookTagsDB();

  @override
  RivetTableSchema<ThroughBookTags, ThroughBookTagRecord> buildSchema() {
    ThroughBookTags createDefinition() {
      final definition = ThroughBookTags();

      return definition;
    }

    final definition = createDefinition();
    ThroughBookTagRecord decodeRow(
      List<Object?> values,
      List<bool> sqlNulls,
      RivetRelationValues relations, {
      required bool transport,
    }) => ThroughBookTagRecord(
      bookTenant: transport
          ? definition.bookTenant.decodeTransportValue(
              values[0],
              isSqlNull: sqlNulls[0],
            )
          : definition.bookTenant.decodeValue(
              values[0],
              isSqlNull: sqlNulls[0],
            ),
      bookId: transport
          ? definition.bookId.decodeTransportValue(
              values[1],
              isSqlNull: sqlNulls[1],
            )
          : definition.bookId.decodeValue(values[1], isSqlNull: sqlNulls[1]),
      tagNamespace: transport
          ? definition.tagNamespace.decodeTransportValue(
              values[2],
              isSqlNull: sqlNulls[2],
            )
          : definition.tagNamespace.decodeValue(
              values[2],
              isSqlNull: sqlNulls[2],
            ),
      tagCode: transport
          ? definition.tagCode.decodeTransportValue(
              values[3],
              isSqlNull: sqlNulls[3],
            )
          : definition.tagCode.decodeValue(values[3], isSqlNull: sqlNulls[3]),
      position: transport
          ? definition.position.decodeTransportValue(
              values[4],
              isSqlNull: sqlNulls[4],
            )
          : definition.position.decodeValue(values[4], isSqlNull: sqlNulls[4]),
      book: relations.read('book'),
      tag: relations.read('tag'),
    );

    final builtSchema = RivetTableSchema<ThroughBookTags, ThroughBookTagRecord>(
      schemaName: 'fbr147',
      tableName: 'throughBookTags',
      definition: definition,
      columns: [
        definition.bookTenant as RivetColumn<Object?>,
        definition.bookId as RivetColumn<Object?>,
        definition.tagNamespace as RivetColumn<Object?>,
        definition.tagCode as RivetColumn<Object?>,
        definition.position as RivetColumn<Object?>,
      ],
      columnNames: [
        'bookTenant',
        'bookId',
        'tagNamespace',
        'tagCode',
        'position',
      ],
      createDefinition: createDefinition,
      columnsFor: (definition) => [
        definition.bookTenant as RivetColumn<Object?>,
        definition.bookId as RivetColumn<Object?>,
        definition.tagNamespace as RivetColumn<Object?>,
        definition.tagCode as RivetColumn<Object?>,
        definition.position as RivetColumn<Object?>,
      ],
      decode: (values, sqlNulls) => decodeRow(
        values,
        sqlNulls,
        const RivetRelationValues(),
        transport: false,
      ),
      decodeRelated: decodeRow,

      relations: {
        'book': definition.book as RivetRelationDescriptor<Object?>,
        'tag': definition.tag as RivetRelationDescriptor<Object?>,
      },
    );
    definition.book.bind(
      name: 'book',
      ownerSchema: builtSchema,
      targetSchema: () => ThroughBooks.db.buildSchema(),
    );
    definition.tag.bind(
      name: 'tag',
      ownerSchema: builtSchema,
      targetSchema: () => ThroughTags.db.buildSchema(),
    );
    return builtSchema;
  }

  /// Creates a reusable read plan with typed relation includes.
  RivetFind<ThroughBookTags, ThroughBookTagRecord> find({
    RivetWhere<ThroughBookTags>? where,
    RivetOrderBy<ThroughBookTags>? orderBy,
    int? limit,
    int? offset,
    RivetIncludes<ThroughBookTagsInclude>? include,
  }) {
    final schema = buildSchema();
    return RivetFind(
      schema,
      where: where,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
      includes: include?.call(ThroughBookTagsInclude(schema)) ?? const [],
    );
  }

  /// Creates a reusable insert plan.
  RivetInsert<ThroughBookTags, ThroughBookTagRecord> insert(
    ThroughBookTagsCompanion companion, {
    RivetOnConflict<ThroughBookTags>? onConflict,
  }) => RivetInsert(buildSchema(), companion, onConflict: onConflict);

  /// Creates a reusable batch insert plan.
  RivetInsertMany<ThroughBookTags, ThroughBookTagRecord> insertMany(
    Iterable<ThroughBookTagsCompanion> companions, {
    RivetOnConflict<ThroughBookTags>? onConflict,
  }) => RivetInsertMany(buildSchema(), companions, onConflict: onConflict);

  /// Creates a reusable update plan.
  RivetUpdate<ThroughBookTags, ThroughBookTagRecord> update(
    ThroughBookTagsCompanion companion, {
    RivetWhere<ThroughBookTags>? where,
  }) => RivetUpdate(buildSchema(), companion, where: where);

  /// Creates a reusable delete plan.
  RivetDelete<ThroughBookTags, ThroughBookTagRecord> delete({
    RivetWhere<ThroughBookTags>? where,
  }) => RivetDelete(buildSchema(), where: where);
}

/// Typed relation include scope for [ThroughReviews].
final class ThroughReviewsInclude {
  /// Creates the generated include scope.
  const ThroughReviewsInclude(this._schema, {this.path = ''});

  final RivetTableSchema<ThroughReviews, ThroughReviewsRow> _schema;

  /// Full relation path used in diagnostics.
  final String path;

  /// Includes the [book] relation.
  RivetInclude<ThroughBooks, ThroughBooksRow> book({
    RivetWhere<ThroughBooks>? where,

    RivetIncludes<ThroughBooksInclude>? include,
  }) {
    final target = ThroughBooks.db.buildSchema();

    final relationPath = path.isEmpty ? 'book' : '$path.book';
    return RivetInclude<ThroughBooks, ThroughBooksRow>(
      name: 'book',
      path: relationPath,
      relation: _schema.relations['book']!,
      targetSchema: target,

      where: where,

      includes:
          include?.call(ThroughBooksInclude(target, path: relationPath)) ??
          const [],
    );
  }
}

/// Generated row returned by reads from 'fbr147.throughReviews'.
final class ThroughReviewsRow {
  /// Creates a row from decoded column and relation values.
  const ThroughReviewsRow({
    required this.id,
    required this.bookTenant,
    required this.bookId,
    required this.body,
    this.book = const Relation.unloaded(),
  });

  /// Value read from `id`.
  final int id;

  /// Value read from `bookTenant`.
  final int bookTenant;

  /// Value read from `bookId`.
  final int bookId;

  /// Value read from `body`.
  final String body;

  /// Loaded or unloaded `book` relation.
  final Relation<ThroughBooksRow?> book;
}

/// Generated values accepted by mutations of 'fbr147.throughReviews'.
final class ThroughReviewsCompanion implements RivetCompanion<ThroughReviews> {
  const ThroughReviewsCompanion._({
    required this.id,
    required this.bookTenant,
    required this.bookId,
    required this.body,
  });

  /// Creates values for an insert, leaving defaulted columns absent.
  factory ThroughReviewsCompanion.insert({
    required RivetValue<ThroughReviews, int, int> id,
    required RivetValue<ThroughReviews, int, int> bookTenant,
    required RivetValue<ThroughReviews, int, int> bookId,
    required RivetValue<ThroughReviews, String, String> body,
  }) => ThroughReviewsCompanion._(
    id: id,
    bookTenant: bookTenant,
    bookId: bookId,
    body: body,
  );

  /// Creates values for an update, leaving untouched columns absent.
  factory ThroughReviewsCompanion.update({
    RivetValue<ThroughReviews, int, int> id = const RivetValue.absent(),
    RivetValue<ThroughReviews, int, int> bookTenant = const RivetValue.absent(),
    RivetValue<ThroughReviews, int, int> bookId = const RivetValue.absent(),
    RivetValue<ThroughReviews, String, String> body = const RivetValue.absent(),
  }) => ThroughReviewsCompanion._(
    id: id,
    bookTenant: bookTenant,
    bookId: bookId,
    body: body,
  );

  /// Mutation value for `id`.
  final RivetValue<ThroughReviews, int, int> id;

  /// Mutation value for `bookTenant`.
  final RivetValue<ThroughReviews, int, int> bookTenant;

  /// Mutation value for `bookId`.
  final RivetValue<ThroughReviews, int, int> bookId;

  /// Mutation value for `body`.
  final RivetValue<ThroughReviews, String, String> body;

  /// The generated column assignments in declaration order.
  @override
  List<RivetAssignment<ThroughReviews>> operator [](RivetCompanionKey key) => [
    RivetAssignment('id', id),
    RivetAssignment('bookTenant', bookTenant),
    RivetAssignment('bookId', bookId),
    RivetAssignment('body', body),
  ];
}

final class _$ThroughReviewsDB
    extends RivetTableAccessor<ThroughReviews, ThroughReviewsRow> {
  const _$ThroughReviewsDB();

  @override
  RivetTableSchema<ThroughReviews, ThroughReviewsRow> buildSchema() {
    ThroughReviews createDefinition() {
      final definition = ThroughReviews();

      return definition;
    }

    final definition = createDefinition();
    ThroughReviewsRow decodeRow(
      List<Object?> values,
      List<bool> sqlNulls,
      RivetRelationValues relations, {
      required bool transport,
    }) => ThroughReviewsRow(
      id: transport
          ? definition.id.decodeTransportValue(
              values[0],
              isSqlNull: sqlNulls[0],
            )
          : definition.id.decodeValue(values[0], isSqlNull: sqlNulls[0]),
      bookTenant: transport
          ? definition.bookTenant.decodeTransportValue(
              values[1],
              isSqlNull: sqlNulls[1],
            )
          : definition.bookTenant.decodeValue(
              values[1],
              isSqlNull: sqlNulls[1],
            ),
      bookId: transport
          ? definition.bookId.decodeTransportValue(
              values[2],
              isSqlNull: sqlNulls[2],
            )
          : definition.bookId.decodeValue(values[2], isSqlNull: sqlNulls[2]),
      body: transport
          ? definition.body.decodeTransportValue(
              values[3],
              isSqlNull: sqlNulls[3],
            )
          : definition.body.decodeValue(values[3], isSqlNull: sqlNulls[3]),
      book: relations.read('book'),
    );

    final builtSchema = RivetTableSchema<ThroughReviews, ThroughReviewsRow>(
      schemaName: 'fbr147',
      tableName: 'throughReviews',
      definition: definition,
      columns: [
        definition.id as RivetColumn<Object?>,
        definition.bookTenant as RivetColumn<Object?>,
        definition.bookId as RivetColumn<Object?>,
        definition.body as RivetColumn<Object?>,
      ],
      columnNames: ['id', 'bookTenant', 'bookId', 'body'],
      createDefinition: createDefinition,
      columnsFor: (definition) => [
        definition.id as RivetColumn<Object?>,
        definition.bookTenant as RivetColumn<Object?>,
        definition.bookId as RivetColumn<Object?>,
        definition.body as RivetColumn<Object?>,
      ],
      decode: (values, sqlNulls) => decodeRow(
        values,
        sqlNulls,
        const RivetRelationValues(),
        transport: false,
      ),
      decodeRelated: decodeRow,

      relations: {'book': definition.book as RivetRelationDescriptor<Object?>},
    );
    definition.book.bind(
      name: 'book',
      ownerSchema: builtSchema,
      targetSchema: () => ThroughBooks.db.buildSchema(),
    );
    return builtSchema;
  }

  /// Creates a reusable read plan with typed relation includes.
  RivetFind<ThroughReviews, ThroughReviewsRow> find({
    RivetWhere<ThroughReviews>? where,
    RivetOrderBy<ThroughReviews>? orderBy,
    int? limit,
    int? offset,
    RivetIncludes<ThroughReviewsInclude>? include,
  }) {
    final schema = buildSchema();
    return RivetFind(
      schema,
      where: where,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
      includes: include?.call(ThroughReviewsInclude(schema)) ?? const [],
    );
  }

  /// Creates a reusable insert plan.
  RivetInsert<ThroughReviews, ThroughReviewsRow> insert(
    ThroughReviewsCompanion companion, {
    RivetOnConflict<ThroughReviews>? onConflict,
  }) => RivetInsert(buildSchema(), companion, onConflict: onConflict);

  /// Creates a reusable batch insert plan.
  RivetInsertMany<ThroughReviews, ThroughReviewsRow> insertMany(
    Iterable<ThroughReviewsCompanion> companions, {
    RivetOnConflict<ThroughReviews>? onConflict,
  }) => RivetInsertMany(buildSchema(), companions, onConflict: onConflict);

  /// Creates a reusable update plan.
  RivetUpdate<ThroughReviews, ThroughReviewsRow> update(
    ThroughReviewsCompanion companion, {
    RivetWhere<ThroughReviews>? where,
  }) => RivetUpdate(buildSchema(), companion, where: where);

  /// Creates a reusable delete plan.
  RivetDelete<ThroughReviews, ThroughReviewsRow> delete({
    RivetWhere<ThroughReviews>? where,
  }) => RivetDelete(buildSchema(), where: where);
}

/// Typed relation include scope for [ThroughTagNotes].
final class ThroughTagNotesInclude {
  /// Creates the generated include scope.
  const ThroughTagNotesInclude(this._schema, {this.path = ''});

  final RivetTableSchema<ThroughTagNotes, ThroughTagNotesRow> _schema;

  /// Full relation path used in diagnostics.
  final String path;

  /// Includes the [tag] relation.
  RivetInclude<ThroughTags, ThroughTagsRow> tag({
    RivetWhere<ThroughTags>? where,

    RivetIncludes<ThroughTagsInclude>? include,
  }) {
    final target = ThroughTags.db.buildSchema();

    final relationPath = path.isEmpty ? 'tag' : '$path.tag';
    return RivetInclude<ThroughTags, ThroughTagsRow>(
      name: 'tag',
      path: relationPath,
      relation: _schema.relations['tag']!,
      targetSchema: target,

      where: where,

      includes:
          include?.call(ThroughTagsInclude(target, path: relationPath)) ??
          const [],
    );
  }
}

/// Generated row returned by reads from 'fbr147.throughTagNotes'.
final class ThroughTagNotesRow {
  /// Creates a row from decoded column and relation values.
  const ThroughTagNotesRow({
    required this.id,
    required this.tagNamespace,
    required this.tagCode,
    required this.body,
    this.tag = const Relation.unloaded(),
  });

  /// Value read from `id`.
  final int id;

  /// Value read from `tagNamespace`.
  final String tagNamespace;

  /// Value read from `tagCode`.
  final String tagCode;

  /// Value read from `body`.
  final String body;

  /// Loaded or unloaded `tag` relation.
  final Relation<ThroughTagsRow?> tag;
}

/// Generated values accepted by mutations of 'fbr147.throughTagNotes'.
final class ThroughTagNotesCompanion
    implements RivetCompanion<ThroughTagNotes> {
  const ThroughTagNotesCompanion._({
    required this.id,
    required this.tagNamespace,
    required this.tagCode,
    required this.body,
  });

  /// Creates values for an insert, leaving defaulted columns absent.
  factory ThroughTagNotesCompanion.insert({
    required RivetValue<ThroughTagNotes, int, int> id,
    required RivetValue<ThroughTagNotes, String, String> tagNamespace,
    required RivetValue<ThroughTagNotes, String, String> tagCode,
    required RivetValue<ThroughTagNotes, String, String> body,
  }) => ThroughTagNotesCompanion._(
    id: id,
    tagNamespace: tagNamespace,
    tagCode: tagCode,
    body: body,
  );

  /// Creates values for an update, leaving untouched columns absent.
  factory ThroughTagNotesCompanion.update({
    RivetValue<ThroughTagNotes, int, int> id = const RivetValue.absent(),
    RivetValue<ThroughTagNotes, String, String> tagNamespace =
        const RivetValue.absent(),
    RivetValue<ThroughTagNotes, String, String> tagCode =
        const RivetValue.absent(),
    RivetValue<ThroughTagNotes, String, String> body =
        const RivetValue.absent(),
  }) => ThroughTagNotesCompanion._(
    id: id,
    tagNamespace: tagNamespace,
    tagCode: tagCode,
    body: body,
  );

  /// Mutation value for `id`.
  final RivetValue<ThroughTagNotes, int, int> id;

  /// Mutation value for `tagNamespace`.
  final RivetValue<ThroughTagNotes, String, String> tagNamespace;

  /// Mutation value for `tagCode`.
  final RivetValue<ThroughTagNotes, String, String> tagCode;

  /// Mutation value for `body`.
  final RivetValue<ThroughTagNotes, String, String> body;

  /// The generated column assignments in declaration order.
  @override
  List<RivetAssignment<ThroughTagNotes>> operator [](RivetCompanionKey key) => [
    RivetAssignment('id', id),
    RivetAssignment('tagNamespace', tagNamespace),
    RivetAssignment('tagCode', tagCode),
    RivetAssignment('body', body),
  ];
}

final class _$ThroughTagNotesDB
    extends RivetTableAccessor<ThroughTagNotes, ThroughTagNotesRow> {
  const _$ThroughTagNotesDB();

  @override
  RivetTableSchema<ThroughTagNotes, ThroughTagNotesRow> buildSchema() {
    ThroughTagNotes createDefinition() {
      final definition = ThroughTagNotes();

      return definition;
    }

    final definition = createDefinition();
    ThroughTagNotesRow decodeRow(
      List<Object?> values,
      List<bool> sqlNulls,
      RivetRelationValues relations, {
      required bool transport,
    }) => ThroughTagNotesRow(
      id: transport
          ? definition.id.decodeTransportValue(
              values[0],
              isSqlNull: sqlNulls[0],
            )
          : definition.id.decodeValue(values[0], isSqlNull: sqlNulls[0]),
      tagNamespace: transport
          ? definition.tagNamespace.decodeTransportValue(
              values[1],
              isSqlNull: sqlNulls[1],
            )
          : definition.tagNamespace.decodeValue(
              values[1],
              isSqlNull: sqlNulls[1],
            ),
      tagCode: transport
          ? definition.tagCode.decodeTransportValue(
              values[2],
              isSqlNull: sqlNulls[2],
            )
          : definition.tagCode.decodeValue(values[2], isSqlNull: sqlNulls[2]),
      body: transport
          ? definition.body.decodeTransportValue(
              values[3],
              isSqlNull: sqlNulls[3],
            )
          : definition.body.decodeValue(values[3], isSqlNull: sqlNulls[3]),
      tag: relations.read('tag'),
    );

    final builtSchema = RivetTableSchema<ThroughTagNotes, ThroughTagNotesRow>(
      schemaName: 'fbr147',
      tableName: 'throughTagNotes',
      definition: definition,
      columns: [
        definition.id as RivetColumn<Object?>,
        definition.tagNamespace as RivetColumn<Object?>,
        definition.tagCode as RivetColumn<Object?>,
        definition.body as RivetColumn<Object?>,
      ],
      columnNames: ['id', 'tagNamespace', 'tagCode', 'body'],
      createDefinition: createDefinition,
      columnsFor: (definition) => [
        definition.id as RivetColumn<Object?>,
        definition.tagNamespace as RivetColumn<Object?>,
        definition.tagCode as RivetColumn<Object?>,
        definition.body as RivetColumn<Object?>,
      ],
      decode: (values, sqlNulls) => decodeRow(
        values,
        sqlNulls,
        const RivetRelationValues(),
        transport: false,
      ),
      decodeRelated: decodeRow,

      relations: {'tag': definition.tag as RivetRelationDescriptor<Object?>},
    );
    definition.tag.bind(
      name: 'tag',
      ownerSchema: builtSchema,
      targetSchema: () => ThroughTags.db.buildSchema(),
    );
    return builtSchema;
  }

  /// Creates a reusable read plan with typed relation includes.
  RivetFind<ThroughTagNotes, ThroughTagNotesRow> find({
    RivetWhere<ThroughTagNotes>? where,
    RivetOrderBy<ThroughTagNotes>? orderBy,
    int? limit,
    int? offset,
    RivetIncludes<ThroughTagNotesInclude>? include,
  }) {
    final schema = buildSchema();
    return RivetFind(
      schema,
      where: where,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
      includes: include?.call(ThroughTagNotesInclude(schema)) ?? const [],
    );
  }

  /// Creates a reusable insert plan.
  RivetInsert<ThroughTagNotes, ThroughTagNotesRow> insert(
    ThroughTagNotesCompanion companion, {
    RivetOnConflict<ThroughTagNotes>? onConflict,
  }) => RivetInsert(buildSchema(), companion, onConflict: onConflict);

  /// Creates a reusable batch insert plan.
  RivetInsertMany<ThroughTagNotes, ThroughTagNotesRow> insertMany(
    Iterable<ThroughTagNotesCompanion> companions, {
    RivetOnConflict<ThroughTagNotes>? onConflict,
  }) => RivetInsertMany(buildSchema(), companions, onConflict: onConflict);

  /// Creates a reusable update plan.
  RivetUpdate<ThroughTagNotes, ThroughTagNotesRow> update(
    ThroughTagNotesCompanion companion, {
    RivetWhere<ThroughTagNotes>? where,
  }) => RivetUpdate(buildSchema(), companion, where: where);

  /// Creates a reusable delete plan.
  RivetDelete<ThroughTagNotes, ThroughTagNotesRow> delete({
    RivetWhere<ThroughTagNotes>? where,
  }) => RivetDelete(buildSchema(), where: where);
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

  /// Creates values for an update, leaving untouched columns absent.
  factory ScalarValuesCompanion.update({
    RivetValue<ScalarValues, String, String> id = const RivetValue.absent(),
    RivetValue<ScalarValues, int, int> count = const RivetValue.absent(),
    RivetValue<ScalarValues, double, double> score = const RivetValue.absent(),
    RivetValue<ScalarValues, bool, bool> active = const RivetValue.absent(),
    RivetValue<ScalarValues, DateTime, DateTime> createdAt =
        const RivetValue.absent(),
    RivetValue<ScalarValues, JsonValue, JsonValue> payload =
        const RivetValue.absent(),
    RivetValue<ScalarValues, Preferences, JsonValue> preferences =
        const RivetValue.absent(),
    RivetValue<ScalarValues, UserCode, String> code = const RivetValue.absent(),
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
  List<RivetAssignment<ScalarValues>> operator [](RivetCompanionKey key) => [
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
    ScalarValues createDefinition() {
      final definition = ScalarValues();

      return definition;
    }

    final definition = createDefinition();

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
      createDefinition: createDefinition,
      columnsFor: (definition) => [
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
    ScalarValuesCompanion companion, {
    RivetOnConflict<ScalarValues>? onConflict,
  }) => RivetInsert(buildSchema(), companion, onConflict: onConflict);

  /// Creates a reusable batch insert plan.
  RivetInsertMany<ScalarValues, ScalarValuesRow> insertMany(
    Iterable<ScalarValuesCompanion> companions, {
    RivetOnConflict<ScalarValues>? onConflict,
  }) => RivetInsertMany(buildSchema(), companions, onConflict: onConflict);

  /// Creates a reusable update plan.
  RivetUpdate<ScalarValues, ScalarValuesRow> update(
    ScalarValuesCompanion companion, {
    RivetWhere<ScalarValues>? where,
  }) => RivetUpdate(buildSchema(), companion, where: where);

  /// Creates a reusable delete plan.
  RivetDelete<ScalarValues, ScalarValuesRow> delete({
    RivetWhere<ScalarValues>? where,
  }) => RivetDelete(buildSchema(), where: where);
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

  /// Creates values for an update, leaving untouched columns absent.
  factory EnumValuesCompanion.update({
    RivetValue<EnumValues, WorkStatus, WorkStatus> status =
        const RivetValue.absent(),
    RivetValue<EnumValues, WorkStatus?, WorkStatus?> optionalStatus =
        const RivetValue.absent(),
    RivetValue<EnumValues, List<WorkStatus?>, List<WorkStatus?>>
        nullableStatuses =
        const RivetValue.absent(),
    RivetValue<EnumValues, List<WorkStatus>?, List<WorkStatus>?>
        optionalStatuses =
        const RivetValue.absent(),
    RivetValue<EnumValues, List<WorkStatus?>?, List<WorkStatus?>?>
        optionalNullableStatuses =
        const RivetValue.absent(),
    RivetValue<EnumValues, WorkState, WorkStatus> mappedStatus =
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
  List<RivetAssignment<EnumValues>> operator [](RivetCompanionKey key) => [
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
    EnumValues createDefinition() {
      final definition = EnumValues();
      definition.status.configureEnum(WorkStatusRivetEnum.codec);
      definition.optionalStatus.configureEnum(WorkStatusRivetEnum.codec);
      definition.nullableStatuses.configureEnum(WorkStatusRivetEnum.codec);
      definition.optionalStatuses.configureEnum(WorkStatusRivetEnum.codec);
      definition.optionalNullableStatuses.configureEnum(
        WorkStatusRivetEnum.codec,
      );
      definition.mappedStatus.configureEnum(WorkStatusRivetEnum.codec);
      return definition;
    }

    final definition = createDefinition();

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
      createDefinition: createDefinition,
      columnsFor: (definition) => [
        definition.status as RivetColumn<Object?>,
        definition.optionalStatus as RivetColumn<Object?>,
        definition.nullableStatuses as RivetColumn<Object?>,
        definition.optionalStatuses as RivetColumn<Object?>,
        definition.optionalNullableStatuses as RivetColumn<Object?>,
        definition.mappedStatus as RivetColumn<Object?>,
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
    EnumValuesCompanion companion, {
    RivetOnConflict<EnumValues>? onConflict,
  }) => RivetInsert(buildSchema(), companion, onConflict: onConflict);

  /// Creates a reusable batch insert plan.
  RivetInsertMany<EnumValues, EnumValuesRow> insertMany(
    Iterable<EnumValuesCompanion> companions, {
    RivetOnConflict<EnumValues>? onConflict,
  }) => RivetInsertMany(buildSchema(), companions, onConflict: onConflict);

  /// Creates a reusable update plan.
  RivetUpdate<EnumValues, EnumValuesRow> update(
    EnumValuesCompanion companion, {
    RivetWhere<EnumValues>? where,
  }) => RivetUpdate(buildSchema(), companion, where: where);

  /// Creates a reusable delete plan.
  RivetDelete<EnumValues, EnumValuesRow> delete({
    RivetWhere<EnumValues>? where,
  }) => RivetDelete(buildSchema(), where: where);
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

  /// Creates values for an update, leaving untouched columns absent.
  factory VectorValuesCompanion.update({
    RivetValue<VectorValues, Float32List, Float32List> embedding =
        const RivetValue.absent(),
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
  List<RivetAssignment<VectorValues>> operator [](RivetCompanionKey key) => [
    RivetAssignment('embedding', embedding),
    RivetAssignment('optionalEmbedding', optionalEmbedding),
  ];
}

final class _$VectorValuesDB
    extends RivetTableAccessor<VectorValues, VectorValuesRow> {
  const _$VectorValuesDB();

  @override
  RivetTableSchema<VectorValues, VectorValuesRow> buildSchema() {
    VectorValues createDefinition() {
      final definition = VectorValues();

      return definition;
    }

    final definition = createDefinition();

    return RivetTableSchema<VectorValues, VectorValuesRow>(
      schemaName: 'fbr121',
      tableName: 'vectorValues',
      definition: definition,
      columns: [
        definition.embedding as RivetColumn<Object?>,
        definition.optionalEmbedding as RivetColumn<Object?>,
      ],
      columnNames: ['embedding', 'optionalEmbedding'],
      createDefinition: createDefinition,
      columnsFor: (definition) => [
        definition.embedding as RivetColumn<Object?>,
        definition.optionalEmbedding as RivetColumn<Object?>,
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

  /// Creates a reusable insert plan.
  RivetInsert<VectorValues, VectorValuesRow> insert(
    VectorValuesCompanion companion, {
    RivetOnConflict<VectorValues>? onConflict,
  }) => RivetInsert(buildSchema(), companion, onConflict: onConflict);

  /// Creates a reusable batch insert plan.
  RivetInsertMany<VectorValues, VectorValuesRow> insertMany(
    Iterable<VectorValuesCompanion> companions, {
    RivetOnConflict<VectorValues>? onConflict,
  }) => RivetInsertMany(buildSchema(), companions, onConflict: onConflict);

  /// Creates a reusable update plan.
  RivetUpdate<VectorValues, VectorValuesRow> update(
    VectorValuesCompanion companion, {
    RivetWhere<VectorValues>? where,
  }) => RivetUpdate(buildSchema(), companion, where: where);

  /// Creates a reusable delete plan.
  RivetDelete<VectorValues, VectorValuesRow> delete({
    RivetWhere<VectorValues>? where,
  }) => RivetDelete(buildSchema(), where: where);
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

  /// Creates values for an update, leaving untouched columns absent.
  factory ArrayValuesCompanion.update({
    RivetValue<ArrayValues, List<int>, List<int>> ints =
        const RivetValue.absent(),
    RivetValue<ArrayValues, List<int?>, List<int?>> nullableInts =
        const RivetValue.absent(),
    RivetValue<ArrayValues, List<int>?, List<int>?> optionalInts =
        const RivetValue.absent(),
    RivetValue<ArrayValues, List<int?>?, List<int?>?> optionalNullableInts =
        const RivetValue.absent(),
    RivetValue<ArrayValues, List<JsonValue?>, List<JsonValue?>> jsonValues =
        const RivetValue.absent(),
    RivetValue<ArrayValues, List<Float32List>, List<Float32List>> vectors =
        const RivetValue.absent(),
    RivetValue<ArrayValues, List<WorkStatus>, List<WorkStatus>> statuses =
        const RivetValue.absent(),
    RivetValue<ArrayValues, List<UserCode?>, List<String?>> codes =
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
  List<RivetAssignment<ArrayValues>> operator [](RivetCompanionKey key) => [
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
    ArrayValues createDefinition() {
      final definition = ArrayValues();
      definition.statuses.configureEnum(WorkStatusRivetEnum.codec);
      return definition;
    }

    final definition = createDefinition();

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
      createDefinition: createDefinition,
      columnsFor: (definition) => [
        definition.ints as RivetColumn<Object?>,
        definition.nullableInts as RivetColumn<Object?>,
        definition.optionalInts as RivetColumn<Object?>,
        definition.optionalNullableInts as RivetColumn<Object?>,
        definition.jsonValues as RivetColumn<Object?>,
        definition.vectors as RivetColumn<Object?>,
        definition.statuses as RivetColumn<Object?>,
        definition.codes as RivetColumn<Object?>,
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
    ArrayValuesCompanion companion, {
    RivetOnConflict<ArrayValues>? onConflict,
  }) => RivetInsert(buildSchema(), companion, onConflict: onConflict);

  /// Creates a reusable batch insert plan.
  RivetInsertMany<ArrayValues, ArrayValuesRow> insertMany(
    Iterable<ArrayValuesCompanion> companions, {
    RivetOnConflict<ArrayValues>? onConflict,
  }) => RivetInsertMany(buildSchema(), companions, onConflict: onConflict);

  /// Creates a reusable update plan.
  RivetUpdate<ArrayValues, ArrayValuesRow> update(
    ArrayValuesCompanion companion, {
    RivetWhere<ArrayValues>? where,
  }) => RivetUpdate(buildSchema(), companion, where: where);

  /// Creates a reusable delete plan.
  RivetDelete<ArrayValues, ArrayValuesRow> delete({
    RivetWhere<ArrayValues>? where,
  }) => RivetDelete(buildSchema(), where: where);
}

/// Typed relation include scope for [CodecParents].
final class CodecParentsInclude {
  /// Creates the generated include scope.
  const CodecParentsInclude(this._schema, {this.path = ''});

  final RivetTableSchema<CodecParents, CodecParentsRow> _schema;

  /// Full relation path used in diagnostics.
  final String path;

  /// Includes the [values] relation.
  RivetInclude<CodecValues, CodecRecord> values({
    RivetWhere<CodecValues>? where,
    RivetOrderBy<CodecValues>? orderBy,
    int? limit,

    RivetIncludes<CodecValuesInclude>? include,
  }) {
    final target = CodecValues.db.buildSchema();

    final relationPath = path.isEmpty ? 'values' : '$path.values';
    return RivetInclude<CodecValues, CodecRecord>(
      name: 'values',
      path: relationPath,
      relation: _schema.relations['values']!,
      targetSchema: target,

      where: where,
      orderBy: orderBy,
      limit: limit,

      includes:
          include?.call(CodecValuesInclude(target, path: relationPath)) ??
          const [],
    );
  }

  /// Includes the [linkedValues] relation.
  RivetInclude<CodecValues, CodecRecord> linkedValues({
    RivetWhere<CodecValues>? where,
    RivetOrderBy<CodecValues>? orderBy,
    int? limit,

    RivetIncludes<CodecValuesInclude>? include,
  }) {
    final target = CodecValues.db.buildSchema();
    final through = CodecLinks.db.buildSchema();

    final relationPath = path.isEmpty ? 'linkedValues' : '$path.linkedValues';
    return RivetInclude<CodecValues, CodecRecord>(
      name: 'linkedValues',
      path: relationPath,
      relation: _schema.relations['linkedValues']!,
      targetSchema: target,
      throughSchema: through,

      where: where,
      orderBy: orderBy,
      limit: limit,

      includes:
          include?.call(CodecValuesInclude(target, path: relationPath)) ??
          const [],
    );
  }
}

/// Generated row returned by reads from 'fbr148.codecParents'.
final class CodecParentsRow {
  /// Creates a row from decoded column and relation values.
  const CodecParentsRow({
    required this.id,
    this.values = const Relation.unloaded(),
    this.linkedValues = const Relation.unloaded(),
  });

  /// Value read from `id`.
  final int id;

  /// Loaded or unloaded `values` relation.
  final Relation<List<CodecRecord>> values;

  /// Loaded or unloaded `linkedValues` relation.
  final Relation<List<CodecRecord>> linkedValues;
}

/// Generated values accepted by mutations of 'fbr148.codecParents'.
final class CodecParentsCompanion implements RivetCompanion<CodecParents> {
  const CodecParentsCompanion._({required this.id});

  /// Creates values for an insert, leaving defaulted columns absent.
  factory CodecParentsCompanion.insert({
    required RivetValue<CodecParents, int, int> id,
  }) => CodecParentsCompanion._(id: id);

  /// Creates values for an update, leaving untouched columns absent.
  factory CodecParentsCompanion.update({
    RivetValue<CodecParents, int, int> id = const RivetValue.absent(),
  }) => CodecParentsCompanion._(id: id);

  /// Mutation value for `id`.
  final RivetValue<CodecParents, int, int> id;

  /// The generated column assignments in declaration order.
  @override
  List<RivetAssignment<CodecParents>> operator [](RivetCompanionKey key) => [
    RivetAssignment('id', id),
  ];
}

final class _$CodecParentsDB
    extends RivetTableAccessor<CodecParents, CodecParentsRow> {
  const _$CodecParentsDB();

  @override
  RivetTableSchema<CodecParents, CodecParentsRow> buildSchema() {
    CodecParents createDefinition() {
      final definition = CodecParents();

      return definition;
    }

    final definition = createDefinition();
    CodecParentsRow decodeRow(
      List<Object?> values,
      List<bool> sqlNulls,
      RivetRelationValues relations, {
      required bool transport,
    }) => CodecParentsRow(
      id: transport
          ? definition.id.decodeTransportValue(
              values[0],
              isSqlNull: sqlNulls[0],
            )
          : definition.id.decodeValue(values[0], isSqlNull: sqlNulls[0]),
      values: relations.read('values'),
      linkedValues: relations.read('linkedValues'),
    );

    final builtSchema = RivetTableSchema<CodecParents, CodecParentsRow>(
      schemaName: 'fbr148',
      tableName: 'codecParents',
      definition: definition,
      columns: [definition.id as RivetColumn<Object?>],
      columnNames: ['id'],
      createDefinition: createDefinition,
      columnsFor: (definition) => [definition.id as RivetColumn<Object?>],
      decode: (values, sqlNulls) => decodeRow(
        values,
        sqlNulls,
        const RivetRelationValues(),
        transport: false,
      ),
      decodeRelated: decodeRow,

      relations: {
        'values': definition.values as RivetRelationDescriptor<Object?>,
        'linkedValues':
            definition.linkedValues as RivetRelationDescriptor<Object?>,
      },
    );
    definition.values.bind(
      name: 'values',
      ownerSchema: builtSchema,
      targetSchema: () => CodecValues.db.buildSchema(),
    );
    definition.linkedValues.bind(
      name: 'linkedValues',
      ownerSchema: builtSchema,
      targetSchema: () => CodecValues.db.buildSchema(),
      throughSchema: () => CodecLinks.db.buildSchema(),
    );
    return builtSchema;
  }

  /// Creates a reusable read plan with typed relation includes.
  RivetFind<CodecParents, CodecParentsRow> find({
    RivetWhere<CodecParents>? where,
    RivetOrderBy<CodecParents>? orderBy,
    int? limit,
    int? offset,
    RivetIncludes<CodecParentsInclude>? include,
  }) {
    final schema = buildSchema();
    return RivetFind(
      schema,
      where: where,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
      includes: include?.call(CodecParentsInclude(schema)) ?? const [],
    );
  }

  /// Creates a reusable insert plan.
  RivetInsert<CodecParents, CodecParentsRow> insert(
    CodecParentsCompanion companion, {
    RivetOnConflict<CodecParents>? onConflict,
  }) => RivetInsert(buildSchema(), companion, onConflict: onConflict);

  /// Creates a reusable batch insert plan.
  RivetInsertMany<CodecParents, CodecParentsRow> insertMany(
    Iterable<CodecParentsCompanion> companions, {
    RivetOnConflict<CodecParents>? onConflict,
  }) => RivetInsertMany(buildSchema(), companions, onConflict: onConflict);

  /// Creates a reusable update plan.
  RivetUpdate<CodecParents, CodecParentsRow> update(
    CodecParentsCompanion companion, {
    RivetWhere<CodecParents>? where,
  }) => RivetUpdate(buildSchema(), companion, where: where);

  /// Creates a reusable delete plan.
  RivetDelete<CodecParents, CodecParentsRow> delete({
    RivetWhere<CodecParents>? where,
  }) => RivetDelete(buildSchema(), where: where);
}

/// Typed relation include scope for [CodecValues].
final class CodecValuesInclude {
  /// Creates the generated include scope.
  const CodecValuesInclude(this._schema, {this.path = ''});

  final RivetTableSchema<CodecValues, CodecRecord> _schema;

  /// Full relation path used in diagnostics.
  final String path;

  /// Includes the [owner] relation.
  RivetInclude<CodecParents, CodecParentsRow> owner({
    RivetWhere<CodecParents>? where,

    RivetIncludes<CodecParentsInclude>? include,
  }) {
    final target = CodecParents.db.buildSchema();

    final relationPath = path.isEmpty ? 'owner' : '$path.owner';
    return RivetInclude<CodecParents, CodecParentsRow>(
      name: 'owner',
      path: relationPath,
      relation: _schema.relations['owner']!,
      targetSchema: target,

      where: where,

      includes:
          include?.call(CodecParentsInclude(target, path: relationPath)) ??
          const [],
    );
  }
}

/// Generated row returned by reads from 'fbr148.codecValues'.
final class CodecRecord {
  /// Creates a row from decoded column and relation values.
  const CodecRecord({
    required this.id,
    required this.ownerId,
    required this.payload,
    required this.happenedAt,
    required this.status,
    required this.embedding,
    required this.ints,
    required this.optionalInts,
    required this.nullableInts,
    required this.jsonValues,
    required this.vectors,
    required this.statuses,
    required this.codes,
    this.owner = const Relation.unloaded(),
  });

  /// Value read from `id`.
  final int id;

  /// Value read from `ownerId`.
  final int ownerId;

  /// Value read from `payload`.
  final JsonValue payload;

  /// Value read from `happenedAt`.
  final DateTime happenedAt;

  /// Value read from `status`.
  final WorkStatus status;

  /// Value read from `embedding`.
  final Float32List embedding;

  /// Value read from `ints`.
  final List<int> ints;

  /// Value read from `optionalInts`.
  final List<int>? optionalInts;

  /// Value read from `nullableInts`.
  final List<int?> nullableInts;

  /// Value read from `jsonValues`.
  final List<JsonValue?> jsonValues;

  /// Value read from `vectors`.
  final List<Float32List> vectors;

  /// Value read from `statuses`.
  final List<WorkStatus> statuses;

  /// Value read from `codes`.
  final List<UserCode?> codes;

  /// Loaded or unloaded `owner` relation.
  final Relation<CodecParentsRow?> owner;
}

/// Generated values accepted by mutations of 'fbr148.codecValues'.
final class CodecValuesCompanion implements RivetCompanion<CodecValues> {
  const CodecValuesCompanion._({
    required this.id,
    required this.ownerId,
    required this.payload,
    required this.happenedAt,
    required this.status,
    required this.embedding,
    required this.ints,
    required this.optionalInts,
    required this.nullableInts,
    required this.jsonValues,
    required this.vectors,
    required this.statuses,
    required this.codes,
  });

  /// Creates values for an insert, leaving defaulted columns absent.
  factory CodecValuesCompanion.insert({
    required RivetValue<CodecValues, int, int> id,
    required RivetValue<CodecValues, int, int> ownerId,
    required RivetValue<CodecValues, JsonValue, JsonValue> payload,
    required RivetValue<CodecValues, DateTime, DateTime> happenedAt,
    required RivetValue<CodecValues, WorkStatus, WorkStatus> status,
    required RivetValue<CodecValues, Float32List, Float32List> embedding,
    required RivetValue<CodecValues, List<int>, List<int>> ints,
    required RivetValue<CodecValues, List<int?>, List<int?>> nullableInts,
    required RivetValue<CodecValues, List<JsonValue?>, List<JsonValue?>>
    jsonValues,
    required RivetValue<CodecValues, List<Float32List>, List<Float32List>>
    vectors,
    required RivetValue<CodecValues, List<WorkStatus>, List<WorkStatus>>
    statuses,
    required RivetValue<CodecValues, List<UserCode?>, List<String?>> codes,
    RivetValue<CodecValues, List<int>?, List<int>?> optionalInts =
        const RivetValue.absent(),
  }) => CodecValuesCompanion._(
    id: id,
    ownerId: ownerId,
    payload: payload,
    happenedAt: happenedAt,
    status: status,
    embedding: embedding,
    ints: ints,
    optionalInts: optionalInts,
    nullableInts: nullableInts,
    jsonValues: jsonValues,
    vectors: vectors,
    statuses: statuses,
    codes: codes,
  );

  /// Creates values for an update, leaving untouched columns absent.
  factory CodecValuesCompanion.update({
    RivetValue<CodecValues, int, int> id = const RivetValue.absent(),
    RivetValue<CodecValues, int, int> ownerId = const RivetValue.absent(),
    RivetValue<CodecValues, JsonValue, JsonValue> payload =
        const RivetValue.absent(),
    RivetValue<CodecValues, DateTime, DateTime> happenedAt =
        const RivetValue.absent(),
    RivetValue<CodecValues, WorkStatus, WorkStatus> status =
        const RivetValue.absent(),
    RivetValue<CodecValues, Float32List, Float32List> embedding =
        const RivetValue.absent(),
    RivetValue<CodecValues, List<int>, List<int>> ints =
        const RivetValue.absent(),
    RivetValue<CodecValues, List<int>?, List<int>?> optionalInts =
        const RivetValue.absent(),
    RivetValue<CodecValues, List<int?>, List<int?>> nullableInts =
        const RivetValue.absent(),
    RivetValue<CodecValues, List<JsonValue?>, List<JsonValue?>> jsonValues =
        const RivetValue.absent(),
    RivetValue<CodecValues, List<Float32List>, List<Float32List>> vectors =
        const RivetValue.absent(),
    RivetValue<CodecValues, List<WorkStatus>, List<WorkStatus>> statuses =
        const RivetValue.absent(),
    RivetValue<CodecValues, List<UserCode?>, List<String?>> codes =
        const RivetValue.absent(),
  }) => CodecValuesCompanion._(
    id: id,
    ownerId: ownerId,
    payload: payload,
    happenedAt: happenedAt,
    status: status,
    embedding: embedding,
    ints: ints,
    optionalInts: optionalInts,
    nullableInts: nullableInts,
    jsonValues: jsonValues,
    vectors: vectors,
    statuses: statuses,
    codes: codes,
  );

  /// Mutation value for `id`.
  final RivetValue<CodecValues, int, int> id;

  /// Mutation value for `ownerId`.
  final RivetValue<CodecValues, int, int> ownerId;

  /// Mutation value for `payload`.
  final RivetValue<CodecValues, JsonValue, JsonValue> payload;

  /// Mutation value for `happenedAt`.
  final RivetValue<CodecValues, DateTime, DateTime> happenedAt;

  /// Mutation value for `status`.
  final RivetValue<CodecValues, WorkStatus, WorkStatus> status;

  /// Mutation value for `embedding`.
  final RivetValue<CodecValues, Float32List, Float32List> embedding;

  /// Mutation value for `ints`.
  final RivetValue<CodecValues, List<int>, List<int>> ints;

  /// Mutation value for `optionalInts`.
  final RivetValue<CodecValues, List<int>?, List<int>?> optionalInts;

  /// Mutation value for `nullableInts`.
  final RivetValue<CodecValues, List<int?>, List<int?>> nullableInts;

  /// Mutation value for `jsonValues`.
  final RivetValue<CodecValues, List<JsonValue?>, List<JsonValue?>> jsonValues;

  /// Mutation value for `vectors`.
  final RivetValue<CodecValues, List<Float32List>, List<Float32List>> vectors;

  /// Mutation value for `statuses`.
  final RivetValue<CodecValues, List<WorkStatus>, List<WorkStatus>> statuses;

  /// Mutation value for `codes`.
  final RivetValue<CodecValues, List<UserCode?>, List<String?>> codes;

  /// The generated column assignments in declaration order.
  @override
  List<RivetAssignment<CodecValues>> operator [](RivetCompanionKey key) => [
    RivetAssignment('id', id),
    RivetAssignment('ownerId', ownerId),
    RivetAssignment('payload', payload),
    RivetAssignment('happenedAt', happenedAt),
    RivetAssignment('status', status),
    RivetAssignment('embedding', embedding),
    RivetAssignment('ints', ints),
    RivetAssignment('optionalInts', optionalInts),
    RivetAssignment('nullableInts', nullableInts),
    RivetAssignment('jsonValues', jsonValues),
    RivetAssignment('vectors', vectors),
    RivetAssignment('statuses', statuses),
    RivetAssignment('codes', codes),
  ];
}

final class _$CodecValuesDB
    extends RivetTableAccessor<CodecValues, CodecRecord> {
  const _$CodecValuesDB();

  @override
  RivetTableSchema<CodecValues, CodecRecord> buildSchema() {
    CodecValues createDefinition() {
      final definition = CodecValues();
      definition.status.configureEnum(WorkStatusRivetEnum.codec);
      definition.statuses.configureEnum(WorkStatusRivetEnum.codec);
      return definition;
    }

    final definition = createDefinition();
    CodecRecord decodeRow(
      List<Object?> values,
      List<bool> sqlNulls,
      RivetRelationValues relations, {
      required bool transport,
    }) => CodecRecord(
      id: transport
          ? definition.id.decodeTransportValue(
              values[0],
              isSqlNull: sqlNulls[0],
            )
          : definition.id.decodeValue(values[0], isSqlNull: sqlNulls[0]),
      ownerId: transport
          ? definition.ownerId.decodeTransportValue(
              values[1],
              isSqlNull: sqlNulls[1],
            )
          : definition.ownerId.decodeValue(values[1], isSqlNull: sqlNulls[1]),
      payload: transport
          ? definition.payload.decodeTransportValue(
              values[2],
              isSqlNull: sqlNulls[2],
            )
          : definition.payload.decodeValue(values[2], isSqlNull: sqlNulls[2]),
      happenedAt: transport
          ? definition.happenedAt.decodeTransportValue(
              values[3],
              isSqlNull: sqlNulls[3],
            )
          : definition.happenedAt.decodeValue(
              values[3],
              isSqlNull: sqlNulls[3],
            ),
      status: transport
          ? definition.status.decodeTransportValue(
              values[4],
              isSqlNull: sqlNulls[4],
            )
          : definition.status.decodeValue(values[4], isSqlNull: sqlNulls[4]),
      embedding: transport
          ? definition.embedding.decodeTransportValue(
              values[5],
              isSqlNull: sqlNulls[5],
            )
          : definition.embedding.decodeValue(values[5], isSqlNull: sqlNulls[5]),
      ints: transport
          ? definition.ints.decodeTransportValue(
              values[6],
              isSqlNull: sqlNulls[6],
            )
          : definition.ints.decodeValue(values[6], isSqlNull: sqlNulls[6]),
      optionalInts: transport
          ? definition.optionalInts.decodeTransportValue(
              values[7],
              isSqlNull: sqlNulls[7],
            )
          : definition.optionalInts.decodeValue(
              values[7],
              isSqlNull: sqlNulls[7],
            ),
      nullableInts: transport
          ? definition.nullableInts.decodeTransportValue(
              values[8],
              isSqlNull: sqlNulls[8],
            )
          : definition.nullableInts.decodeValue(
              values[8],
              isSqlNull: sqlNulls[8],
            ),
      jsonValues: transport
          ? definition.jsonValues.decodeTransportValue(
              values[9],
              isSqlNull: sqlNulls[9],
            )
          : definition.jsonValues.decodeValue(
              values[9],
              isSqlNull: sqlNulls[9],
            ),
      vectors: transport
          ? definition.vectors.decodeTransportValue(
              values[10],
              isSqlNull: sqlNulls[10],
            )
          : definition.vectors.decodeValue(values[10], isSqlNull: sqlNulls[10]),
      statuses: transport
          ? definition.statuses.decodeTransportValue(
              values[11],
              isSqlNull: sqlNulls[11],
            )
          : definition.statuses.decodeValue(
              values[11],
              isSqlNull: sqlNulls[11],
            ),
      codes: transport
          ? definition.codes.decodeTransportValue(
              values[12],
              isSqlNull: sqlNulls[12],
            )
          : definition.codes.decodeValue(values[12], isSqlNull: sqlNulls[12]),
      owner: relations.read('owner'),
    );

    final builtSchema = RivetTableSchema<CodecValues, CodecRecord>(
      schemaName: 'fbr148',
      tableName: 'codecValues',
      definition: definition,
      columns: [
        definition.id as RivetColumn<Object?>,
        definition.ownerId as RivetColumn<Object?>,
        definition.payload as RivetColumn<Object?>,
        definition.happenedAt as RivetColumn<Object?>,
        definition.status as RivetColumn<Object?>,
        definition.embedding as RivetColumn<Object?>,
        definition.ints as RivetColumn<Object?>,
        definition.optionalInts as RivetColumn<Object?>,
        definition.nullableInts as RivetColumn<Object?>,
        definition.jsonValues as RivetColumn<Object?>,
        definition.vectors as RivetColumn<Object?>,
        definition.statuses as RivetColumn<Object?>,
        definition.codes as RivetColumn<Object?>,
      ],
      columnNames: [
        'id',
        'ownerId',
        'payload',
        'happenedAt',
        'status',
        'embedding',
        'ints',
        'optionalInts',
        'nullableInts',
        'jsonValues',
        'vectors',
        'statuses',
        'codes',
      ],
      createDefinition: createDefinition,
      columnsFor: (definition) => [
        definition.id as RivetColumn<Object?>,
        definition.ownerId as RivetColumn<Object?>,
        definition.payload as RivetColumn<Object?>,
        definition.happenedAt as RivetColumn<Object?>,
        definition.status as RivetColumn<Object?>,
        definition.embedding as RivetColumn<Object?>,
        definition.ints as RivetColumn<Object?>,
        definition.optionalInts as RivetColumn<Object?>,
        definition.nullableInts as RivetColumn<Object?>,
        definition.jsonValues as RivetColumn<Object?>,
        definition.vectors as RivetColumn<Object?>,
        definition.statuses as RivetColumn<Object?>,
        definition.codes as RivetColumn<Object?>,
      ],
      decode: (values, sqlNulls) => decodeRow(
        values,
        sqlNulls,
        const RivetRelationValues(),
        transport: false,
      ),
      decodeRelated: decodeRow,

      relations: {
        'owner': definition.owner as RivetRelationDescriptor<Object?>,
      },
    );
    definition.owner.bind(
      name: 'owner',
      ownerSchema: builtSchema,
      targetSchema: () => CodecParents.db.buildSchema(),
    );
    return builtSchema;
  }

  /// Creates a reusable read plan with typed relation includes.
  RivetFind<CodecValues, CodecRecord> find({
    RivetWhere<CodecValues>? where,
    RivetOrderBy<CodecValues>? orderBy,
    int? limit,
    int? offset,
    RivetIncludes<CodecValuesInclude>? include,
  }) {
    final schema = buildSchema();
    return RivetFind(
      schema,
      where: where,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
      includes: include?.call(CodecValuesInclude(schema)) ?? const [],
    );
  }

  /// Creates a reusable insert plan.
  RivetInsert<CodecValues, CodecRecord> insert(
    CodecValuesCompanion companion, {
    RivetOnConflict<CodecValues>? onConflict,
  }) => RivetInsert(buildSchema(), companion, onConflict: onConflict);

  /// Creates a reusable batch insert plan.
  RivetInsertMany<CodecValues, CodecRecord> insertMany(
    Iterable<CodecValuesCompanion> companions, {
    RivetOnConflict<CodecValues>? onConflict,
  }) => RivetInsertMany(buildSchema(), companions, onConflict: onConflict);

  /// Creates a reusable update plan.
  RivetUpdate<CodecValues, CodecRecord> update(
    CodecValuesCompanion companion, {
    RivetWhere<CodecValues>? where,
  }) => RivetUpdate(buildSchema(), companion, where: where);

  /// Creates a reusable delete plan.
  RivetDelete<CodecValues, CodecRecord> delete({
    RivetWhere<CodecValues>? where,
  }) => RivetDelete(buildSchema(), where: where);
}

/// Typed relation include scope for [CodecLinks].
final class CodecLinksInclude {
  /// Creates the generated include scope.
  const CodecLinksInclude(this._schema, {this.path = ''});

  final RivetTableSchema<CodecLinks, CodecLinksRow> _schema;

  /// Full relation path used in diagnostics.
  final String path;

  /// Includes the [owner] relation.
  RivetInclude<CodecParents, CodecParentsRow> owner({
    RivetWhere<CodecParents>? where,

    RivetIncludes<CodecParentsInclude>? include,
  }) {
    final target = CodecParents.db.buildSchema();

    final relationPath = path.isEmpty ? 'owner' : '$path.owner';
    return RivetInclude<CodecParents, CodecParentsRow>(
      name: 'owner',
      path: relationPath,
      relation: _schema.relations['owner']!,
      targetSchema: target,

      where: where,

      includes:
          include?.call(CodecParentsInclude(target, path: relationPath)) ??
          const [],
    );
  }

  /// Includes the [value] relation.
  RivetInclude<CodecValues, CodecRecord> value({
    RivetWhere<CodecValues>? where,

    RivetIncludes<CodecValuesInclude>? include,
  }) {
    final target = CodecValues.db.buildSchema();

    final relationPath = path.isEmpty ? 'value' : '$path.value';
    return RivetInclude<CodecValues, CodecRecord>(
      name: 'value',
      path: relationPath,
      relation: _schema.relations['value']!,
      targetSchema: target,

      where: where,

      includes:
          include?.call(CodecValuesInclude(target, path: relationPath)) ??
          const [],
    );
  }
}

/// Generated row returned by reads from 'fbr148.codecLinks'.
final class CodecLinksRow {
  /// Creates a row from decoded column and relation values.
  const CodecLinksRow({
    required this.ownerId,
    required this.valueId,
    this.owner = const Relation.unloaded(),
    this.value = const Relation.unloaded(),
  });

  /// Value read from `ownerId`.
  final int ownerId;

  /// Value read from `valueId`.
  final int valueId;

  /// Loaded or unloaded `owner` relation.
  final Relation<CodecParentsRow?> owner;

  /// Loaded or unloaded `value` relation.
  final Relation<CodecRecord?> value;
}

/// Generated values accepted by mutations of 'fbr148.codecLinks'.
final class CodecLinksCompanion implements RivetCompanion<CodecLinks> {
  const CodecLinksCompanion._({required this.ownerId, required this.valueId});

  /// Creates values for an insert, leaving defaulted columns absent.
  factory CodecLinksCompanion.insert({
    required RivetValue<CodecLinks, int, int> ownerId,
    required RivetValue<CodecLinks, int, int> valueId,
  }) => CodecLinksCompanion._(ownerId: ownerId, valueId: valueId);

  /// Creates values for an update, leaving untouched columns absent.
  factory CodecLinksCompanion.update({
    RivetValue<CodecLinks, int, int> ownerId = const RivetValue.absent(),
    RivetValue<CodecLinks, int, int> valueId = const RivetValue.absent(),
  }) => CodecLinksCompanion._(ownerId: ownerId, valueId: valueId);

  /// Mutation value for `ownerId`.
  final RivetValue<CodecLinks, int, int> ownerId;

  /// Mutation value for `valueId`.
  final RivetValue<CodecLinks, int, int> valueId;

  /// The generated column assignments in declaration order.
  @override
  List<RivetAssignment<CodecLinks>> operator [](RivetCompanionKey key) => [
    RivetAssignment('ownerId', ownerId),
    RivetAssignment('valueId', valueId),
  ];
}

final class _$CodecLinksDB
    extends RivetTableAccessor<CodecLinks, CodecLinksRow> {
  const _$CodecLinksDB();

  @override
  RivetTableSchema<CodecLinks, CodecLinksRow> buildSchema() {
    CodecLinks createDefinition() {
      final definition = CodecLinks();

      return definition;
    }

    final definition = createDefinition();
    CodecLinksRow decodeRow(
      List<Object?> values,
      List<bool> sqlNulls,
      RivetRelationValues relations, {
      required bool transport,
    }) => CodecLinksRow(
      ownerId: transport
          ? definition.ownerId.decodeTransportValue(
              values[0],
              isSqlNull: sqlNulls[0],
            )
          : definition.ownerId.decodeValue(values[0], isSqlNull: sqlNulls[0]),
      valueId: transport
          ? definition.valueId.decodeTransportValue(
              values[1],
              isSqlNull: sqlNulls[1],
            )
          : definition.valueId.decodeValue(values[1], isSqlNull: sqlNulls[1]),
      owner: relations.read('owner'),
      value: relations.read('value'),
    );

    final builtSchema = RivetTableSchema<CodecLinks, CodecLinksRow>(
      schemaName: 'fbr148',
      tableName: 'codecLinks',
      definition: definition,
      columns: [
        definition.ownerId as RivetColumn<Object?>,
        definition.valueId as RivetColumn<Object?>,
      ],
      columnNames: ['ownerId', 'valueId'],
      createDefinition: createDefinition,
      columnsFor: (definition) => [
        definition.ownerId as RivetColumn<Object?>,
        definition.valueId as RivetColumn<Object?>,
      ],
      decode: (values, sqlNulls) => decodeRow(
        values,
        sqlNulls,
        const RivetRelationValues(),
        transport: false,
      ),
      decodeRelated: decodeRow,

      relations: {
        'owner': definition.owner as RivetRelationDescriptor<Object?>,
        'value': definition.value as RivetRelationDescriptor<Object?>,
      },
    );
    definition.owner.bind(
      name: 'owner',
      ownerSchema: builtSchema,
      targetSchema: () => CodecParents.db.buildSchema(),
    );
    definition.value.bind(
      name: 'value',
      ownerSchema: builtSchema,
      targetSchema: () => CodecValues.db.buildSchema(),
    );
    return builtSchema;
  }

  /// Creates a reusable read plan with typed relation includes.
  RivetFind<CodecLinks, CodecLinksRow> find({
    RivetWhere<CodecLinks>? where,
    RivetOrderBy<CodecLinks>? orderBy,
    int? limit,
    int? offset,
    RivetIncludes<CodecLinksInclude>? include,
  }) {
    final schema = buildSchema();
    return RivetFind(
      schema,
      where: where,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
      includes: include?.call(CodecLinksInclude(schema)) ?? const [],
    );
  }

  /// Creates a reusable insert plan.
  RivetInsert<CodecLinks, CodecLinksRow> insert(
    CodecLinksCompanion companion, {
    RivetOnConflict<CodecLinks>? onConflict,
  }) => RivetInsert(buildSchema(), companion, onConflict: onConflict);

  /// Creates a reusable batch insert plan.
  RivetInsertMany<CodecLinks, CodecLinksRow> insertMany(
    Iterable<CodecLinksCompanion> companions, {
    RivetOnConflict<CodecLinks>? onConflict,
  }) => RivetInsertMany(buildSchema(), companions, onConflict: onConflict);

  /// Creates a reusable update plan.
  RivetUpdate<CodecLinks, CodecLinksRow> update(
    CodecLinksCompanion companion, {
    RivetWhere<CodecLinks>? where,
  }) => RivetUpdate(buildSchema(), companion, where: where);

  /// Creates a reusable delete plan.
  RivetDelete<CodecLinks, CodecLinksRow> delete({
    RivetWhere<CodecLinks>? where,
  }) => RivetDelete(buildSchema(), where: where);
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

  /// Creates values for an update, leaving untouched columns absent.
  factory MalformedArraysCompanion.update({
    RivetValue<MalformedArrays, List<int>, List<int>> ints =
        const RivetValue.absent(),
  }) => MalformedArraysCompanion._(ints: ints);

  /// Mutation value for `ints`.
  final RivetValue<MalformedArrays, List<int>, List<int>> ints;

  /// The generated column assignments in declaration order.
  @override
  List<RivetAssignment<MalformedArrays>> operator [](RivetCompanionKey key) => [
    RivetAssignment('ints', ints),
  ];
}

final class _$MalformedArraysDB
    extends RivetTableAccessor<MalformedArrays, MalformedArraysRow> {
  const _$MalformedArraysDB();

  @override
  RivetTableSchema<MalformedArrays, MalformedArraysRow> buildSchema() {
    MalformedArrays createDefinition() {
      final definition = MalformedArrays();

      return definition;
    }

    final definition = createDefinition();

    return RivetTableSchema<MalformedArrays, MalformedArraysRow>(
      schemaName: 'fbr122',
      tableName: 'malformedArrays',
      definition: definition,
      columns: [definition.ints as RivetColumn<Object?>],
      columnNames: ['ints'],
      createDefinition: createDefinition,
      columnsFor: (definition) => [definition.ints as RivetColumn<Object?>],
      decode: (values, sqlNulls) => MalformedArraysRow(
        ints: definition.ints.decodeValue(values[0], isSqlNull: sqlNulls[0]),
      ),
    );
  }

  /// Creates a reusable insert plan.
  RivetInsert<MalformedArrays, MalformedArraysRow> insert(
    MalformedArraysCompanion companion, {
    RivetOnConflict<MalformedArrays>? onConflict,
  }) => RivetInsert(buildSchema(), companion, onConflict: onConflict);

  /// Creates a reusable batch insert plan.
  RivetInsertMany<MalformedArrays, MalformedArraysRow> insertMany(
    Iterable<MalformedArraysCompanion> companions, {
    RivetOnConflict<MalformedArrays>? onConflict,
  }) => RivetInsertMany(buildSchema(), companions, onConflict: onConflict);

  /// Creates a reusable update plan.
  RivetUpdate<MalformedArrays, MalformedArraysRow> update(
    MalformedArraysCompanion companion, {
    RivetWhere<MalformedArrays>? where,
  }) => RivetUpdate(buildSchema(), companion, where: where);

  /// Creates a reusable delete plan.
  RivetDelete<MalformedArrays, MalformedArraysRow> delete({
    RivetWhere<MalformedArrays>? where,
  }) => RivetDelete(buildSchema(), where: where);
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

  /// Creates values for an update, leaving untouched columns absent.
  factory MetadataColumnsCompanion.update({
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
  List<RivetAssignment<MetadataColumns>> operator [](RivetCompanionKey key) => [
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
    MetadataColumns createDefinition() {
      final definition = MetadataColumns();

      return definition;
    }

    final definition = createDefinition();

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
      createDefinition: createDefinition,
      columnsFor: (definition) => [
        definition.count as RivetColumn<Object?>,
        definition.payload as RivetColumn<Object?>,
        definition.embedding as RivetColumn<Object?>,
        definition.values as RivetColumn<Object?>,
        definition.code as RivetColumn<Object?>,
      ],
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
    MetadataColumnsCompanion companion, {
    RivetOnConflict<MetadataColumns>? onConflict,
  }) => RivetInsert(buildSchema(), companion, onConflict: onConflict);

  /// Creates a reusable batch insert plan.
  RivetInsertMany<MetadataColumns, MetadataColumnsRow> insertMany(
    Iterable<MetadataColumnsCompanion> companions, {
    RivetOnConflict<MetadataColumns>? onConflict,
  }) => RivetInsertMany(buildSchema(), companions, onConflict: onConflict);

  /// Creates a reusable update plan.
  RivetUpdate<MetadataColumns, MetadataColumnsRow> update(
    MetadataColumnsCompanion companion, {
    RivetWhere<MetadataColumns>? where,
  }) => RivetUpdate(buildSchema(), companion, where: where);

  /// Creates a reusable delete plan.
  RivetDelete<MetadataColumns, MetadataColumnsRow> delete({
    RivetWhere<MetadataColumns>? where,
  }) => RivetDelete(buildSchema(), where: where);
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

  /// Creates values for an update, leaving untouched columns absent.
  factory TextTargetsCompanion.update({
    RivetValue<TextTargets, String, String> value = const RivetValue.absent(),
  }) => TextTargetsCompanion._(value: value);

  /// Mutation value for `value`.
  final RivetValue<TextTargets, String, String> value;

  /// The generated column assignments in declaration order.
  @override
  List<RivetAssignment<TextTargets>> operator [](RivetCompanionKey key) => [
    RivetAssignment('value', value),
  ];
}

final class _$TextTargetsDB
    extends RivetTableAccessor<TextTargets, TextTargetsRow> {
  const _$TextTargetsDB();

  @override
  RivetTableSchema<TextTargets, TextTargetsRow> buildSchema() {
    TextTargets createDefinition() {
      final definition = TextTargets();

      return definition;
    }

    final definition = createDefinition();

    return RivetTableSchema<TextTargets, TextTargetsRow>(
      schemaName: 'metadata',
      tableName: 'textTargets',
      definition: definition,
      columns: [definition.value as RivetColumn<Object?>],
      columnNames: ['value'],
      createDefinition: createDefinition,
      columnsFor: (definition) => [definition.value as RivetColumn<Object?>],
      decode: (values, sqlNulls) => TextTargetsRow(
        value: definition.value.decodeValue(values[0], isSqlNull: sqlNulls[0]),
      ),
    );
  }

  /// Creates a reusable insert plan.
  RivetInsert<TextTargets, TextTargetsRow> insert(
    TextTargetsCompanion companion, {
    RivetOnConflict<TextTargets>? onConflict,
  }) => RivetInsert(buildSchema(), companion, onConflict: onConflict);

  /// Creates a reusable batch insert plan.
  RivetInsertMany<TextTargets, TextTargetsRow> insertMany(
    Iterable<TextTargetsCompanion> companions, {
    RivetOnConflict<TextTargets>? onConflict,
  }) => RivetInsertMany(buildSchema(), companions, onConflict: onConflict);

  /// Creates a reusable update plan.
  RivetUpdate<TextTargets, TextTargetsRow> update(
    TextTargetsCompanion companion, {
    RivetWhere<TextTargets>? where,
  }) => RivetUpdate(buildSchema(), companion, where: where);

  /// Creates a reusable delete plan.
  RivetDelete<TextTargets, TextTargetsRow> delete({
    RivetWhere<TextTargets>? where,
  }) => RivetDelete(buildSchema(), where: where);
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

  /// Creates values for an update, leaving untouched columns absent.
  factory InvalidReferencesCompanion.update({
    RivetValue<InvalidReferences, int, int> value = const RivetValue.absent(),
  }) => InvalidReferencesCompanion._(value: value);

  /// Mutation value for `value`.
  final RivetValue<InvalidReferences, int, int> value;

  /// The generated column assignments in declaration order.
  @override
  List<RivetAssignment<InvalidReferences>> operator [](RivetCompanionKey key) =>
      [RivetAssignment('value', value)];
}

final class _$InvalidReferencesDB
    extends RivetTableAccessor<InvalidReferences, InvalidReferencesRow> {
  const _$InvalidReferencesDB();

  @override
  RivetTableSchema<InvalidReferences, InvalidReferencesRow> buildSchema() {
    InvalidReferences createDefinition() {
      final definition = InvalidReferences();

      return definition;
    }

    final definition = createDefinition();

    return RivetTableSchema<InvalidReferences, InvalidReferencesRow>(
      schemaName: 'metadata',
      tableName: 'invalidReferences',
      definition: definition,
      columns: [definition.value as RivetColumn<Object?>],
      columnNames: ['value'],
      createDefinition: createDefinition,
      columnsFor: (definition) => [definition.value as RivetColumn<Object?>],
      decode: (values, sqlNulls) => InvalidReferencesRow(
        value: definition.value.decodeValue(values[0], isSqlNull: sqlNulls[0]),
      ),
    );
  }

  /// Creates a reusable insert plan.
  RivetInsert<InvalidReferences, InvalidReferencesRow> insert(
    InvalidReferencesCompanion companion, {
    RivetOnConflict<InvalidReferences>? onConflict,
  }) => RivetInsert(buildSchema(), companion, onConflict: onConflict);

  /// Creates a reusable batch insert plan.
  RivetInsertMany<InvalidReferences, InvalidReferencesRow> insertMany(
    Iterable<InvalidReferencesCompanion> companions, {
    RivetOnConflict<InvalidReferences>? onConflict,
  }) => RivetInsertMany(buildSchema(), companions, onConflict: onConflict);

  /// Creates a reusable update plan.
  RivetUpdate<InvalidReferences, InvalidReferencesRow> update(
    InvalidReferencesCompanion companion, {
    RivetWhere<InvalidReferences>? where,
  }) => RivetUpdate(buildSchema(), companion, where: where);

  /// Creates a reusable delete plan.
  RivetDelete<InvalidReferences, InvalidReferencesRow> delete({
    RivetWhere<InvalidReferences>? where,
  }) => RivetDelete(buildSchema(), where: where);
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

  /// Creates values for an update, leaving untouched columns absent.
  factory ParameterNamesCompanion.update({
    RivetValue<ParameterNames, String, String> value =
        const RivetValue.absent(),
  }) => ParameterNamesCompanion._(value: value);

  /// Mutation value for `value`.
  final RivetValue<ParameterNames, String, String> value;

  /// The generated column assignments in declaration order.
  @override
  List<RivetAssignment<ParameterNames>> operator [](RivetCompanionKey key) => [
    RivetAssignment('value', value),
  ];
}

final class _$ParameterNamesDB
    extends RivetTableAccessor<ParameterNames, ParameterNamesRow> {
  const _$ParameterNamesDB();

  @override
  RivetTableSchema<ParameterNames, ParameterNamesRow> buildSchema() {
    ParameterNames createDefinition() {
      final definition = ParameterNames();

      return definition;
    }

    final definition = createDefinition();

    return RivetTableSchema<ParameterNames, ParameterNamesRow>(
      schemaName: 'metadata',
      tableName: 'parameterNames',
      definition: definition,
      columns: [definition.value as RivetColumn<Object?>],
      columnNames: ['value'],
      createDefinition: createDefinition,
      columnsFor: (definition) => [definition.value as RivetColumn<Object?>],
      decode: (values, sqlNulls) => ParameterNamesRow(
        value: definition.value.decodeValue(values[0], isSqlNull: sqlNulls[0]),
      ),
    );
  }

  /// Creates a reusable insert plan.
  RivetInsert<ParameterNames, ParameterNamesRow> insert(
    ParameterNamesCompanion companion, {
    RivetOnConflict<ParameterNames>? onConflict,
  }) => RivetInsert(buildSchema(), companion, onConflict: onConflict);

  /// Creates a reusable batch insert plan.
  RivetInsertMany<ParameterNames, ParameterNamesRow> insertMany(
    Iterable<ParameterNamesCompanion> companions, {
    RivetOnConflict<ParameterNames>? onConflict,
  }) => RivetInsertMany(buildSchema(), companions, onConflict: onConflict);

  /// Creates a reusable update plan.
  RivetUpdate<ParameterNames, ParameterNamesRow> update(
    ParameterNamesCompanion companion, {
    RivetWhere<ParameterNames>? where,
  }) => RivetUpdate(buildSchema(), companion, where: where);

  /// Creates a reusable delete plan.
  RivetDelete<ParameterNames, ParameterNamesRow> delete({
    RivetWhere<ParameterNames>? where,
  }) => RivetDelete(buildSchema(), where: where);
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

  /// Creates values for an update, leaving untouched columns absent.
  factory MutationCatalogCompanion.update({
    RivetValue<MutationCatalog, int, int> id = const RivetValue.absent(),
    RivetValue<MutationCatalog, String, String> textValue =
        const RivetValue.absent(),
    RivetValue<MutationCatalog, int, int> count = const RivetValue.absent(),
    RivetValue<MutationCatalog, double, double> score =
        const RivetValue.absent(),
    RivetValue<MutationCatalog, bool, bool> active = const RivetValue.absent(),
    RivetValue<MutationCatalog, DateTime, DateTime> createdAt =
        const RivetValue.absent(),
    RivetValue<MutationCatalog, JsonValue, JsonValue> payload =
        const RivetValue.absent(),
    RivetValue<MutationCatalog, JsonValue?, JsonValue?> nullablePayload =
        const RivetValue.absent(),
    RivetValue<MutationCatalog, Preferences, JsonValue> preferences =
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
    RivetValue<MutationCatalog, List<DateTime>, List<DateTime>> timestamps =
        const RivetValue.absent(),
    RivetValue<MutationCatalog, List<int?>, List<int?>> nullableInts =
        const RivetValue.absent(),
    RivetValue<MutationCatalog, List<int>?, List<int>?> optionalInts =
        const RivetValue.absent(),
    RivetValue<MutationCatalog, List<JsonValue?>, List<JsonValue?>> jsonValues =
        const RivetValue.absent(),
    RivetValue<MutationCatalog, List<MutationCode?>, List<String?>>
        mappedCodes =
        const RivetValue.absent(),
    RivetValue<MutationCatalog, Float32List, Float32List> embedding =
        const RivetValue.absent(),
    RivetValue<MutationCatalog, List<Float32List>, List<Float32List>>
        embeddings =
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
  List<RivetAssignment<MutationCatalog>> operator [](RivetCompanionKey key) => [
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
    MutationCatalog createDefinition() {
      final definition = MutationCatalog();
      definition.status.configureEnum(MutationStatusRivetEnum.codec);
      definition.statuses.configureEnum(MutationStatusRivetEnum.codec);
      return definition;
    }

    final definition = createDefinition();

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
      createDefinition: createDefinition,
      columnsFor: (definition) => [
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
    MutationCatalogCompanion companion, {
    RivetOnConflict<MutationCatalog>? onConflict,
  }) => RivetInsert(buildSchema(), companion, onConflict: onConflict);

  /// Creates a reusable batch insert plan.
  RivetInsertMany<MutationCatalog, MutationCatalogRow> insertMany(
    Iterable<MutationCatalogCompanion> companions, {
    RivetOnConflict<MutationCatalog>? onConflict,
  }) => RivetInsertMany(buildSchema(), companions, onConflict: onConflict);

  /// Creates a reusable update plan.
  RivetUpdate<MutationCatalog, MutationCatalogRow> update(
    MutationCatalogCompanion companion, {
    RivetWhere<MutationCatalog>? where,
  }) => RivetUpdate(buildSchema(), companion, where: where);

  /// Creates a reusable delete plan.
  RivetDelete<MutationCatalog, MutationCatalogRow> delete({
    RivetWhere<MutationCatalog>? where,
  }) => RivetDelete(buildSchema(), where: where);
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

  /// Creates values for an update, leaving untouched columns absent.
  factory MutationUsersCompanion.update({
    RivetValue<MutationUsers, int, int> id = const RivetValue.absent(),
    RivetValue<MutationUsers, String, String> name = const RivetValue.absent(),
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
  List<RivetAssignment<MutationUsers>> operator [](RivetCompanionKey key) => [
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
    MutationUsers createDefinition() {
      final definition = MutationUsers();

      return definition;
    }

    final definition = createDefinition();

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
      createDefinition: createDefinition,
      columnsFor: (definition) => [
        definition.id as RivetColumn<Object?>,
        definition.name as RivetColumn<Object?>,
        definition.nickname as RivetColumn<Object?>,
        definition.createdAt as RivetColumn<Object?>,
        definition.updatedAt as RivetColumn<Object?>,
        definition.nullableDefault as RivetColumn<Object?>,
        definition.serverValue as RivetColumn<Object?>,
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
    MutationUsersCompanion companion, {
    RivetOnConflict<MutationUsers>? onConflict,
  }) => RivetInsert(buildSchema(), companion, onConflict: onConflict);

  /// Creates a reusable batch insert plan.
  RivetInsertMany<MutationUsers, MutationUsersRow> insertMany(
    Iterable<MutationUsersCompanion> companions, {
    RivetOnConflict<MutationUsers>? onConflict,
  }) => RivetInsertMany(buildSchema(), companions, onConflict: onConflict);

  /// Creates a reusable update plan.
  RivetUpdate<MutationUsers, MutationUsersRow> update(
    MutationUsersCompanion companion, {
    RivetWhere<MutationUsers>? where,
  }) => RivetUpdate(buildSchema(), companion, where: where);

  /// Creates a reusable delete plan.
  RivetDelete<MutationUsers, MutationUsersRow> delete({
    RivetWhere<MutationUsers>? where,
  }) => RivetDelete(buildSchema(), where: where);
}

/// Typed relation include scope for [MutationParents].
final class MutationParentsInclude {
  /// Creates the generated include scope.
  const MutationParentsInclude(this._schema, {this.path = ''});

  final RivetTableSchema<MutationParents, MutationParentsRow> _schema;

  /// Full relation path used in diagnostics.
  final String path;

  /// Includes the [children] relation.
  RivetInclude<MutationChildren, MutationChildrenRow> children({
    RivetWhere<MutationChildren>? where,
    RivetOrderBy<MutationChildren>? orderBy,
    int? limit,

    RivetIncludes<MutationChildrenInclude>? include,
  }) {
    final target = MutationChildren.db.buildSchema();

    final relationPath = path.isEmpty ? 'children' : '$path.children';
    return RivetInclude<MutationChildren, MutationChildrenRow>(
      name: 'children',
      path: relationPath,
      relation: _schema.relations['children']!,
      targetSchema: target,

      where: where,
      orderBy: orderBy,
      limit: limit,

      includes:
          include?.call(MutationChildrenInclude(target, path: relationPath)) ??
          const [],
    );
  }
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

  /// Creates values for an update, leaving untouched columns absent.
  factory MutationParentsCompanion.update({
    RivetValue<MutationParents, int, int> id = const RivetValue.absent(),
    RivetValue<MutationParents, String, String> name =
        const RivetValue.absent(),
  }) => MutationParentsCompanion._(id: id, name: name);

  /// Mutation value for `id`.
  final RivetValue<MutationParents, int, int> id;

  /// Mutation value for `name`.
  final RivetValue<MutationParents, String, String> name;

  /// The generated column assignments in declaration order.
  @override
  List<RivetAssignment<MutationParents>> operator [](RivetCompanionKey key) => [
    RivetAssignment('id', id),
    RivetAssignment('name', name),
  ];
}

final class _$MutationParentsDB
    extends RivetTableAccessor<MutationParents, MutationParentsRow> {
  const _$MutationParentsDB();

  @override
  RivetTableSchema<MutationParents, MutationParentsRow> buildSchema() {
    MutationParents createDefinition() {
      final definition = MutationParents();

      return definition;
    }

    final definition = createDefinition();
    MutationParentsRow decodeRow(
      List<Object?> values,
      List<bool> sqlNulls,
      RivetRelationValues relations, {
      required bool transport,
    }) => MutationParentsRow(
      id: transport
          ? definition.id.decodeTransportValue(
              values[0],
              isSqlNull: sqlNulls[0],
            )
          : definition.id.decodeValue(values[0], isSqlNull: sqlNulls[0]),
      name: transport
          ? definition.name.decodeTransportValue(
              values[1],
              isSqlNull: sqlNulls[1],
            )
          : definition.name.decodeValue(values[1], isSqlNull: sqlNulls[1]),
      children: relations.read('children'),
    );

    final builtSchema = RivetTableSchema<MutationParents, MutationParentsRow>(
      schemaName: 'fbr138',
      tableName: 'mutationParents',
      definition: definition,
      columns: [
        definition.id as RivetColumn<Object?>,
        definition.name as RivetColumn<Object?>,
      ],
      columnNames: ['id', 'name'],
      createDefinition: createDefinition,
      columnsFor: (definition) => [
        definition.id as RivetColumn<Object?>,
        definition.name as RivetColumn<Object?>,
      ],
      decode: (values, sqlNulls) => decodeRow(
        values,
        sqlNulls,
        const RivetRelationValues(),
        transport: false,
      ),
      decodeRelated: decodeRow,

      relations: {
        'children': definition.children as RivetRelationDescriptor<Object?>,
      },
    );
    definition.children.bind(
      name: 'children',
      ownerSchema: builtSchema,
      targetSchema: () => MutationChildren.db.buildSchema(),
    );
    return builtSchema;
  }

  /// Creates a reusable read plan with typed relation includes.
  RivetFind<MutationParents, MutationParentsRow> find({
    RivetWhere<MutationParents>? where,
    RivetOrderBy<MutationParents>? orderBy,
    int? limit,
    int? offset,
    RivetIncludes<MutationParentsInclude>? include,
  }) {
    final schema = buildSchema();
    return RivetFind(
      schema,
      where: where,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
      includes: include?.call(MutationParentsInclude(schema)) ?? const [],
    );
  }

  /// Creates a reusable insert plan.
  RivetInsert<MutationParents, MutationParentsRow> insert(
    MutationParentsCompanion companion, {
    RivetOnConflict<MutationParents>? onConflict,
  }) => RivetInsert(buildSchema(), companion, onConflict: onConflict);

  /// Creates a reusable batch insert plan.
  RivetInsertMany<MutationParents, MutationParentsRow> insertMany(
    Iterable<MutationParentsCompanion> companions, {
    RivetOnConflict<MutationParents>? onConflict,
  }) => RivetInsertMany(buildSchema(), companions, onConflict: onConflict);

  /// Creates a reusable update plan.
  RivetUpdate<MutationParents, MutationParentsRow> update(
    MutationParentsCompanion companion, {
    RivetWhere<MutationParents>? where,
  }) => RivetUpdate(buildSchema(), companion, where: where);

  /// Creates a reusable delete plan.
  RivetDelete<MutationParents, MutationParentsRow> delete({
    RivetWhere<MutationParents>? where,
  }) => RivetDelete(buildSchema(), where: where);
}

/// Typed relation include scope for [MutationChildren].
final class MutationChildrenInclude {
  /// Creates the generated include scope.
  const MutationChildrenInclude(this._schema, {this.path = ''});

  final RivetTableSchema<MutationChildren, MutationChildrenRow> _schema;

  /// Full relation path used in diagnostics.
  final String path;

  /// Includes the [parent] relation.
  RivetInclude<MutationParents, MutationParentsRow> parent({
    RivetWhere<MutationParents>? where,

    RivetIncludes<MutationParentsInclude>? include,
  }) {
    final target = MutationParents.db.buildSchema();

    final relationPath = path.isEmpty ? 'parent' : '$path.parent';
    return RivetInclude<MutationParents, MutationParentsRow>(
      name: 'parent',
      path: relationPath,
      relation: _schema.relations['parent']!,
      targetSchema: target,

      where: where,

      includes:
          include?.call(MutationParentsInclude(target, path: relationPath)) ??
          const [],
    );
  }
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

  /// Creates values for an update, leaving untouched columns absent.
  factory MutationChildrenCompanion.update({
    RivetValue<MutationChildren, int, int> id = const RivetValue.absent(),
    RivetValue<MutationChildren, int, int> parentId = const RivetValue.absent(),
  }) => MutationChildrenCompanion._(id: id, parentId: parentId);

  /// Mutation value for `id`.
  final RivetValue<MutationChildren, int, int> id;

  /// Mutation value for `parentId`.
  final RivetValue<MutationChildren, int, int> parentId;

  /// The generated column assignments in declaration order.
  @override
  List<RivetAssignment<MutationChildren>> operator [](RivetCompanionKey key) =>
      [RivetAssignment('id', id), RivetAssignment('parentId', parentId)];
}

final class _$MutationChildrenDB
    extends RivetTableAccessor<MutationChildren, MutationChildrenRow> {
  const _$MutationChildrenDB();

  @override
  RivetTableSchema<MutationChildren, MutationChildrenRow> buildSchema() {
    MutationChildren createDefinition() {
      final definition = MutationChildren();

      return definition;
    }

    final definition = createDefinition();
    MutationChildrenRow decodeRow(
      List<Object?> values,
      List<bool> sqlNulls,
      RivetRelationValues relations, {
      required bool transport,
    }) => MutationChildrenRow(
      id: transport
          ? definition.id.decodeTransportValue(
              values[0],
              isSqlNull: sqlNulls[0],
            )
          : definition.id.decodeValue(values[0], isSqlNull: sqlNulls[0]),
      parentId: transport
          ? definition.parentId.decodeTransportValue(
              values[1],
              isSqlNull: sqlNulls[1],
            )
          : definition.parentId.decodeValue(values[1], isSqlNull: sqlNulls[1]),
      parent: relations.read('parent'),
    );

    final builtSchema = RivetTableSchema<MutationChildren, MutationChildrenRow>(
      schemaName: 'fbr138',
      tableName: 'mutationChildren',
      definition: definition,
      columns: [
        definition.id as RivetColumn<Object?>,
        definition.parentId as RivetColumn<Object?>,
      ],
      columnNames: ['id', 'parentId'],
      createDefinition: createDefinition,
      columnsFor: (definition) => [
        definition.id as RivetColumn<Object?>,
        definition.parentId as RivetColumn<Object?>,
      ],
      decode: (values, sqlNulls) => decodeRow(
        values,
        sqlNulls,
        const RivetRelationValues(),
        transport: false,
      ),
      decodeRelated: decodeRow,

      relations: {
        'parent': definition.parent as RivetRelationDescriptor<Object?>,
      },
    );
    definition.parent.bind(
      name: 'parent',
      ownerSchema: builtSchema,
      targetSchema: () => MutationParents.db.buildSchema(),
    );
    return builtSchema;
  }

  /// Creates a reusable read plan with typed relation includes.
  RivetFind<MutationChildren, MutationChildrenRow> find({
    RivetWhere<MutationChildren>? where,
    RivetOrderBy<MutationChildren>? orderBy,
    int? limit,
    int? offset,
    RivetIncludes<MutationChildrenInclude>? include,
  }) {
    final schema = buildSchema();
    return RivetFind(
      schema,
      where: where,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
      includes: include?.call(MutationChildrenInclude(schema)) ?? const [],
    );
  }

  /// Creates a reusable insert plan.
  RivetInsert<MutationChildren, MutationChildrenRow> insert(
    MutationChildrenCompanion companion, {
    RivetOnConflict<MutationChildren>? onConflict,
  }) => RivetInsert(buildSchema(), companion, onConflict: onConflict);

  /// Creates a reusable batch insert plan.
  RivetInsertMany<MutationChildren, MutationChildrenRow> insertMany(
    Iterable<MutationChildrenCompanion> companions, {
    RivetOnConflict<MutationChildren>? onConflict,
  }) => RivetInsertMany(buildSchema(), companions, onConflict: onConflict);

  /// Creates a reusable update plan.
  RivetUpdate<MutationChildren, MutationChildrenRow> update(
    MutationChildrenCompanion companion, {
    RivetWhere<MutationChildren>? where,
  }) => RivetUpdate(buildSchema(), companion, where: where);

  /// Creates a reusable delete plan.
  RivetDelete<MutationChildren, MutationChildrenRow> delete({
    RivetWhere<MutationChildren>? where,
  }) => RivetDelete(buildSchema(), where: where);
}

/// Typed relation include scope for [MutationUpdateUsers].
final class MutationUpdateUsersInclude {
  /// Creates the generated include scope.
  const MutationUpdateUsersInclude(this._schema, {this.path = ''});

  final RivetTableSchema<MutationUpdateUsers, MutationUpdateUsersRow> _schema;

  /// Full relation path used in diagnostics.
  final String path;

  /// Includes the [children] relation.
  RivetInclude<MutationUpdateChildren, MutationUpdateChildrenRow> children({
    RivetWhere<MutationUpdateChildren>? where,
    RivetOrderBy<MutationUpdateChildren>? orderBy,
    int? limit,

    RivetIncludes<MutationUpdateChildrenInclude>? include,
  }) {
    final target = MutationUpdateChildren.db.buildSchema();

    final relationPath = path.isEmpty ? 'children' : '$path.children';
    return RivetInclude<MutationUpdateChildren, MutationUpdateChildrenRow>(
      name: 'children',
      path: relationPath,
      relation: _schema.relations['children']!,
      targetSchema: target,

      where: where,
      orderBy: orderBy,
      limit: limit,

      includes:
          include?.call(
            MutationUpdateChildrenInclude(target, path: relationPath),
          ) ??
          const [],
    );
  }
}

/// Generated row returned by reads from 'fbr140.mutationUpdateUsers'.
final class MutationUpdateUsersRow {
  /// Creates a row from decoded column and relation values.
  const MutationUpdateUsersRow({
    required this.id,
    required this.name,
    required this.age,
    required this.updatedAt,
    required this.nullableNote,
    required this.code,
    required this.defaultOnly,
    required this.serverOnly,
    this.children = const Relation.unloaded(),
  });

  /// Value read from `id`.
  final int id;

  /// Value read from `name`.
  final String name;

  /// Value read from `age`.
  final int age;

  /// Value read from `updatedAt`.
  final DateTime updatedAt;

  /// Value read from `nullableNote`.
  final String? nullableNote;

  /// Value read from `code`.
  final MutationCode code;

  /// Value read from `defaultOnly`.
  final String defaultOnly;

  /// Value read from `serverOnly`.
  final int serverOnly;

  /// Loaded or unloaded `children` relation.
  final Relation<List<MutationUpdateChildrenRow>> children;
}

/// Generated values accepted by mutations of 'fbr140.mutationUpdateUsers'.
final class MutationUpdateUsersCompanion
    implements RivetCompanion<MutationUpdateUsers> {
  const MutationUpdateUsersCompanion._({
    required this.id,
    required this.name,
    required this.age,
    required this.updatedAt,
    required this.nullableNote,
    required this.code,
    required this.defaultOnly,
    required this.serverOnly,
  });

  /// Creates values for an insert, leaving defaulted columns absent.
  factory MutationUpdateUsersCompanion.insert({
    required RivetValue<MutationUpdateUsers, int, int> id,
    required RivetValue<MutationUpdateUsers, String, String> name,
    required RivetValue<MutationUpdateUsers, int, int> age,
    RivetValue<MutationUpdateUsers, DateTime, DateTime> updatedAt =
        const RivetValue.absent(),
    RivetValue<MutationUpdateUsers, String?, String?> nullableNote =
        const RivetValue.absent(),
    RivetValue<MutationUpdateUsers, MutationCode, String> code =
        const RivetValue.absent(),
    RivetValue<MutationUpdateUsers, String, String> defaultOnly =
        const RivetValue.absent(),
    RivetValue<MutationUpdateUsers, int, int> serverOnly =
        const RivetValue.absent(),
  }) => MutationUpdateUsersCompanion._(
    id: id,
    name: name,
    age: age,
    updatedAt: updatedAt,
    nullableNote: nullableNote,
    code: code,
    defaultOnly: defaultOnly,
    serverOnly: serverOnly,
  );

  /// Creates values for an update, leaving untouched columns absent.
  factory MutationUpdateUsersCompanion.update({
    RivetValue<MutationUpdateUsers, int, int> id = const RivetValue.absent(),
    RivetValue<MutationUpdateUsers, String, String> name =
        const RivetValue.absent(),
    RivetValue<MutationUpdateUsers, int, int> age = const RivetValue.absent(),
    RivetValue<MutationUpdateUsers, DateTime, DateTime> updatedAt =
        const RivetValue.absent(),
    RivetValue<MutationUpdateUsers, String?, String?> nullableNote =
        const RivetValue.absent(),
    RivetValue<MutationUpdateUsers, MutationCode, String> code =
        const RivetValue.absent(),
    RivetValue<MutationUpdateUsers, String, String> defaultOnly =
        const RivetValue.absent(),
    RivetValue<MutationUpdateUsers, int, int> serverOnly =
        const RivetValue.absent(),
  }) => MutationUpdateUsersCompanion._(
    id: id,
    name: name,
    age: age,
    updatedAt: updatedAt,
    nullableNote: nullableNote,
    code: code,
    defaultOnly: defaultOnly,
    serverOnly: serverOnly,
  );

  /// Mutation value for `id`.
  final RivetValue<MutationUpdateUsers, int, int> id;

  /// Mutation value for `name`.
  final RivetValue<MutationUpdateUsers, String, String> name;

  /// Mutation value for `age`.
  final RivetValue<MutationUpdateUsers, int, int> age;

  /// Mutation value for `updatedAt`.
  final RivetValue<MutationUpdateUsers, DateTime, DateTime> updatedAt;

  /// Mutation value for `nullableNote`.
  final RivetValue<MutationUpdateUsers, String?, String?> nullableNote;

  /// Mutation value for `code`.
  final RivetValue<MutationUpdateUsers, MutationCode, String> code;

  /// Mutation value for `defaultOnly`.
  final RivetValue<MutationUpdateUsers, String, String> defaultOnly;

  /// Mutation value for `serverOnly`.
  final RivetValue<MutationUpdateUsers, int, int> serverOnly;

  /// The generated column assignments in declaration order.
  @override
  List<RivetAssignment<MutationUpdateUsers>> operator [](
    RivetCompanionKey key,
  ) => [
    RivetAssignment('id', id),
    RivetAssignment('name', name),
    RivetAssignment('age', age),
    RivetAssignment('updatedAt', updatedAt),
    RivetAssignment('nullableNote', nullableNote),
    RivetAssignment('code', code),
    RivetAssignment('defaultOnly', defaultOnly),
    RivetAssignment('serverOnly', serverOnly),
  ];
}

final class _$MutationUpdateUsersDB
    extends RivetTableAccessor<MutationUpdateUsers, MutationUpdateUsersRow> {
  const _$MutationUpdateUsersDB();

  @override
  RivetTableSchema<MutationUpdateUsers, MutationUpdateUsersRow> buildSchema() {
    MutationUpdateUsers createDefinition() {
      final definition = MutationUpdateUsers();

      return definition;
    }

    final definition = createDefinition();
    MutationUpdateUsersRow decodeRow(
      List<Object?> values,
      List<bool> sqlNulls,
      RivetRelationValues relations, {
      required bool transport,
    }) => MutationUpdateUsersRow(
      id: transport
          ? definition.id.decodeTransportValue(
              values[0],
              isSqlNull: sqlNulls[0],
            )
          : definition.id.decodeValue(values[0], isSqlNull: sqlNulls[0]),
      name: transport
          ? definition.name.decodeTransportValue(
              values[1],
              isSqlNull: sqlNulls[1],
            )
          : definition.name.decodeValue(values[1], isSqlNull: sqlNulls[1]),
      age: transport
          ? definition.age.decodeTransportValue(
              values[2],
              isSqlNull: sqlNulls[2],
            )
          : definition.age.decodeValue(values[2], isSqlNull: sqlNulls[2]),
      updatedAt: transport
          ? definition.updatedAt.decodeTransportValue(
              values[3],
              isSqlNull: sqlNulls[3],
            )
          : definition.updatedAt.decodeValue(values[3], isSqlNull: sqlNulls[3]),
      nullableNote: transport
          ? definition.nullableNote.decodeTransportValue(
              values[4],
              isSqlNull: sqlNulls[4],
            )
          : definition.nullableNote.decodeValue(
              values[4],
              isSqlNull: sqlNulls[4],
            ),
      code: transport
          ? definition.code.decodeTransportValue(
              values[5],
              isSqlNull: sqlNulls[5],
            )
          : definition.code.decodeValue(values[5], isSqlNull: sqlNulls[5]),
      defaultOnly: transport
          ? definition.defaultOnly.decodeTransportValue(
              values[6],
              isSqlNull: sqlNulls[6],
            )
          : definition.defaultOnly.decodeValue(
              values[6],
              isSqlNull: sqlNulls[6],
            ),
      serverOnly: transport
          ? definition.serverOnly.decodeTransportValue(
              values[7],
              isSqlNull: sqlNulls[7],
            )
          : definition.serverOnly.decodeValue(
              values[7],
              isSqlNull: sqlNulls[7],
            ),
      children: relations.read('children'),
    );

    final builtSchema =
        RivetTableSchema<MutationUpdateUsers, MutationUpdateUsersRow>(
          schemaName: 'fbr140',
          tableName: 'mutationUpdateUsers',
          definition: definition,
          columns: [
            definition.id as RivetColumn<Object?>,
            definition.name as RivetColumn<Object?>,
            definition.age as RivetColumn<Object?>,
            definition.updatedAt as RivetColumn<Object?>,
            definition.nullableNote as RivetColumn<Object?>,
            definition.code as RivetColumn<Object?>,
            definition.defaultOnly as RivetColumn<Object?>,
            definition.serverOnly as RivetColumn<Object?>,
          ],
          columnNames: [
            'id',
            'name',
            'age',
            'updatedAt',
            'nullableNote',
            'code',
            'defaultOnly',
            'serverOnly',
          ],
          createDefinition: createDefinition,
          columnsFor: (definition) => [
            definition.id as RivetColumn<Object?>,
            definition.name as RivetColumn<Object?>,
            definition.age as RivetColumn<Object?>,
            definition.updatedAt as RivetColumn<Object?>,
            definition.nullableNote as RivetColumn<Object?>,
            definition.code as RivetColumn<Object?>,
            definition.defaultOnly as RivetColumn<Object?>,
            definition.serverOnly as RivetColumn<Object?>,
          ],
          decode: (values, sqlNulls) => decodeRow(
            values,
            sqlNulls,
            const RivetRelationValues(),
            transport: false,
          ),
          decodeRelated: decodeRow,

          relations: {
            'children': definition.children as RivetRelationDescriptor<Object?>,
          },
        );
    definition.children.bind(
      name: 'children',
      ownerSchema: builtSchema,
      targetSchema: () => MutationUpdateChildren.db.buildSchema(),
    );
    return builtSchema;
  }

  /// Creates a reusable read plan with typed relation includes.
  RivetFind<MutationUpdateUsers, MutationUpdateUsersRow> find({
    RivetWhere<MutationUpdateUsers>? where,
    RivetOrderBy<MutationUpdateUsers>? orderBy,
    int? limit,
    int? offset,
    RivetIncludes<MutationUpdateUsersInclude>? include,
  }) {
    final schema = buildSchema();
    return RivetFind(
      schema,
      where: where,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
      includes: include?.call(MutationUpdateUsersInclude(schema)) ?? const [],
    );
  }

  /// Creates a reusable insert plan.
  RivetInsert<MutationUpdateUsers, MutationUpdateUsersRow> insert(
    MutationUpdateUsersCompanion companion, {
    RivetOnConflict<MutationUpdateUsers>? onConflict,
  }) => RivetInsert(buildSchema(), companion, onConflict: onConflict);

  /// Creates a reusable batch insert plan.
  RivetInsertMany<MutationUpdateUsers, MutationUpdateUsersRow> insertMany(
    Iterable<MutationUpdateUsersCompanion> companions, {
    RivetOnConflict<MutationUpdateUsers>? onConflict,
  }) => RivetInsertMany(buildSchema(), companions, onConflict: onConflict);

  /// Creates a reusable update plan.
  RivetUpdate<MutationUpdateUsers, MutationUpdateUsersRow> update(
    MutationUpdateUsersCompanion companion, {
    RivetWhere<MutationUpdateUsers>? where,
  }) => RivetUpdate(buildSchema(), companion, where: where);

  /// Creates a reusable delete plan.
  RivetDelete<MutationUpdateUsers, MutationUpdateUsersRow> delete({
    RivetWhere<MutationUpdateUsers>? where,
  }) => RivetDelete(buildSchema(), where: where);
}

/// Typed relation include scope for [MutationUpdateChildren].
final class MutationUpdateChildrenInclude {
  /// Creates the generated include scope.
  const MutationUpdateChildrenInclude(this._schema, {this.path = ''});

  final RivetTableSchema<MutationUpdateChildren, MutationUpdateChildrenRow>
  _schema;

  /// Full relation path used in diagnostics.
  final String path;

  /// Includes the [user] relation.
  RivetInclude<MutationUpdateUsers, MutationUpdateUsersRow> user({
    RivetWhere<MutationUpdateUsers>? where,

    RivetIncludes<MutationUpdateUsersInclude>? include,
  }) {
    final target = MutationUpdateUsers.db.buildSchema();

    final relationPath = path.isEmpty ? 'user' : '$path.user';
    return RivetInclude<MutationUpdateUsers, MutationUpdateUsersRow>(
      name: 'user',
      path: relationPath,
      relation: _schema.relations['user']!,
      targetSchema: target,

      where: where,

      includes:
          include?.call(
            MutationUpdateUsersInclude(target, path: relationPath),
          ) ??
          const [],
    );
  }
}

/// Generated row returned by reads from 'fbr140.mutationUpdateChildren'.
final class MutationUpdateChildrenRow {
  /// Creates a row from decoded column and relation values.
  const MutationUpdateChildrenRow({
    required this.id,
    required this.userId,
    this.user = const Relation.unloaded(),
  });

  /// Value read from `id`.
  final int id;

  /// Value read from `userId`.
  final int userId;

  /// Loaded or unloaded `user` relation.
  final Relation<MutationUpdateUsersRow?> user;
}

/// Generated values accepted by mutations of 'fbr140.mutationUpdateChildren'.
final class MutationUpdateChildrenCompanion
    implements RivetCompanion<MutationUpdateChildren> {
  const MutationUpdateChildrenCompanion._({
    required this.id,
    required this.userId,
  });

  /// Creates values for an insert, leaving defaulted columns absent.
  factory MutationUpdateChildrenCompanion.insert({
    required RivetValue<MutationUpdateChildren, int, int> id,
    required RivetValue<MutationUpdateChildren, int, int> userId,
  }) => MutationUpdateChildrenCompanion._(id: id, userId: userId);

  /// Creates values for an update, leaving untouched columns absent.
  factory MutationUpdateChildrenCompanion.update({
    RivetValue<MutationUpdateChildren, int, int> id = const RivetValue.absent(),
    RivetValue<MutationUpdateChildren, int, int> userId =
        const RivetValue.absent(),
  }) => MutationUpdateChildrenCompanion._(id: id, userId: userId);

  /// Mutation value for `id`.
  final RivetValue<MutationUpdateChildren, int, int> id;

  /// Mutation value for `userId`.
  final RivetValue<MutationUpdateChildren, int, int> userId;

  /// The generated column assignments in declaration order.
  @override
  List<RivetAssignment<MutationUpdateChildren>> operator [](
    RivetCompanionKey key,
  ) => [RivetAssignment('id', id), RivetAssignment('userId', userId)];
}

final class _$MutationUpdateChildrenDB
    extends
        RivetTableAccessor<MutationUpdateChildren, MutationUpdateChildrenRow> {
  const _$MutationUpdateChildrenDB();

  @override
  RivetTableSchema<MutationUpdateChildren, MutationUpdateChildrenRow>
  buildSchema() {
    MutationUpdateChildren createDefinition() {
      final definition = MutationUpdateChildren();

      return definition;
    }

    final definition = createDefinition();
    MutationUpdateChildrenRow decodeRow(
      List<Object?> values,
      List<bool> sqlNulls,
      RivetRelationValues relations, {
      required bool transport,
    }) => MutationUpdateChildrenRow(
      id: transport
          ? definition.id.decodeTransportValue(
              values[0],
              isSqlNull: sqlNulls[0],
            )
          : definition.id.decodeValue(values[0], isSqlNull: sqlNulls[0]),
      userId: transport
          ? definition.userId.decodeTransportValue(
              values[1],
              isSqlNull: sqlNulls[1],
            )
          : definition.userId.decodeValue(values[1], isSqlNull: sqlNulls[1]),
      user: relations.read('user'),
    );

    final builtSchema =
        RivetTableSchema<MutationUpdateChildren, MutationUpdateChildrenRow>(
          schemaName: 'fbr140',
          tableName: 'mutationUpdateChildren',
          definition: definition,
          columns: [
            definition.id as RivetColumn<Object?>,
            definition.userId as RivetColumn<Object?>,
          ],
          columnNames: ['id', 'userId'],
          createDefinition: createDefinition,
          columnsFor: (definition) => [
            definition.id as RivetColumn<Object?>,
            definition.userId as RivetColumn<Object?>,
          ],
          decode: (values, sqlNulls) => decodeRow(
            values,
            sqlNulls,
            const RivetRelationValues(),
            transport: false,
          ),
          decodeRelated: decodeRow,

          relations: {
            'user': definition.user as RivetRelationDescriptor<Object?>,
          },
        );
    definition.user.bind(
      name: 'user',
      ownerSchema: builtSchema,
      targetSchema: () => MutationUpdateUsers.db.buildSchema(),
    );
    return builtSchema;
  }

  /// Creates a reusable read plan with typed relation includes.
  RivetFind<MutationUpdateChildren, MutationUpdateChildrenRow> find({
    RivetWhere<MutationUpdateChildren>? where,
    RivetOrderBy<MutationUpdateChildren>? orderBy,
    int? limit,
    int? offset,
    RivetIncludes<MutationUpdateChildrenInclude>? include,
  }) {
    final schema = buildSchema();
    return RivetFind(
      schema,
      where: where,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
      includes:
          include?.call(MutationUpdateChildrenInclude(schema)) ?? const [],
    );
  }

  /// Creates a reusable insert plan.
  RivetInsert<MutationUpdateChildren, MutationUpdateChildrenRow> insert(
    MutationUpdateChildrenCompanion companion, {
    RivetOnConflict<MutationUpdateChildren>? onConflict,
  }) => RivetInsert(buildSchema(), companion, onConflict: onConflict);

  /// Creates a reusable batch insert plan.
  RivetInsertMany<MutationUpdateChildren, MutationUpdateChildrenRow> insertMany(
    Iterable<MutationUpdateChildrenCompanion> companions, {
    RivetOnConflict<MutationUpdateChildren>? onConflict,
  }) => RivetInsertMany(buildSchema(), companions, onConflict: onConflict);

  /// Creates a reusable update plan.
  RivetUpdate<MutationUpdateChildren, MutationUpdateChildrenRow> update(
    MutationUpdateChildrenCompanion companion, {
    RivetWhere<MutationUpdateChildren>? where,
  }) => RivetUpdate(buildSchema(), companion, where: where);

  /// Creates a reusable delete plan.
  RivetDelete<MutationUpdateChildren, MutationUpdateChildrenRow> delete({
    RivetWhere<MutationUpdateChildren>? where,
  }) => RivetDelete(buildSchema(), where: where);
}

/// Typed relation include scope for [MutationDeleteParents].
final class MutationDeleteParentsInclude {
  /// Creates the generated include scope.
  const MutationDeleteParentsInclude(this._schema, {this.path = ''});

  final RivetTableSchema<MutationDeleteParents, MutationDeleteParentsRow>
  _schema;

  /// Full relation path used in diagnostics.
  final String path;

  /// Includes the [cascadeChildren] relation.
  RivetInclude<MutationCascadeChildren, MutationCascadeChildrenRow>
  cascadeChildren({
    RivetWhere<MutationCascadeChildren>? where,
    RivetOrderBy<MutationCascadeChildren>? orderBy,
    int? limit,

    RivetIncludes<MutationCascadeChildrenInclude>? include,
  }) {
    final target = MutationCascadeChildren.db.buildSchema();

    final relationPath = path.isEmpty
        ? 'cascadeChildren'
        : '$path.cascadeChildren';
    return RivetInclude<MutationCascadeChildren, MutationCascadeChildrenRow>(
      name: 'cascadeChildren',
      path: relationPath,
      relation: _schema.relations['cascadeChildren']!,
      targetSchema: target,

      where: where,
      orderBy: orderBy,
      limit: limit,

      includes:
          include?.call(
            MutationCascadeChildrenInclude(target, path: relationPath),
          ) ??
          const [],
    );
  }

  /// Includes the [restrictChildren] relation.
  RivetInclude<MutationRestrictChildren, MutationRestrictChildrenRow>
  restrictChildren({
    RivetWhere<MutationRestrictChildren>? where,
    RivetOrderBy<MutationRestrictChildren>? orderBy,
    int? limit,

    RivetIncludes<MutationRestrictChildrenInclude>? include,
  }) {
    final target = MutationRestrictChildren.db.buildSchema();

    final relationPath = path.isEmpty
        ? 'restrictChildren'
        : '$path.restrictChildren';
    return RivetInclude<MutationRestrictChildren, MutationRestrictChildrenRow>(
      name: 'restrictChildren',
      path: relationPath,
      relation: _schema.relations['restrictChildren']!,
      targetSchema: target,

      where: where,
      orderBy: orderBy,
      limit: limit,

      includes:
          include?.call(
            MutationRestrictChildrenInclude(target, path: relationPath),
          ) ??
          const [],
    );
  }
}

/// Generated row returned by reads from 'fbr141.delete Parents'.
final class MutationDeleteParentsRow {
  /// Creates a row from decoded column and relation values.
  const MutationDeleteParentsRow({
    required this.id,
    required this.label,
    this.cascadeChildren = const Relation.unloaded(),
    this.restrictChildren = const Relation.unloaded(),
  });

  /// Value read from `id`.
  final int id;

  /// Value read from `label`.
  final String label;

  /// Loaded or unloaded `cascadeChildren` relation.
  final Relation<List<MutationCascadeChildrenRow>> cascadeChildren;

  /// Loaded or unloaded `restrictChildren` relation.
  final Relation<List<MutationRestrictChildrenRow>> restrictChildren;
}

/// Generated values accepted by mutations of 'fbr141.delete Parents'.
final class MutationDeleteParentsCompanion
    implements RivetCompanion<MutationDeleteParents> {
  const MutationDeleteParentsCompanion._({
    required this.id,
    required this.label,
  });

  /// Creates values for an insert, leaving defaulted columns absent.
  factory MutationDeleteParentsCompanion.insert({
    required RivetValue<MutationDeleteParents, int, int> id,
    required RivetValue<MutationDeleteParents, String, String> label,
  }) => MutationDeleteParentsCompanion._(id: id, label: label);

  /// Creates values for an update, leaving untouched columns absent.
  factory MutationDeleteParentsCompanion.update({
    RivetValue<MutationDeleteParents, int, int> id = const RivetValue.absent(),
    RivetValue<MutationDeleteParents, String, String> label =
        const RivetValue.absent(),
  }) => MutationDeleteParentsCompanion._(id: id, label: label);

  /// Mutation value for `id`.
  final RivetValue<MutationDeleteParents, int, int> id;

  /// Mutation value for `label`.
  final RivetValue<MutationDeleteParents, String, String> label;

  /// The generated column assignments in declaration order.
  @override
  List<RivetAssignment<MutationDeleteParents>> operator [](
    RivetCompanionKey key,
  ) => [RivetAssignment('id', id), RivetAssignment('label', label)];
}

final class _$MutationDeleteParentsDB
    extends
        RivetTableAccessor<MutationDeleteParents, MutationDeleteParentsRow> {
  const _$MutationDeleteParentsDB();

  @override
  RivetTableSchema<MutationDeleteParents, MutationDeleteParentsRow>
  buildSchema() {
    MutationDeleteParents createDefinition() {
      final definition = MutationDeleteParents();

      return definition;
    }

    final definition = createDefinition();
    MutationDeleteParentsRow decodeRow(
      List<Object?> values,
      List<bool> sqlNulls,
      RivetRelationValues relations, {
      required bool transport,
    }) => MutationDeleteParentsRow(
      id: transport
          ? definition.id.decodeTransportValue(
              values[0],
              isSqlNull: sqlNulls[0],
            )
          : definition.id.decodeValue(values[0], isSqlNull: sqlNulls[0]),
      label: transport
          ? definition.label.decodeTransportValue(
              values[1],
              isSqlNull: sqlNulls[1],
            )
          : definition.label.decodeValue(values[1], isSqlNull: sqlNulls[1]),
      cascadeChildren: relations.read('cascadeChildren'),
      restrictChildren: relations.read('restrictChildren'),
    );

    final builtSchema =
        RivetTableSchema<MutationDeleteParents, MutationDeleteParentsRow>(
          schemaName: 'fbr141',
          tableName: 'delete Parents',
          definition: definition,
          columns: [
            definition.id as RivetColumn<Object?>,
            definition.label as RivetColumn<Object?>,
          ],
          columnNames: ['id', 'label'],
          createDefinition: createDefinition,
          columnsFor: (definition) => [
            definition.id as RivetColumn<Object?>,
            definition.label as RivetColumn<Object?>,
          ],
          decode: (values, sqlNulls) => decodeRow(
            values,
            sqlNulls,
            const RivetRelationValues(),
            transport: false,
          ),
          decodeRelated: decodeRow,

          relations: {
            'cascadeChildren':
                definition.cascadeChildren as RivetRelationDescriptor<Object?>,
            'restrictChildren':
                definition.restrictChildren as RivetRelationDescriptor<Object?>,
          },
        );
    definition.cascadeChildren.bind(
      name: 'cascadeChildren',
      ownerSchema: builtSchema,
      targetSchema: () => MutationCascadeChildren.db.buildSchema(),
    );
    definition.restrictChildren.bind(
      name: 'restrictChildren',
      ownerSchema: builtSchema,
      targetSchema: () => MutationRestrictChildren.db.buildSchema(),
    );
    return builtSchema;
  }

  /// Creates a reusable read plan with typed relation includes.
  RivetFind<MutationDeleteParents, MutationDeleteParentsRow> find({
    RivetWhere<MutationDeleteParents>? where,
    RivetOrderBy<MutationDeleteParents>? orderBy,
    int? limit,
    int? offset,
    RivetIncludes<MutationDeleteParentsInclude>? include,
  }) {
    final schema = buildSchema();
    return RivetFind(
      schema,
      where: where,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
      includes: include?.call(MutationDeleteParentsInclude(schema)) ?? const [],
    );
  }

  /// Creates a reusable insert plan.
  RivetInsert<MutationDeleteParents, MutationDeleteParentsRow> insert(
    MutationDeleteParentsCompanion companion, {
    RivetOnConflict<MutationDeleteParents>? onConflict,
  }) => RivetInsert(buildSchema(), companion, onConflict: onConflict);

  /// Creates a reusable batch insert plan.
  RivetInsertMany<MutationDeleteParents, MutationDeleteParentsRow> insertMany(
    Iterable<MutationDeleteParentsCompanion> companions, {
    RivetOnConflict<MutationDeleteParents>? onConflict,
  }) => RivetInsertMany(buildSchema(), companions, onConflict: onConflict);

  /// Creates a reusable update plan.
  RivetUpdate<MutationDeleteParents, MutationDeleteParentsRow> update(
    MutationDeleteParentsCompanion companion, {
    RivetWhere<MutationDeleteParents>? where,
  }) => RivetUpdate(buildSchema(), companion, where: where);

  /// Creates a reusable delete plan.
  RivetDelete<MutationDeleteParents, MutationDeleteParentsRow> delete({
    RivetWhere<MutationDeleteParents>? where,
  }) => RivetDelete(buildSchema(), where: where);
}

/// Typed relation include scope for [MutationCascadeChildren].
final class MutationCascadeChildrenInclude {
  /// Creates the generated include scope.
  const MutationCascadeChildrenInclude(this._schema, {this.path = ''});

  final RivetTableSchema<MutationCascadeChildren, MutationCascadeChildrenRow>
  _schema;

  /// Full relation path used in diagnostics.
  final String path;

  /// Includes the [parent] relation.
  RivetInclude<MutationDeleteParents, MutationDeleteParentsRow> parent({
    RivetWhere<MutationDeleteParents>? where,

    RivetIncludes<MutationDeleteParentsInclude>? include,
  }) {
    final target = MutationDeleteParents.db.buildSchema();

    final relationPath = path.isEmpty ? 'parent' : '$path.parent';
    return RivetInclude<MutationDeleteParents, MutationDeleteParentsRow>(
      name: 'parent',
      path: relationPath,
      relation: _schema.relations['parent']!,
      targetSchema: target,

      where: where,

      includes:
          include?.call(
            MutationDeleteParentsInclude(target, path: relationPath),
          ) ??
          const [],
    );
  }
}

/// Generated row returned by reads from 'fbr141.cascade Children'.
final class MutationCascadeChildrenRow {
  /// Creates a row from decoded column and relation values.
  const MutationCascadeChildrenRow({
    required this.id,
    required this.parentId,
    this.parent = const Relation.unloaded(),
  });

  /// Value read from `id`.
  final int id;

  /// Value read from `parentId`.
  final int parentId;

  /// Loaded or unloaded `parent` relation.
  final Relation<MutationDeleteParentsRow?> parent;
}

/// Generated values accepted by mutations of 'fbr141.cascade Children'.
final class MutationCascadeChildrenCompanion
    implements RivetCompanion<MutationCascadeChildren> {
  const MutationCascadeChildrenCompanion._({
    required this.id,
    required this.parentId,
  });

  /// Creates values for an insert, leaving defaulted columns absent.
  factory MutationCascadeChildrenCompanion.insert({
    required RivetValue<MutationCascadeChildren, int, int> id,
    required RivetValue<MutationCascadeChildren, int, int> parentId,
  }) => MutationCascadeChildrenCompanion._(id: id, parentId: parentId);

  /// Creates values for an update, leaving untouched columns absent.
  factory MutationCascadeChildrenCompanion.update({
    RivetValue<MutationCascadeChildren, int, int> id =
        const RivetValue.absent(),
    RivetValue<MutationCascadeChildren, int, int> parentId =
        const RivetValue.absent(),
  }) => MutationCascadeChildrenCompanion._(id: id, parentId: parentId);

  /// Mutation value for `id`.
  final RivetValue<MutationCascadeChildren, int, int> id;

  /// Mutation value for `parentId`.
  final RivetValue<MutationCascadeChildren, int, int> parentId;

  /// The generated column assignments in declaration order.
  @override
  List<RivetAssignment<MutationCascadeChildren>> operator [](
    RivetCompanionKey key,
  ) => [RivetAssignment('id', id), RivetAssignment('parentId', parentId)];
}

final class _$MutationCascadeChildrenDB
    extends
        RivetTableAccessor<
          MutationCascadeChildren,
          MutationCascadeChildrenRow
        > {
  const _$MutationCascadeChildrenDB();

  @override
  RivetTableSchema<MutationCascadeChildren, MutationCascadeChildrenRow>
  buildSchema() {
    MutationCascadeChildren createDefinition() {
      final definition = MutationCascadeChildren();

      return definition;
    }

    final definition = createDefinition();
    MutationCascadeChildrenRow decodeRow(
      List<Object?> values,
      List<bool> sqlNulls,
      RivetRelationValues relations, {
      required bool transport,
    }) => MutationCascadeChildrenRow(
      id: transport
          ? definition.id.decodeTransportValue(
              values[0],
              isSqlNull: sqlNulls[0],
            )
          : definition.id.decodeValue(values[0], isSqlNull: sqlNulls[0]),
      parentId: transport
          ? definition.parentId.decodeTransportValue(
              values[1],
              isSqlNull: sqlNulls[1],
            )
          : definition.parentId.decodeValue(values[1], isSqlNull: sqlNulls[1]),
      parent: relations.read('parent'),
    );

    final builtSchema =
        RivetTableSchema<MutationCascadeChildren, MutationCascadeChildrenRow>(
          schemaName: 'fbr141',
          tableName: 'cascade Children',
          definition: definition,
          columns: [
            definition.id as RivetColumn<Object?>,
            definition.parentId as RivetColumn<Object?>,
          ],
          columnNames: ['id', 'parentId'],
          createDefinition: createDefinition,
          columnsFor: (definition) => [
            definition.id as RivetColumn<Object?>,
            definition.parentId as RivetColumn<Object?>,
          ],
          decode: (values, sqlNulls) => decodeRow(
            values,
            sqlNulls,
            const RivetRelationValues(),
            transport: false,
          ),
          decodeRelated: decodeRow,

          relations: {
            'parent': definition.parent as RivetRelationDescriptor<Object?>,
          },
        );
    definition.parent.bind(
      name: 'parent',
      ownerSchema: builtSchema,
      targetSchema: () => MutationDeleteParents.db.buildSchema(),
    );
    return builtSchema;
  }

  /// Creates a reusable read plan with typed relation includes.
  RivetFind<MutationCascadeChildren, MutationCascadeChildrenRow> find({
    RivetWhere<MutationCascadeChildren>? where,
    RivetOrderBy<MutationCascadeChildren>? orderBy,
    int? limit,
    int? offset,
    RivetIncludes<MutationCascadeChildrenInclude>? include,
  }) {
    final schema = buildSchema();
    return RivetFind(
      schema,
      where: where,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
      includes:
          include?.call(MutationCascadeChildrenInclude(schema)) ?? const [],
    );
  }

  /// Creates a reusable insert plan.
  RivetInsert<MutationCascadeChildren, MutationCascadeChildrenRow> insert(
    MutationCascadeChildrenCompanion companion, {
    RivetOnConflict<MutationCascadeChildren>? onConflict,
  }) => RivetInsert(buildSchema(), companion, onConflict: onConflict);

  /// Creates a reusable batch insert plan.
  RivetInsertMany<MutationCascadeChildren, MutationCascadeChildrenRow>
  insertMany(
    Iterable<MutationCascadeChildrenCompanion> companions, {
    RivetOnConflict<MutationCascadeChildren>? onConflict,
  }) => RivetInsertMany(buildSchema(), companions, onConflict: onConflict);

  /// Creates a reusable update plan.
  RivetUpdate<MutationCascadeChildren, MutationCascadeChildrenRow> update(
    MutationCascadeChildrenCompanion companion, {
    RivetWhere<MutationCascadeChildren>? where,
  }) => RivetUpdate(buildSchema(), companion, where: where);

  /// Creates a reusable delete plan.
  RivetDelete<MutationCascadeChildren, MutationCascadeChildrenRow> delete({
    RivetWhere<MutationCascadeChildren>? where,
  }) => RivetDelete(buildSchema(), where: where);
}

/// Typed relation include scope for [MutationRestrictChildren].
final class MutationRestrictChildrenInclude {
  /// Creates the generated include scope.
  const MutationRestrictChildrenInclude(this._schema, {this.path = ''});

  final RivetTableSchema<MutationRestrictChildren, MutationRestrictChildrenRow>
  _schema;

  /// Full relation path used in diagnostics.
  final String path;

  /// Includes the [parent] relation.
  RivetInclude<MutationDeleteParents, MutationDeleteParentsRow> parent({
    RivetWhere<MutationDeleteParents>? where,

    RivetIncludes<MutationDeleteParentsInclude>? include,
  }) {
    final target = MutationDeleteParents.db.buildSchema();

    final relationPath = path.isEmpty ? 'parent' : '$path.parent';
    return RivetInclude<MutationDeleteParents, MutationDeleteParentsRow>(
      name: 'parent',
      path: relationPath,
      relation: _schema.relations['parent']!,
      targetSchema: target,

      where: where,

      includes:
          include?.call(
            MutationDeleteParentsInclude(target, path: relationPath),
          ) ??
          const [],
    );
  }
}

/// Generated row returned by reads from 'fbr141.restrict Children'.
final class MutationRestrictChildrenRow {
  /// Creates a row from decoded column and relation values.
  const MutationRestrictChildrenRow({
    required this.id,
    required this.parentId,
    this.parent = const Relation.unloaded(),
  });

  /// Value read from `id`.
  final int id;

  /// Value read from `parentId`.
  final int parentId;

  /// Loaded or unloaded `parent` relation.
  final Relation<MutationDeleteParentsRow?> parent;
}

/// Generated values accepted by mutations of 'fbr141.restrict Children'.
final class MutationRestrictChildrenCompanion
    implements RivetCompanion<MutationRestrictChildren> {
  const MutationRestrictChildrenCompanion._({
    required this.id,
    required this.parentId,
  });

  /// Creates values for an insert, leaving defaulted columns absent.
  factory MutationRestrictChildrenCompanion.insert({
    required RivetValue<MutationRestrictChildren, int, int> id,
    required RivetValue<MutationRestrictChildren, int, int> parentId,
  }) => MutationRestrictChildrenCompanion._(id: id, parentId: parentId);

  /// Creates values for an update, leaving untouched columns absent.
  factory MutationRestrictChildrenCompanion.update({
    RivetValue<MutationRestrictChildren, int, int> id =
        const RivetValue.absent(),
    RivetValue<MutationRestrictChildren, int, int> parentId =
        const RivetValue.absent(),
  }) => MutationRestrictChildrenCompanion._(id: id, parentId: parentId);

  /// Mutation value for `id`.
  final RivetValue<MutationRestrictChildren, int, int> id;

  /// Mutation value for `parentId`.
  final RivetValue<MutationRestrictChildren, int, int> parentId;

  /// The generated column assignments in declaration order.
  @override
  List<RivetAssignment<MutationRestrictChildren>> operator [](
    RivetCompanionKey key,
  ) => [RivetAssignment('id', id), RivetAssignment('parentId', parentId)];
}

final class _$MutationRestrictChildrenDB
    extends
        RivetTableAccessor<
          MutationRestrictChildren,
          MutationRestrictChildrenRow
        > {
  const _$MutationRestrictChildrenDB();

  @override
  RivetTableSchema<MutationRestrictChildren, MutationRestrictChildrenRow>
  buildSchema() {
    MutationRestrictChildren createDefinition() {
      final definition = MutationRestrictChildren();

      return definition;
    }

    final definition = createDefinition();
    MutationRestrictChildrenRow decodeRow(
      List<Object?> values,
      List<bool> sqlNulls,
      RivetRelationValues relations, {
      required bool transport,
    }) => MutationRestrictChildrenRow(
      id: transport
          ? definition.id.decodeTransportValue(
              values[0],
              isSqlNull: sqlNulls[0],
            )
          : definition.id.decodeValue(values[0], isSqlNull: sqlNulls[0]),
      parentId: transport
          ? definition.parentId.decodeTransportValue(
              values[1],
              isSqlNull: sqlNulls[1],
            )
          : definition.parentId.decodeValue(values[1], isSqlNull: sqlNulls[1]),
      parent: relations.read('parent'),
    );

    final builtSchema =
        RivetTableSchema<MutationRestrictChildren, MutationRestrictChildrenRow>(
          schemaName: 'fbr141',
          tableName: 'restrict Children',
          definition: definition,
          columns: [
            definition.id as RivetColumn<Object?>,
            definition.parentId as RivetColumn<Object?>,
          ],
          columnNames: ['id', 'parentId'],
          createDefinition: createDefinition,
          columnsFor: (definition) => [
            definition.id as RivetColumn<Object?>,
            definition.parentId as RivetColumn<Object?>,
          ],
          decode: (values, sqlNulls) => decodeRow(
            values,
            sqlNulls,
            const RivetRelationValues(),
            transport: false,
          ),
          decodeRelated: decodeRow,

          relations: {
            'parent': definition.parent as RivetRelationDescriptor<Object?>,
          },
        );
    definition.parent.bind(
      name: 'parent',
      ownerSchema: builtSchema,
      targetSchema: () => MutationDeleteParents.db.buildSchema(),
    );
    return builtSchema;
  }

  /// Creates a reusable read plan with typed relation includes.
  RivetFind<MutationRestrictChildren, MutationRestrictChildrenRow> find({
    RivetWhere<MutationRestrictChildren>? where,
    RivetOrderBy<MutationRestrictChildren>? orderBy,
    int? limit,
    int? offset,
    RivetIncludes<MutationRestrictChildrenInclude>? include,
  }) {
    final schema = buildSchema();
    return RivetFind(
      schema,
      where: where,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
      includes:
          include?.call(MutationRestrictChildrenInclude(schema)) ?? const [],
    );
  }

  /// Creates a reusable insert plan.
  RivetInsert<MutationRestrictChildren, MutationRestrictChildrenRow> insert(
    MutationRestrictChildrenCompanion companion, {
    RivetOnConflict<MutationRestrictChildren>? onConflict,
  }) => RivetInsert(buildSchema(), companion, onConflict: onConflict);

  /// Creates a reusable batch insert plan.
  RivetInsertMany<MutationRestrictChildren, MutationRestrictChildrenRow>
  insertMany(
    Iterable<MutationRestrictChildrenCompanion> companions, {
    RivetOnConflict<MutationRestrictChildren>? onConflict,
  }) => RivetInsertMany(buildSchema(), companions, onConflict: onConflict);

  /// Creates a reusable update plan.
  RivetUpdate<MutationRestrictChildren, MutationRestrictChildrenRow> update(
    MutationRestrictChildrenCompanion companion, {
    RivetWhere<MutationRestrictChildren>? where,
  }) => RivetUpdate(buildSchema(), companion, where: where);

  /// Creates a reusable delete plan.
  RivetDelete<MutationRestrictChildren, MutationRestrictChildrenRow> delete({
    RivetWhere<MutationRestrictChildren>? where,
  }) => RivetDelete(buildSchema(), where: where);
}

/// Typed relation include scope for [MutationBatchParents].
final class MutationBatchParentsInclude {
  /// Creates the generated include scope.
  const MutationBatchParentsInclude(this._schema, {this.path = ''});

  final RivetTableSchema<MutationBatchParents, MutationBatchParentsRow> _schema;

  /// Full relation path used in diagnostics.
  final String path;

  /// Includes the [children] relation.
  RivetInclude<MutationBatchChildren, MutationBatchChildrenRow> children({
    RivetWhere<MutationBatchChildren>? where,
    RivetOrderBy<MutationBatchChildren>? orderBy,
    int? limit,

    RivetIncludes<MutationBatchChildrenInclude>? include,
  }) {
    final target = MutationBatchChildren.db.buildSchema();

    final relationPath = path.isEmpty ? 'children' : '$path.children';
    return RivetInclude<MutationBatchChildren, MutationBatchChildrenRow>(
      name: 'children',
      path: relationPath,
      relation: _schema.relations['children']!,
      targetSchema: target,

      where: where,
      orderBy: orderBy,
      limit: limit,

      includes:
          include?.call(
            MutationBatchChildrenInclude(target, path: relationPath),
          ) ??
          const [],
    );
  }
}

/// Generated row returned by reads from 'fbr142.mutationBatchParents'.
final class MutationBatchParentsRow {
  /// Creates a row from decoded column and relation values.
  const MutationBatchParentsRow({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.nickname,
    required this.serverValue,
    this.children = const Relation.unloaded(),
  });

  /// Value read from `id`.
  final int id;

  /// Value read from `name`.
  final String name;

  /// Value read from `createdAt`.
  final DateTime createdAt;

  /// Value read from `nickname`.
  final String? nickname;

  /// Value read from `serverValue`.
  final int serverValue;

  /// Loaded or unloaded `children` relation.
  final Relation<List<MutationBatchChildrenRow>> children;
}

/// Generated values accepted by mutations of 'fbr142.mutationBatchParents'.
final class MutationBatchParentsCompanion
    implements RivetCompanion<MutationBatchParents> {
  const MutationBatchParentsCompanion._({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.nickname,
    required this.serverValue,
  });

  /// Creates values for an insert, leaving defaulted columns absent.
  factory MutationBatchParentsCompanion.insert({
    required RivetValue<MutationBatchParents, int, int> id,
    required RivetValue<MutationBatchParents, String, String> name,
    RivetValue<MutationBatchParents, DateTime, DateTime> createdAt =
        const RivetValue.absent(),
    RivetValue<MutationBatchParents, String?, String?> nickname =
        const RivetValue.absent(),
    RivetValue<MutationBatchParents, int, int> serverValue =
        const RivetValue.absent(),
  }) => MutationBatchParentsCompanion._(
    id: id,
    name: name,
    createdAt: createdAt,
    nickname: nickname,
    serverValue: serverValue,
  );

  /// Creates values for an update, leaving untouched columns absent.
  factory MutationBatchParentsCompanion.update({
    RivetValue<MutationBatchParents, int, int> id = const RivetValue.absent(),
    RivetValue<MutationBatchParents, String, String> name =
        const RivetValue.absent(),
    RivetValue<MutationBatchParents, DateTime, DateTime> createdAt =
        const RivetValue.absent(),
    RivetValue<MutationBatchParents, String?, String?> nickname =
        const RivetValue.absent(),
    RivetValue<MutationBatchParents, int, int> serverValue =
        const RivetValue.absent(),
  }) => MutationBatchParentsCompanion._(
    id: id,
    name: name,
    createdAt: createdAt,
    nickname: nickname,
    serverValue: serverValue,
  );

  /// Mutation value for `id`.
  final RivetValue<MutationBatchParents, int, int> id;

  /// Mutation value for `name`.
  final RivetValue<MutationBatchParents, String, String> name;

  /// Mutation value for `createdAt`.
  final RivetValue<MutationBatchParents, DateTime, DateTime> createdAt;

  /// Mutation value for `nickname`.
  final RivetValue<MutationBatchParents, String?, String?> nickname;

  /// Mutation value for `serverValue`.
  final RivetValue<MutationBatchParents, int, int> serverValue;

  /// The generated column assignments in declaration order.
  @override
  List<RivetAssignment<MutationBatchParents>> operator [](
    RivetCompanionKey key,
  ) => [
    RivetAssignment('id', id),
    RivetAssignment('name', name),
    RivetAssignment('createdAt', createdAt),
    RivetAssignment('nickname', nickname),
    RivetAssignment('serverValue', serverValue),
  ];
}

final class _$MutationBatchParentsDB
    extends RivetTableAccessor<MutationBatchParents, MutationBatchParentsRow> {
  const _$MutationBatchParentsDB();

  @override
  RivetTableSchema<MutationBatchParents, MutationBatchParentsRow>
  buildSchema() {
    MutationBatchParents createDefinition() {
      final definition = MutationBatchParents();

      return definition;
    }

    final definition = createDefinition();
    MutationBatchParentsRow decodeRow(
      List<Object?> values,
      List<bool> sqlNulls,
      RivetRelationValues relations, {
      required bool transport,
    }) => MutationBatchParentsRow(
      id: transport
          ? definition.id.decodeTransportValue(
              values[0],
              isSqlNull: sqlNulls[0],
            )
          : definition.id.decodeValue(values[0], isSqlNull: sqlNulls[0]),
      name: transport
          ? definition.name.decodeTransportValue(
              values[1],
              isSqlNull: sqlNulls[1],
            )
          : definition.name.decodeValue(values[1], isSqlNull: sqlNulls[1]),
      createdAt: transport
          ? definition.createdAt.decodeTransportValue(
              values[2],
              isSqlNull: sqlNulls[2],
            )
          : definition.createdAt.decodeValue(values[2], isSqlNull: sqlNulls[2]),
      nickname: transport
          ? definition.nickname.decodeTransportValue(
              values[3],
              isSqlNull: sqlNulls[3],
            )
          : definition.nickname.decodeValue(values[3], isSqlNull: sqlNulls[3]),
      serverValue: transport
          ? definition.serverValue.decodeTransportValue(
              values[4],
              isSqlNull: sqlNulls[4],
            )
          : definition.serverValue.decodeValue(
              values[4],
              isSqlNull: sqlNulls[4],
            ),
      children: relations.read('children'),
    );

    final builtSchema =
        RivetTableSchema<MutationBatchParents, MutationBatchParentsRow>(
          schemaName: 'fbr142',
          tableName: 'mutationBatchParents',
          definition: definition,
          columns: [
            definition.id as RivetColumn<Object?>,
            definition.name as RivetColumn<Object?>,
            definition.createdAt as RivetColumn<Object?>,
            definition.nickname as RivetColumn<Object?>,
            definition.serverValue as RivetColumn<Object?>,
          ],
          columnNames: ['id', 'name', 'createdAt', 'nickname', 'serverValue'],
          createDefinition: createDefinition,
          columnsFor: (definition) => [
            definition.id as RivetColumn<Object?>,
            definition.name as RivetColumn<Object?>,
            definition.createdAt as RivetColumn<Object?>,
            definition.nickname as RivetColumn<Object?>,
            definition.serverValue as RivetColumn<Object?>,
          ],
          decode: (values, sqlNulls) => decodeRow(
            values,
            sqlNulls,
            const RivetRelationValues(),
            transport: false,
          ),
          decodeRelated: decodeRow,

          relations: {
            'children': definition.children as RivetRelationDescriptor<Object?>,
          },
        );
    definition.children.bind(
      name: 'children',
      ownerSchema: builtSchema,
      targetSchema: () => MutationBatchChildren.db.buildSchema(),
    );
    return builtSchema;
  }

  /// Creates a reusable read plan with typed relation includes.
  RivetFind<MutationBatchParents, MutationBatchParentsRow> find({
    RivetWhere<MutationBatchParents>? where,
    RivetOrderBy<MutationBatchParents>? orderBy,
    int? limit,
    int? offset,
    RivetIncludes<MutationBatchParentsInclude>? include,
  }) {
    final schema = buildSchema();
    return RivetFind(
      schema,
      where: where,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
      includes: include?.call(MutationBatchParentsInclude(schema)) ?? const [],
    );
  }

  /// Creates a reusable insert plan.
  RivetInsert<MutationBatchParents, MutationBatchParentsRow> insert(
    MutationBatchParentsCompanion companion, {
    RivetOnConflict<MutationBatchParents>? onConflict,
  }) => RivetInsert(buildSchema(), companion, onConflict: onConflict);

  /// Creates a reusable batch insert plan.
  RivetInsertMany<MutationBatchParents, MutationBatchParentsRow> insertMany(
    Iterable<MutationBatchParentsCompanion> companions, {
    RivetOnConflict<MutationBatchParents>? onConflict,
  }) => RivetInsertMany(buildSchema(), companions, onConflict: onConflict);

  /// Creates a reusable update plan.
  RivetUpdate<MutationBatchParents, MutationBatchParentsRow> update(
    MutationBatchParentsCompanion companion, {
    RivetWhere<MutationBatchParents>? where,
  }) => RivetUpdate(buildSchema(), companion, where: where);

  /// Creates a reusable delete plan.
  RivetDelete<MutationBatchParents, MutationBatchParentsRow> delete({
    RivetWhere<MutationBatchParents>? where,
  }) => RivetDelete(buildSchema(), where: where);
}

/// Typed relation include scope for [MutationBatchChildren].
final class MutationBatchChildrenInclude {
  /// Creates the generated include scope.
  const MutationBatchChildrenInclude(this._schema, {this.path = ''});

  final RivetTableSchema<MutationBatchChildren, MutationBatchChildrenRow>
  _schema;

  /// Full relation path used in diagnostics.
  final String path;

  /// Includes the [parent] relation.
  RivetInclude<MutationBatchParents, MutationBatchParentsRow> parent({
    RivetWhere<MutationBatchParents>? where,

    RivetIncludes<MutationBatchParentsInclude>? include,
  }) {
    final target = MutationBatchParents.db.buildSchema();

    final relationPath = path.isEmpty ? 'parent' : '$path.parent';
    return RivetInclude<MutationBatchParents, MutationBatchParentsRow>(
      name: 'parent',
      path: relationPath,
      relation: _schema.relations['parent']!,
      targetSchema: target,

      where: where,

      includes:
          include?.call(
            MutationBatchParentsInclude(target, path: relationPath),
          ) ??
          const [],
    );
  }
}

/// Generated row returned by reads from 'fbr142.mutationBatchChildren'.
final class MutationBatchChildrenRow {
  /// Creates a row from decoded column and relation values.
  const MutationBatchChildrenRow({
    required this.id,
    required this.parentId,
    this.parent = const Relation.unloaded(),
  });

  /// Value read from `id`.
  final int id;

  /// Value read from `parentId`.
  final int parentId;

  /// Loaded or unloaded `parent` relation.
  final Relation<MutationBatchParentsRow?> parent;
}

/// Generated values accepted by mutations of 'fbr142.mutationBatchChildren'.
final class MutationBatchChildrenCompanion
    implements RivetCompanion<MutationBatchChildren> {
  const MutationBatchChildrenCompanion._({
    required this.id,
    required this.parentId,
  });

  /// Creates values for an insert, leaving defaulted columns absent.
  factory MutationBatchChildrenCompanion.insert({
    required RivetValue<MutationBatchChildren, int, int> id,
    required RivetValue<MutationBatchChildren, int, int> parentId,
  }) => MutationBatchChildrenCompanion._(id: id, parentId: parentId);

  /// Creates values for an update, leaving untouched columns absent.
  factory MutationBatchChildrenCompanion.update({
    RivetValue<MutationBatchChildren, int, int> id = const RivetValue.absent(),
    RivetValue<MutationBatchChildren, int, int> parentId =
        const RivetValue.absent(),
  }) => MutationBatchChildrenCompanion._(id: id, parentId: parentId);

  /// Mutation value for `id`.
  final RivetValue<MutationBatchChildren, int, int> id;

  /// Mutation value for `parentId`.
  final RivetValue<MutationBatchChildren, int, int> parentId;

  /// The generated column assignments in declaration order.
  @override
  List<RivetAssignment<MutationBatchChildren>> operator [](
    RivetCompanionKey key,
  ) => [RivetAssignment('id', id), RivetAssignment('parentId', parentId)];
}

final class _$MutationBatchChildrenDB
    extends
        RivetTableAccessor<MutationBatchChildren, MutationBatchChildrenRow> {
  const _$MutationBatchChildrenDB();

  @override
  RivetTableSchema<MutationBatchChildren, MutationBatchChildrenRow>
  buildSchema() {
    MutationBatchChildren createDefinition() {
      final definition = MutationBatchChildren();

      return definition;
    }

    final definition = createDefinition();
    MutationBatchChildrenRow decodeRow(
      List<Object?> values,
      List<bool> sqlNulls,
      RivetRelationValues relations, {
      required bool transport,
    }) => MutationBatchChildrenRow(
      id: transport
          ? definition.id.decodeTransportValue(
              values[0],
              isSqlNull: sqlNulls[0],
            )
          : definition.id.decodeValue(values[0], isSqlNull: sqlNulls[0]),
      parentId: transport
          ? definition.parentId.decodeTransportValue(
              values[1],
              isSqlNull: sqlNulls[1],
            )
          : definition.parentId.decodeValue(values[1], isSqlNull: sqlNulls[1]),
      parent: relations.read('parent'),
    );

    final builtSchema =
        RivetTableSchema<MutationBatchChildren, MutationBatchChildrenRow>(
          schemaName: 'fbr142',
          tableName: 'mutationBatchChildren',
          definition: definition,
          columns: [
            definition.id as RivetColumn<Object?>,
            definition.parentId as RivetColumn<Object?>,
          ],
          columnNames: ['id', 'parentId'],
          createDefinition: createDefinition,
          columnsFor: (definition) => [
            definition.id as RivetColumn<Object?>,
            definition.parentId as RivetColumn<Object?>,
          ],
          decode: (values, sqlNulls) => decodeRow(
            values,
            sqlNulls,
            const RivetRelationValues(),
            transport: false,
          ),
          decodeRelated: decodeRow,

          relations: {
            'parent': definition.parent as RivetRelationDescriptor<Object?>,
          },
        );
    definition.parent.bind(
      name: 'parent',
      ownerSchema: builtSchema,
      targetSchema: () => MutationBatchParents.db.buildSchema(),
    );
    return builtSchema;
  }

  /// Creates a reusable read plan with typed relation includes.
  RivetFind<MutationBatchChildren, MutationBatchChildrenRow> find({
    RivetWhere<MutationBatchChildren>? where,
    RivetOrderBy<MutationBatchChildren>? orderBy,
    int? limit,
    int? offset,
    RivetIncludes<MutationBatchChildrenInclude>? include,
  }) {
    final schema = buildSchema();
    return RivetFind(
      schema,
      where: where,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
      includes: include?.call(MutationBatchChildrenInclude(schema)) ?? const [],
    );
  }

  /// Creates a reusable insert plan.
  RivetInsert<MutationBatchChildren, MutationBatchChildrenRow> insert(
    MutationBatchChildrenCompanion companion, {
    RivetOnConflict<MutationBatchChildren>? onConflict,
  }) => RivetInsert(buildSchema(), companion, onConflict: onConflict);

  /// Creates a reusable batch insert plan.
  RivetInsertMany<MutationBatchChildren, MutationBatchChildrenRow> insertMany(
    Iterable<MutationBatchChildrenCompanion> companions, {
    RivetOnConflict<MutationBatchChildren>? onConflict,
  }) => RivetInsertMany(buildSchema(), companions, onConflict: onConflict);

  /// Creates a reusable update plan.
  RivetUpdate<MutationBatchChildren, MutationBatchChildrenRow> update(
    MutationBatchChildrenCompanion companion, {
    RivetWhere<MutationBatchChildren>? where,
  }) => RivetUpdate(buildSchema(), companion, where: where);

  /// Creates a reusable delete plan.
  RivetDelete<MutationBatchChildren, MutationBatchChildrenRow> delete({
    RivetWhere<MutationBatchChildren>? where,
  }) => RivetDelete(buildSchema(), where: where);
}

/// Generated row returned by reads from 'fbr143.mutationConflictGroups'.
final class MutationConflictGroupsRow {
  /// Creates a row from decoded column and relation values.
  const MutationConflictGroupsRow({required this.id});

  /// Value read from `id`.
  final int id;
}

/// Generated values accepted by mutations of 'fbr143.mutationConflictGroups'.
final class MutationConflictGroupsCompanion
    implements RivetCompanion<MutationConflictGroups> {
  const MutationConflictGroupsCompanion._({required this.id});

  /// Creates values for an insert, leaving defaulted columns absent.
  factory MutationConflictGroupsCompanion.insert({
    required RivetValue<MutationConflictGroups, int, int> id,
  }) => MutationConflictGroupsCompanion._(id: id);

  /// Creates values for an update, leaving untouched columns absent.
  factory MutationConflictGroupsCompanion.update({
    RivetValue<MutationConflictGroups, int, int> id = const RivetValue.absent(),
  }) => MutationConflictGroupsCompanion._(id: id);

  /// Mutation value for `id`.
  final RivetValue<MutationConflictGroups, int, int> id;

  /// The generated column assignments in declaration order.
  @override
  List<RivetAssignment<MutationConflictGroups>> operator [](
    RivetCompanionKey key,
  ) => [RivetAssignment('id', id)];
}

final class _$MutationConflictGroupsDB
    extends
        RivetTableAccessor<MutationConflictGroups, MutationConflictGroupsRow> {
  const _$MutationConflictGroupsDB();

  @override
  RivetTableSchema<MutationConflictGroups, MutationConflictGroupsRow>
  buildSchema() {
    MutationConflictGroups createDefinition() {
      final definition = MutationConflictGroups();

      return definition;
    }

    final definition = createDefinition();

    return RivetTableSchema<MutationConflictGroups, MutationConflictGroupsRow>(
      schemaName: 'fbr143',
      tableName: 'mutationConflictGroups',
      definition: definition,
      columns: [definition.id as RivetColumn<Object?>],
      columnNames: ['id'],
      createDefinition: createDefinition,
      columnsFor: (definition) => [definition.id as RivetColumn<Object?>],
      decode: (values, sqlNulls) => MutationConflictGroupsRow(
        id: definition.id.decodeValue(values[0], isSqlNull: sqlNulls[0]),
      ),
    );
  }

  /// Creates a reusable insert plan.
  RivetInsert<MutationConflictGroups, MutationConflictGroupsRow> insert(
    MutationConflictGroupsCompanion companion, {
    RivetOnConflict<MutationConflictGroups>? onConflict,
  }) => RivetInsert(buildSchema(), companion, onConflict: onConflict);

  /// Creates a reusable batch insert plan.
  RivetInsertMany<MutationConflictGroups, MutationConflictGroupsRow> insertMany(
    Iterable<MutationConflictGroupsCompanion> companions, {
    RivetOnConflict<MutationConflictGroups>? onConflict,
  }) => RivetInsertMany(buildSchema(), companions, onConflict: onConflict);

  /// Creates a reusable update plan.
  RivetUpdate<MutationConflictGroups, MutationConflictGroupsRow> update(
    MutationConflictGroupsCompanion companion, {
    RivetWhere<MutationConflictGroups>? where,
  }) => RivetUpdate(buildSchema(), companion, where: where);

  /// Creates a reusable delete plan.
  RivetDelete<MutationConflictGroups, MutationConflictGroupsRow> delete({
    RivetWhere<MutationConflictGroups>? where,
  }) => RivetDelete(buildSchema(), where: where);
}

/// Typed relation include scope for [MutationConflictParents].
final class MutationConflictParentsInclude {
  /// Creates the generated include scope.
  const MutationConflictParentsInclude(this._schema, {this.path = ''});

  final RivetTableSchema<MutationConflictParents, MutationConflictParentsRow>
  _schema;

  /// Full relation path used in diagnostics.
  final String path;

  /// Includes the [children] relation.
  RivetInclude<MutationConflictChildren, MutationConflictChildrenRow> children({
    RivetWhere<MutationConflictChildren>? where,
    RivetOrderBy<MutationConflictChildren>? orderBy,
    int? limit,

    RivetIncludes<MutationConflictChildrenInclude>? include,
  }) {
    final target = MutationConflictChildren.db.buildSchema();

    final relationPath = path.isEmpty ? 'children' : '$path.children';
    return RivetInclude<MutationConflictChildren, MutationConflictChildrenRow>(
      name: 'children',
      path: relationPath,
      relation: _schema.relations['children']!,
      targetSchema: target,

      where: where,
      orderBy: orderBy,
      limit: limit,

      includes:
          include?.call(
            MutationConflictChildrenInclude(target, path: relationPath),
          ) ??
          const [],
    );
  }
}

/// Generated row returned by reads from 'fbr143.mutationConflictParents'.
final class MutationConflictParentsRow {
  /// Creates a row from decoded column and relation values.
  const MutationConflictParentsRow({
    required this.id,
    required this.email,
    required this.username,
    required this.active,
    required this.name,
    required this.age,
    required this.createdAt,
    required this.requiredByDatabase,
    required this.groupId,
    this.children = const Relation.unloaded(),
  });

  /// Value read from `id`.
  final int id;

  /// Value read from `email`.
  final String email;

  /// Value read from `username`.
  final String username;

  /// Value read from `active`.
  final bool active;

  /// Value read from `name`.
  final String name;

  /// Value read from `age`.
  final int age;

  /// Value read from `createdAt`.
  final DateTime createdAt;

  /// Value read from `requiredByDatabase`.
  final String? requiredByDatabase;

  /// Value read from `groupId`.
  final int? groupId;

  /// Loaded or unloaded `children` relation.
  final Relation<List<MutationConflictChildrenRow>> children;
}

/// Generated values accepted by mutations of 'fbr143.mutationConflictParents'.
final class MutationConflictParentsCompanion
    implements RivetCompanion<MutationConflictParents> {
  const MutationConflictParentsCompanion._({
    required this.id,
    required this.email,
    required this.username,
    required this.active,
    required this.name,
    required this.age,
    required this.createdAt,
    required this.requiredByDatabase,
    required this.groupId,
  });

  /// Creates values for an insert, leaving defaulted columns absent.
  factory MutationConflictParentsCompanion.insert({
    required RivetValue<MutationConflictParents, int, int> id,
    required RivetValue<MutationConflictParents, String, String> email,
    required RivetValue<MutationConflictParents, String, String> username,
    required RivetValue<MutationConflictParents, bool, bool> active,
    required RivetValue<MutationConflictParents, String, String> name,
    required RivetValue<MutationConflictParents, int, int> age,
    RivetValue<MutationConflictParents, DateTime, DateTime> createdAt =
        const RivetValue.absent(),
    RivetValue<MutationConflictParents, String?, String?> requiredByDatabase =
        const RivetValue.absent(),
    RivetValue<MutationConflictParents, int?, int?> groupId =
        const RivetValue.absent(),
  }) => MutationConflictParentsCompanion._(
    id: id,
    email: email,
    username: username,
    active: active,
    name: name,
    age: age,
    createdAt: createdAt,
    requiredByDatabase: requiredByDatabase,
    groupId: groupId,
  );

  /// Creates values for an update, leaving untouched columns absent.
  factory MutationConflictParentsCompanion.update({
    RivetValue<MutationConflictParents, int, int> id =
        const RivetValue.absent(),
    RivetValue<MutationConflictParents, String, String> email =
        const RivetValue.absent(),
    RivetValue<MutationConflictParents, String, String> username =
        const RivetValue.absent(),
    RivetValue<MutationConflictParents, bool, bool> active =
        const RivetValue.absent(),
    RivetValue<MutationConflictParents, String, String> name =
        const RivetValue.absent(),
    RivetValue<MutationConflictParents, int, int> age =
        const RivetValue.absent(),
    RivetValue<MutationConflictParents, DateTime, DateTime> createdAt =
        const RivetValue.absent(),
    RivetValue<MutationConflictParents, String?, String?> requiredByDatabase =
        const RivetValue.absent(),
    RivetValue<MutationConflictParents, int?, int?> groupId =
        const RivetValue.absent(),
  }) => MutationConflictParentsCompanion._(
    id: id,
    email: email,
    username: username,
    active: active,
    name: name,
    age: age,
    createdAt: createdAt,
    requiredByDatabase: requiredByDatabase,
    groupId: groupId,
  );

  /// Mutation value for `id`.
  final RivetValue<MutationConflictParents, int, int> id;

  /// Mutation value for `email`.
  final RivetValue<MutationConflictParents, String, String> email;

  /// Mutation value for `username`.
  final RivetValue<MutationConflictParents, String, String> username;

  /// Mutation value for `active`.
  final RivetValue<MutationConflictParents, bool, bool> active;

  /// Mutation value for `name`.
  final RivetValue<MutationConflictParents, String, String> name;

  /// Mutation value for `age`.
  final RivetValue<MutationConflictParents, int, int> age;

  /// Mutation value for `createdAt`.
  final RivetValue<MutationConflictParents, DateTime, DateTime> createdAt;

  /// Mutation value for `requiredByDatabase`.
  final RivetValue<MutationConflictParents, String?, String?>
  requiredByDatabase;

  /// Mutation value for `groupId`.
  final RivetValue<MutationConflictParents, int?, int?> groupId;

  /// The generated column assignments in declaration order.
  @override
  List<RivetAssignment<MutationConflictParents>> operator [](
    RivetCompanionKey key,
  ) => [
    RivetAssignment('id', id),
    RivetAssignment('email', email),
    RivetAssignment('username', username),
    RivetAssignment('active', active),
    RivetAssignment('name', name),
    RivetAssignment('age', age),
    RivetAssignment('createdAt', createdAt),
    RivetAssignment('requiredByDatabase', requiredByDatabase),
    RivetAssignment('groupId', groupId),
  ];
}

final class _$MutationConflictParentsDB
    extends
        RivetTableAccessor<
          MutationConflictParents,
          MutationConflictParentsRow
        > {
  const _$MutationConflictParentsDB();

  @override
  RivetTableSchema<MutationConflictParents, MutationConflictParentsRow>
  buildSchema() {
    MutationConflictParents createDefinition() {
      final definition = MutationConflictParents();

      return definition;
    }

    final definition = createDefinition();
    MutationConflictParentsRow decodeRow(
      List<Object?> values,
      List<bool> sqlNulls,
      RivetRelationValues relations, {
      required bool transport,
    }) => MutationConflictParentsRow(
      id: transport
          ? definition.id.decodeTransportValue(
              values[0],
              isSqlNull: sqlNulls[0],
            )
          : definition.id.decodeValue(values[0], isSqlNull: sqlNulls[0]),
      email: transport
          ? definition.email.decodeTransportValue(
              values[1],
              isSqlNull: sqlNulls[1],
            )
          : definition.email.decodeValue(values[1], isSqlNull: sqlNulls[1]),
      username: transport
          ? definition.username.decodeTransportValue(
              values[2],
              isSqlNull: sqlNulls[2],
            )
          : definition.username.decodeValue(values[2], isSqlNull: sqlNulls[2]),
      active: transport
          ? definition.active.decodeTransportValue(
              values[3],
              isSqlNull: sqlNulls[3],
            )
          : definition.active.decodeValue(values[3], isSqlNull: sqlNulls[3]),
      name: transport
          ? definition.name.decodeTransportValue(
              values[4],
              isSqlNull: sqlNulls[4],
            )
          : definition.name.decodeValue(values[4], isSqlNull: sqlNulls[4]),
      age: transport
          ? definition.age.decodeTransportValue(
              values[5],
              isSqlNull: sqlNulls[5],
            )
          : definition.age.decodeValue(values[5], isSqlNull: sqlNulls[5]),
      createdAt: transport
          ? definition.createdAt.decodeTransportValue(
              values[6],
              isSqlNull: sqlNulls[6],
            )
          : definition.createdAt.decodeValue(values[6], isSqlNull: sqlNulls[6]),
      requiredByDatabase: transport
          ? definition.requiredByDatabase.decodeTransportValue(
              values[7],
              isSqlNull: sqlNulls[7],
            )
          : definition.requiredByDatabase.decodeValue(
              values[7],
              isSqlNull: sqlNulls[7],
            ),
      groupId: transport
          ? definition.groupId.decodeTransportValue(
              values[8],
              isSqlNull: sqlNulls[8],
            )
          : definition.groupId.decodeValue(values[8], isSqlNull: sqlNulls[8]),
      children: relations.read('children'),
    );

    final builtSchema =
        RivetTableSchema<MutationConflictParents, MutationConflictParentsRow>(
          schemaName: 'fbr143',
          tableName: 'mutationConflictParents',
          definition: definition,
          columns: [
            definition.id as RivetColumn<Object?>,
            definition.email as RivetColumn<Object?>,
            definition.username as RivetColumn<Object?>,
            definition.active as RivetColumn<Object?>,
            definition.name as RivetColumn<Object?>,
            definition.age as RivetColumn<Object?>,
            definition.createdAt as RivetColumn<Object?>,
            definition.requiredByDatabase as RivetColumn<Object?>,
            definition.groupId as RivetColumn<Object?>,
          ],
          columnNames: [
            'id',
            'email',
            'username',
            'active',
            'name',
            'age',
            'createdAt',
            'requiredByDatabase',
            'groupId',
          ],
          createDefinition: createDefinition,
          columnsFor: (definition) => [
            definition.id as RivetColumn<Object?>,
            definition.email as RivetColumn<Object?>,
            definition.username as RivetColumn<Object?>,
            definition.active as RivetColumn<Object?>,
            definition.name as RivetColumn<Object?>,
            definition.age as RivetColumn<Object?>,
            definition.createdAt as RivetColumn<Object?>,
            definition.requiredByDatabase as RivetColumn<Object?>,
            definition.groupId as RivetColumn<Object?>,
          ],
          decode: (values, sqlNulls) => decodeRow(
            values,
            sqlNulls,
            const RivetRelationValues(),
            transport: false,
          ),
          decodeRelated: decodeRow,

          relations: {
            'children': definition.children as RivetRelationDescriptor<Object?>,
          },
        );
    definition.children.bind(
      name: 'children',
      ownerSchema: builtSchema,
      targetSchema: () => MutationConflictChildren.db.buildSchema(),
    );
    return builtSchema;
  }

  /// Creates a reusable read plan with typed relation includes.
  RivetFind<MutationConflictParents, MutationConflictParentsRow> find({
    RivetWhere<MutationConflictParents>? where,
    RivetOrderBy<MutationConflictParents>? orderBy,
    int? limit,
    int? offset,
    RivetIncludes<MutationConflictParentsInclude>? include,
  }) {
    final schema = buildSchema();
    return RivetFind(
      schema,
      where: where,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
      includes:
          include?.call(MutationConflictParentsInclude(schema)) ?? const [],
    );
  }

  /// Creates a reusable insert plan.
  RivetInsert<MutationConflictParents, MutationConflictParentsRow> insert(
    MutationConflictParentsCompanion companion, {
    RivetOnConflict<MutationConflictParents>? onConflict,
  }) => RivetInsert(buildSchema(), companion, onConflict: onConflict);

  /// Creates a reusable batch insert plan.
  RivetInsertMany<MutationConflictParents, MutationConflictParentsRow>
  insertMany(
    Iterable<MutationConflictParentsCompanion> companions, {
    RivetOnConflict<MutationConflictParents>? onConflict,
  }) => RivetInsertMany(buildSchema(), companions, onConflict: onConflict);

  /// Creates a reusable update plan.
  RivetUpdate<MutationConflictParents, MutationConflictParentsRow> update(
    MutationConflictParentsCompanion companion, {
    RivetWhere<MutationConflictParents>? where,
  }) => RivetUpdate(buildSchema(), companion, where: where);

  /// Creates a reusable delete plan.
  RivetDelete<MutationConflictParents, MutationConflictParentsRow> delete({
    RivetWhere<MutationConflictParents>? where,
  }) => RivetDelete(buildSchema(), where: where);
}

/// Typed relation include scope for [MutationConflictChildren].
final class MutationConflictChildrenInclude {
  /// Creates the generated include scope.
  const MutationConflictChildrenInclude(this._schema, {this.path = ''});

  final RivetTableSchema<MutationConflictChildren, MutationConflictChildrenRow>
  _schema;

  /// Full relation path used in diagnostics.
  final String path;

  /// Includes the [parent] relation.
  RivetInclude<MutationConflictParents, MutationConflictParentsRow> parent({
    RivetWhere<MutationConflictParents>? where,

    RivetIncludes<MutationConflictParentsInclude>? include,
  }) {
    final target = MutationConflictParents.db.buildSchema();

    final relationPath = path.isEmpty ? 'parent' : '$path.parent';
    return RivetInclude<MutationConflictParents, MutationConflictParentsRow>(
      name: 'parent',
      path: relationPath,
      relation: _schema.relations['parent']!,
      targetSchema: target,

      where: where,

      includes:
          include?.call(
            MutationConflictParentsInclude(target, path: relationPath),
          ) ??
          const [],
    );
  }
}

/// Generated row returned by reads from 'fbr143.mutationConflictChildren'.
final class MutationConflictChildrenRow {
  /// Creates a row from decoded column and relation values.
  const MutationConflictChildrenRow({
    required this.id,
    required this.parentId,
    this.parent = const Relation.unloaded(),
  });

  /// Value read from `id`.
  final int id;

  /// Value read from `parentId`.
  final int parentId;

  /// Loaded or unloaded `parent` relation.
  final Relation<MutationConflictParentsRow?> parent;
}

/// Generated values accepted by mutations of 'fbr143.mutationConflictChildren'.
final class MutationConflictChildrenCompanion
    implements RivetCompanion<MutationConflictChildren> {
  const MutationConflictChildrenCompanion._({
    required this.id,
    required this.parentId,
  });

  /// Creates values for an insert, leaving defaulted columns absent.
  factory MutationConflictChildrenCompanion.insert({
    required RivetValue<MutationConflictChildren, int, int> id,
    required RivetValue<MutationConflictChildren, int, int> parentId,
  }) => MutationConflictChildrenCompanion._(id: id, parentId: parentId);

  /// Creates values for an update, leaving untouched columns absent.
  factory MutationConflictChildrenCompanion.update({
    RivetValue<MutationConflictChildren, int, int> id =
        const RivetValue.absent(),
    RivetValue<MutationConflictChildren, int, int> parentId =
        const RivetValue.absent(),
  }) => MutationConflictChildrenCompanion._(id: id, parentId: parentId);

  /// Mutation value for `id`.
  final RivetValue<MutationConflictChildren, int, int> id;

  /// Mutation value for `parentId`.
  final RivetValue<MutationConflictChildren, int, int> parentId;

  /// The generated column assignments in declaration order.
  @override
  List<RivetAssignment<MutationConflictChildren>> operator [](
    RivetCompanionKey key,
  ) => [RivetAssignment('id', id), RivetAssignment('parentId', parentId)];
}

final class _$MutationConflictChildrenDB
    extends
        RivetTableAccessor<
          MutationConflictChildren,
          MutationConflictChildrenRow
        > {
  const _$MutationConflictChildrenDB();

  @override
  RivetTableSchema<MutationConflictChildren, MutationConflictChildrenRow>
  buildSchema() {
    MutationConflictChildren createDefinition() {
      final definition = MutationConflictChildren();

      return definition;
    }

    final definition = createDefinition();
    MutationConflictChildrenRow decodeRow(
      List<Object?> values,
      List<bool> sqlNulls,
      RivetRelationValues relations, {
      required bool transport,
    }) => MutationConflictChildrenRow(
      id: transport
          ? definition.id.decodeTransportValue(
              values[0],
              isSqlNull: sqlNulls[0],
            )
          : definition.id.decodeValue(values[0], isSqlNull: sqlNulls[0]),
      parentId: transport
          ? definition.parentId.decodeTransportValue(
              values[1],
              isSqlNull: sqlNulls[1],
            )
          : definition.parentId.decodeValue(values[1], isSqlNull: sqlNulls[1]),
      parent: relations.read('parent'),
    );

    final builtSchema =
        RivetTableSchema<MutationConflictChildren, MutationConflictChildrenRow>(
          schemaName: 'fbr143',
          tableName: 'mutationConflictChildren',
          definition: definition,
          columns: [
            definition.id as RivetColumn<Object?>,
            definition.parentId as RivetColumn<Object?>,
          ],
          columnNames: ['id', 'parentId'],
          createDefinition: createDefinition,
          columnsFor: (definition) => [
            definition.id as RivetColumn<Object?>,
            definition.parentId as RivetColumn<Object?>,
          ],
          decode: (values, sqlNulls) => decodeRow(
            values,
            sqlNulls,
            const RivetRelationValues(),
            transport: false,
          ),
          decodeRelated: decodeRow,

          relations: {
            'parent': definition.parent as RivetRelationDescriptor<Object?>,
          },
        );
    definition.parent.bind(
      name: 'parent',
      ownerSchema: builtSchema,
      targetSchema: () => MutationConflictParents.db.buildSchema(),
    );
    return builtSchema;
  }

  /// Creates a reusable read plan with typed relation includes.
  RivetFind<MutationConflictChildren, MutationConflictChildrenRow> find({
    RivetWhere<MutationConflictChildren>? where,
    RivetOrderBy<MutationConflictChildren>? orderBy,
    int? limit,
    int? offset,
    RivetIncludes<MutationConflictChildrenInclude>? include,
  }) {
    final schema = buildSchema();
    return RivetFind(
      schema,
      where: where,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
      includes:
          include?.call(MutationConflictChildrenInclude(schema)) ?? const [],
    );
  }

  /// Creates a reusable insert plan.
  RivetInsert<MutationConflictChildren, MutationConflictChildrenRow> insert(
    MutationConflictChildrenCompanion companion, {
    RivetOnConflict<MutationConflictChildren>? onConflict,
  }) => RivetInsert(buildSchema(), companion, onConflict: onConflict);

  /// Creates a reusable batch insert plan.
  RivetInsertMany<MutationConflictChildren, MutationConflictChildrenRow>
  insertMany(
    Iterable<MutationConflictChildrenCompanion> companions, {
    RivetOnConflict<MutationConflictChildren>? onConflict,
  }) => RivetInsertMany(buildSchema(), companions, onConflict: onConflict);

  /// Creates a reusable update plan.
  RivetUpdate<MutationConflictChildren, MutationConflictChildrenRow> update(
    MutationConflictChildrenCompanion companion, {
    RivetWhere<MutationConflictChildren>? where,
  }) => RivetUpdate(buildSchema(), companion, where: where);

  /// Creates a reusable delete plan.
  RivetDelete<MutationConflictChildren, MutationConflictChildrenRow> delete({
    RivetWhere<MutationConflictChildren>? where,
  }) => RivetDelete(buildSchema(), where: where);
}

/// Generated row returned by reads from 'fbr144.mutationUpsertUsers'.
final class MutationUpsertUsersRow {
  /// Creates a row from decoded column and relation values.
  const MutationUpsertUsersRow({
    required this.id,
    required this.email,
    required this.name,
    required this.age,
    required this.active,
    required this.conditionValue,
    required this.updatedAt,
    required this.note,
    required this.code,
  });

  /// Value read from `id`.
  final int id;

  /// Value read from `email`.
  final String email;

  /// Value read from `name`.
  final String name;

  /// Value read from `age`.
  final int age;

  /// Value read from `active`.
  final bool active;

  /// Value read from `conditionValue`.
  final int? conditionValue;

  /// Value read from `updatedAt`.
  final DateTime updatedAt;

  /// Value read from `note`.
  final String? note;

  /// Value read from `code`.
  final MutationCode code;
}

/// Generated values accepted by mutations of 'fbr144.mutationUpsertUsers'.
final class MutationUpsertUsersCompanion
    implements RivetCompanion<MutationUpsertUsers> {
  const MutationUpsertUsersCompanion._({
    required this.id,
    required this.email,
    required this.name,
    required this.age,
    required this.active,
    required this.conditionValue,
    required this.updatedAt,
    required this.note,
    required this.code,
  });

  /// Creates values for an insert, leaving defaulted columns absent.
  factory MutationUpsertUsersCompanion.insert({
    required RivetValue<MutationUpsertUsers, int, int> id,
    required RivetValue<MutationUpsertUsers, String, String> email,
    required RivetValue<MutationUpsertUsers, String, String> name,
    required RivetValue<MutationUpsertUsers, int, int> age,
    required RivetValue<MutationUpsertUsers, bool, bool> active,
    RivetValue<MutationUpsertUsers, int?, int?> conditionValue =
        const RivetValue.absent(),
    RivetValue<MutationUpsertUsers, DateTime, DateTime> updatedAt =
        const RivetValue.absent(),
    RivetValue<MutationUpsertUsers, String?, String?> note =
        const RivetValue.absent(),
    RivetValue<MutationUpsertUsers, MutationCode, String> code =
        const RivetValue.absent(),
  }) => MutationUpsertUsersCompanion._(
    id: id,
    email: email,
    name: name,
    age: age,
    active: active,
    conditionValue: conditionValue,
    updatedAt: updatedAt,
    note: note,
    code: code,
  );

  /// Creates values for an update, leaving untouched columns absent.
  factory MutationUpsertUsersCompanion.update({
    RivetValue<MutationUpsertUsers, int, int> id = const RivetValue.absent(),
    RivetValue<MutationUpsertUsers, String, String> email =
        const RivetValue.absent(),
    RivetValue<MutationUpsertUsers, String, String> name =
        const RivetValue.absent(),
    RivetValue<MutationUpsertUsers, int, int> age = const RivetValue.absent(),
    RivetValue<MutationUpsertUsers, bool, bool> active =
        const RivetValue.absent(),
    RivetValue<MutationUpsertUsers, int?, int?> conditionValue =
        const RivetValue.absent(),
    RivetValue<MutationUpsertUsers, DateTime, DateTime> updatedAt =
        const RivetValue.absent(),
    RivetValue<MutationUpsertUsers, String?, String?> note =
        const RivetValue.absent(),
    RivetValue<MutationUpsertUsers, MutationCode, String> code =
        const RivetValue.absent(),
  }) => MutationUpsertUsersCompanion._(
    id: id,
    email: email,
    name: name,
    age: age,
    active: active,
    conditionValue: conditionValue,
    updatedAt: updatedAt,
    note: note,
    code: code,
  );

  /// Mutation value for `id`.
  final RivetValue<MutationUpsertUsers, int, int> id;

  /// Mutation value for `email`.
  final RivetValue<MutationUpsertUsers, String, String> email;

  /// Mutation value for `name`.
  final RivetValue<MutationUpsertUsers, String, String> name;

  /// Mutation value for `age`.
  final RivetValue<MutationUpsertUsers, int, int> age;

  /// Mutation value for `active`.
  final RivetValue<MutationUpsertUsers, bool, bool> active;

  /// Mutation value for `conditionValue`.
  final RivetValue<MutationUpsertUsers, int?, int?> conditionValue;

  /// Mutation value for `updatedAt`.
  final RivetValue<MutationUpsertUsers, DateTime, DateTime> updatedAt;

  /// Mutation value for `note`.
  final RivetValue<MutationUpsertUsers, String?, String?> note;

  /// Mutation value for `code`.
  final RivetValue<MutationUpsertUsers, MutationCode, String> code;

  /// The generated column assignments in declaration order.
  @override
  List<RivetAssignment<MutationUpsertUsers>> operator [](
    RivetCompanionKey key,
  ) => [
    RivetAssignment('id', id),
    RivetAssignment('email', email),
    RivetAssignment('name', name),
    RivetAssignment('age', age),
    RivetAssignment('active', active),
    RivetAssignment('conditionValue', conditionValue),
    RivetAssignment('updatedAt', updatedAt),
    RivetAssignment('note', note),
    RivetAssignment('code', code),
  ];
}

final class _$MutationUpsertUsersDB
    extends RivetTableAccessor<MutationUpsertUsers, MutationUpsertUsersRow> {
  const _$MutationUpsertUsersDB();

  @override
  RivetTableSchema<MutationUpsertUsers, MutationUpsertUsersRow> buildSchema() {
    MutationUpsertUsers createDefinition() {
      final definition = MutationUpsertUsers();

      return definition;
    }

    final definition = createDefinition();

    return RivetTableSchema<MutationUpsertUsers, MutationUpsertUsersRow>(
      schemaName: 'fbr144',
      tableName: 'mutationUpsertUsers',
      definition: definition,
      columns: [
        definition.id as RivetColumn<Object?>,
        definition.email as RivetColumn<Object?>,
        definition.name as RivetColumn<Object?>,
        definition.age as RivetColumn<Object?>,
        definition.active as RivetColumn<Object?>,
        definition.conditionValue as RivetColumn<Object?>,
        definition.updatedAt as RivetColumn<Object?>,
        definition.note as RivetColumn<Object?>,
        definition.code as RivetColumn<Object?>,
      ],
      columnNames: [
        'id',
        'email',
        'name',
        'age',
        'active',
        'conditionValue',
        'updatedAt',
        'note',
        'code',
      ],
      createDefinition: createDefinition,
      columnsFor: (definition) => [
        definition.id as RivetColumn<Object?>,
        definition.email as RivetColumn<Object?>,
        definition.name as RivetColumn<Object?>,
        definition.age as RivetColumn<Object?>,
        definition.active as RivetColumn<Object?>,
        definition.conditionValue as RivetColumn<Object?>,
        definition.updatedAt as RivetColumn<Object?>,
        definition.note as RivetColumn<Object?>,
        definition.code as RivetColumn<Object?>,
      ],
      decode: (values, sqlNulls) => MutationUpsertUsersRow(
        id: definition.id.decodeValue(values[0], isSqlNull: sqlNulls[0]),
        email: definition.email.decodeValue(values[1], isSqlNull: sqlNulls[1]),
        name: definition.name.decodeValue(values[2], isSqlNull: sqlNulls[2]),
        age: definition.age.decodeValue(values[3], isSqlNull: sqlNulls[3]),
        active: definition.active.decodeValue(
          values[4],
          isSqlNull: sqlNulls[4],
        ),
        conditionValue: definition.conditionValue.decodeValue(
          values[5],
          isSqlNull: sqlNulls[5],
        ),
        updatedAt: definition.updatedAt.decodeValue(
          values[6],
          isSqlNull: sqlNulls[6],
        ),
        note: definition.note.decodeValue(values[7], isSqlNull: sqlNulls[7]),
        code: definition.code.decodeValue(values[8], isSqlNull: sqlNulls[8]),
      ),
    );
  }

  /// Creates a reusable insert plan.
  RivetInsert<MutationUpsertUsers, MutationUpsertUsersRow> insert(
    MutationUpsertUsersCompanion companion, {
    RivetOnConflict<MutationUpsertUsers>? onConflict,
  }) => RivetInsert(buildSchema(), companion, onConflict: onConflict);

  /// Creates a reusable batch insert plan.
  RivetInsertMany<MutationUpsertUsers, MutationUpsertUsersRow> insertMany(
    Iterable<MutationUpsertUsersCompanion> companions, {
    RivetOnConflict<MutationUpsertUsers>? onConflict,
  }) => RivetInsertMany(buildSchema(), companions, onConflict: onConflict);

  /// Creates a reusable update plan.
  RivetUpdate<MutationUpsertUsers, MutationUpsertUsersRow> update(
    MutationUpsertUsersCompanion companion, {
    RivetWhere<MutationUpsertUsers>? where,
  }) => RivetUpdate(buildSchema(), companion, where: where);

  /// Creates a reusable delete plan.
  RivetDelete<MutationUpsertUsers, MutationUpsertUsersRow> delete({
    RivetWhere<MutationUpsertUsers>? where,
  }) => RivetDelete(buildSchema(), where: where);
}

/// Generated row returned by reads from 'fbr144.mutationAssignmentNames'.
final class MutationAssignmentNamesRow {
  /// Creates a row from decoded column and relation values.
  const MutationAssignmentNamesRow({
    required this.assignments,
    required this.key,
  });

  /// Value read from `assignments`.
  final int assignments;

  /// Value read from `key`.
  final int key;
}

/// Generated values accepted by mutations of 'fbr144.mutationAssignmentNames'.
final class MutationAssignmentNamesCompanion
    implements RivetCompanion<MutationAssignmentNames> {
  const MutationAssignmentNamesCompanion._({
    required this.assignments,
    required this.key,
  });

  /// Creates values for an insert, leaving defaulted columns absent.
  factory MutationAssignmentNamesCompanion.insert({
    required RivetValue<MutationAssignmentNames, int, int> assignments,
    required RivetValue<MutationAssignmentNames, int, int> key,
  }) => MutationAssignmentNamesCompanion._(assignments: assignments, key: key);

  /// Creates values for an update, leaving untouched columns absent.
  factory MutationAssignmentNamesCompanion.update({
    RivetValue<MutationAssignmentNames, int, int> assignments =
        const RivetValue.absent(),
    RivetValue<MutationAssignmentNames, int, int> key =
        const RivetValue.absent(),
  }) => MutationAssignmentNamesCompanion._(assignments: assignments, key: key);

  /// Mutation value for `assignments`.
  final RivetValue<MutationAssignmentNames, int, int> assignments;

  /// Mutation value for `key`.
  final RivetValue<MutationAssignmentNames, int, int> key;

  /// The generated column assignments in declaration order.
  @override
  List<RivetAssignment<MutationAssignmentNames>> operator [](
    RivetCompanionKey key,
  ) => [
    RivetAssignment('assignments', assignments),
    RivetAssignment('key', this.key),
  ];
}

final class _$MutationAssignmentNamesDB
    extends
        RivetTableAccessor<
          MutationAssignmentNames,
          MutationAssignmentNamesRow
        > {
  const _$MutationAssignmentNamesDB();

  @override
  RivetTableSchema<MutationAssignmentNames, MutationAssignmentNamesRow>
  buildSchema() {
    MutationAssignmentNames createDefinition() {
      final definition = MutationAssignmentNames();

      return definition;
    }

    final definition = createDefinition();

    return RivetTableSchema<
      MutationAssignmentNames,
      MutationAssignmentNamesRow
    >(
      schemaName: 'fbr144',
      tableName: 'mutationAssignmentNames',
      definition: definition,
      columns: [
        definition.assignments as RivetColumn<Object?>,
        definition.key as RivetColumn<Object?>,
      ],
      columnNames: ['assignments', 'key'],
      createDefinition: createDefinition,
      columnsFor: (definition) => [
        definition.assignments as RivetColumn<Object?>,
        definition.key as RivetColumn<Object?>,
      ],
      decode: (values, sqlNulls) => MutationAssignmentNamesRow(
        assignments: definition.assignments.decodeValue(
          values[0],
          isSqlNull: sqlNulls[0],
        ),
        key: definition.key.decodeValue(values[1], isSqlNull: sqlNulls[1]),
      ),
    );
  }

  /// Creates a reusable insert plan.
  RivetInsert<MutationAssignmentNames, MutationAssignmentNamesRow> insert(
    MutationAssignmentNamesCompanion companion, {
    RivetOnConflict<MutationAssignmentNames>? onConflict,
  }) => RivetInsert(buildSchema(), companion, onConflict: onConflict);

  /// Creates a reusable batch insert plan.
  RivetInsertMany<MutationAssignmentNames, MutationAssignmentNamesRow>
  insertMany(
    Iterable<MutationAssignmentNamesCompanion> companions, {
    RivetOnConflict<MutationAssignmentNames>? onConflict,
  }) => RivetInsertMany(buildSchema(), companions, onConflict: onConflict);

  /// Creates a reusable update plan.
  RivetUpdate<MutationAssignmentNames, MutationAssignmentNamesRow> update(
    MutationAssignmentNamesCompanion companion, {
    RivetWhere<MutationAssignmentNames>? where,
  }) => RivetUpdate(buildSchema(), companion, where: where);

  /// Creates a reusable delete plan.
  RivetDelete<MutationAssignmentNames, MutationAssignmentNamesRow> delete({
    RivetWhere<MutationAssignmentNames>? where,
  }) => RivetDelete(buildSchema(), where: where);
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
      RelationalUsers.db.buildSchema() as RivetTableSchema<Object?, Object?>,
      RelationalPosts.db.buildSchema() as RivetTableSchema<Object?, Object?>,
      RelationalComments.db.buildSchema() as RivetTableSchema<Object?, Object?>,
      ThroughBooks.db.buildSchema() as RivetTableSchema<Object?, Object?>,
      ThroughTags.db.buildSchema() as RivetTableSchema<Object?, Object?>,
      ThroughBookTags.db.buildSchema() as RivetTableSchema<Object?, Object?>,
      ThroughReviews.db.buildSchema() as RivetTableSchema<Object?, Object?>,
      ThroughTagNotes.db.buildSchema() as RivetTableSchema<Object?, Object?>,
      ScalarValues.db.buildSchema() as RivetTableSchema<Object?, Object?>,
      EnumValues.db.buildSchema() as RivetTableSchema<Object?, Object?>,
      VectorValues.db.buildSchema() as RivetTableSchema<Object?, Object?>,
      ArrayValues.db.buildSchema() as RivetTableSchema<Object?, Object?>,
      CodecParents.db.buildSchema() as RivetTableSchema<Object?, Object?>,
      CodecValues.db.buildSchema() as RivetTableSchema<Object?, Object?>,
      CodecLinks.db.buildSchema() as RivetTableSchema<Object?, Object?>,
      MalformedArrays.db.buildSchema() as RivetTableSchema<Object?, Object?>,
      MetadataColumns.db.buildSchema() as RivetTableSchema<Object?, Object?>,
      ParameterNames.db.buildSchema() as RivetTableSchema<Object?, Object?>,
      MutationUsers.db.buildSchema() as RivetTableSchema<Object?, Object?>,
      MutationParents.db.buildSchema() as RivetTableSchema<Object?, Object?>,
      MutationChildren.db.buildSchema() as RivetTableSchema<Object?, Object?>,
      MutationCatalog.db.buildSchema() as RivetTableSchema<Object?, Object?>,
      MutationUpdateUsers.db.buildSchema()
          as RivetTableSchema<Object?, Object?>,
      MutationUpdateChildren.db.buildSchema()
          as RivetTableSchema<Object?, Object?>,
      MutationDeleteParents.db.buildSchema()
          as RivetTableSchema<Object?, Object?>,
      MutationCascadeChildren.db.buildSchema()
          as RivetTableSchema<Object?, Object?>,
      MutationRestrictChildren.db.buildSchema()
          as RivetTableSchema<Object?, Object?>,
      MutationBatchParents.db.buildSchema()
          as RivetTableSchema<Object?, Object?>,
      MutationBatchChildren.db.buildSchema()
          as RivetTableSchema<Object?, Object?>,
      MutationConflictGroups.db.buildSchema()
          as RivetTableSchema<Object?, Object?>,
      MutationConflictParents.db.buildSchema()
          as RivetTableSchema<Object?, Object?>,
      MutationConflictChildren.db.buildSchema()
          as RivetTableSchema<Object?, Object?>,
      MutationUpsertUsers.db.buildSchema()
          as RivetTableSchema<Object?, Object?>,
      MutationAssignmentNames.db.buildSchema()
          as RivetTableSchema<Object?, Object?>,
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
