// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

part of 'posts.dart';

// **************************************************************************
// VoxelTableGenerator
// **************************************************************************

/// Generated row returned by reads from 'content.posts'.
final class PostsRow {
  /// Creates a row from decoded column and relation values.
  const PostsRow({
    required this.id,
    required this.authorID,
    required this.status,
    this.author = const Relation.unloaded(),
    this.tags = const Relation.unloaded(),
  });

  /// Value read from `id`.
  final String id;

  /// Value read from `authorID`.
  final String authorID;

  /// Value read from `status`.
  final schema.PostStatus status;

  /// Loaded or unloaded `author` relation.
  final Relation<schema.AuthorsRow?> author;

  /// Loaded or unloaded `tags` relation.
  final Relation<List<TagsRow>> tags;
}

/// Generated values accepted by mutations of 'content.posts'.
final class PostsCompanion implements VoxelCompanion<Posts> {
  const PostsCompanion._({
    required this.id,
    required this.authorID,
    required this.status,
  });

  /// Creates values for an insert, leaving defaulted columns absent.
  factory PostsCompanion.insert({
    required VoxelValue<Posts, String, String> id,
    required VoxelValue<Posts, String, String> authorID,
    VoxelValue<Posts, schema.PostStatus, schema.PostStatus> status =
        const VoxelValue.absent(),
  }) => PostsCompanion._(id: id, authorID: authorID, status: status);

  /// Creates values for an update, leaving untouched columns absent.
  factory PostsCompanion.update({
    VoxelValue<Posts, String, String> id = const VoxelValue.absent(),
    VoxelValue<Posts, String, String> authorID = const VoxelValue.absent(),
    VoxelValue<Posts, schema.PostStatus, schema.PostStatus> status =
        const VoxelValue.absent(),
  }) => PostsCompanion._(id: id, authorID: authorID, status: status);

  /// Mutation value for `id`.
  final VoxelValue<Posts, String, String> id;

  /// Mutation value for `authorID`.
  final VoxelValue<Posts, String, String> authorID;

  /// Mutation value for `status`.
  final VoxelValue<Posts, schema.PostStatus, schema.PostStatus> status;

  /// The generated column assignments in declaration order.
  @override
  List<VoxelAssignment<Posts>> operator [](VoxelCompanionKey key) => [
    VoxelAssignment('id', id),
    VoxelAssignment('authorID', authorID),
    VoxelAssignment('status', status),
  ];
}

final class _$PostsDB extends VoxelTableAccessor<Posts, PostsRow> {
  const _$PostsDB();

  @override
  VoxelTableSchema<Posts, PostsRow> buildSchema() {
    Posts createDefinition() {
      final definition = Posts();
      definition.status.configureEnum(schema.PostStatusVoxelEnum.codec);
      return definition;
    }

    final definition = createDefinition();
    return VoxelTableSchema<Posts, PostsRow>(
      schemaName: 'content',
      tableName: 'posts',
      definition: definition,
      definitionType: Posts,
      rowType: PostsRow,
      columns: [
        definition.id as VoxelColumn<Object?>,
        definition.authorID as VoxelColumn<Object?>,
        definition.status as VoxelColumn<Object?>,
      ],
      columnNames: ['id', 'authorID', 'status'],
      createDefinition: createDefinition,
      columnsFor: (definition) => [
        definition.id as VoxelColumn<Object?>,
        definition.authorID as VoxelColumn<Object?>,
        definition.status as VoxelColumn<Object?>,
      ],
      decode: (values, sqlNulls) => PostsRow(
        id: definition.id.decodeValue(values[0], isSqlNull: sqlNulls[0]),
        authorID: definition.authorID.decodeValue(
          values[1],
          isSqlNull: sqlNulls[1],
        ),
        status: definition.status.decodeValue(
          values[2],
          isSqlNull: sqlNulls[2],
        ),
      ),
      relations: {
        'author': definition.author as VoxelRelationDescriptor<Object?>,
        'tags': definition.tags as VoxelRelationDescriptor<Object?>,
      },
    );
  }
}

/// Generated row returned by reads from 'content.tags'.
final class TagsRow {
  /// Creates a row from decoded column and relation values.
  const TagsRow({required this.id});

  /// Value read from `id`.
  final String id;
}

/// Generated values accepted by mutations of 'content.tags'.
final class TagsCompanion implements VoxelCompanion<Tags> {
  const TagsCompanion._({required this.id});

  /// Creates values for an insert, leaving defaulted columns absent.
  factory TagsCompanion.insert({
    required VoxelValue<Tags, String, String> id,
  }) => TagsCompanion._(id: id);

  /// Creates values for an update, leaving untouched columns absent.
  factory TagsCompanion.update({
    VoxelValue<Tags, String, String> id = const VoxelValue.absent(),
  }) => TagsCompanion._(id: id);

  /// Mutation value for `id`.
  final VoxelValue<Tags, String, String> id;

  /// The generated column assignments in declaration order.
  @override
  List<VoxelAssignment<Tags>> operator [](VoxelCompanionKey key) => [
    VoxelAssignment('id', id),
  ];
}

final class _$TagsDB extends VoxelTableAccessor<Tags, TagsRow> {
  const _$TagsDB();

  @override
  VoxelTableSchema<Tags, TagsRow> buildSchema() {
    Tags createDefinition() {
      final definition = Tags();

      return definition;
    }

    final definition = createDefinition();
    return VoxelTableSchema<Tags, TagsRow>(
      schemaName: 'content',
      tableName: 'tags',
      definition: definition,
      definitionType: Tags,
      rowType: TagsRow,
      columns: [definition.id as VoxelColumn<Object?>],
      columnNames: ['id'],
      createDefinition: createDefinition,
      columnsFor: (definition) => [definition.id as VoxelColumn<Object?>],
      decode: (values, sqlNulls) => TagsRow(
        id: definition.id.decodeValue(values[0], isSqlNull: sqlNulls[0]),
      ),
    );
  }
}

/// Generated row returned by reads from 'content.postTags'.
final class PostTagsRow {
  /// Creates a row from decoded column and relation values.
  const PostTagsRow({
    required this.postID,
    required this.tagID,
    this.post = const Relation.unloaded(),
    this.tag = const Relation.unloaded(),
  });

  /// Value read from `postID`.
  final String postID;

  /// Value read from `tagID`.
  final String tagID;

  /// Loaded or unloaded `post` relation.
  final Relation<PostsRow?> post;

  /// Loaded or unloaded `tag` relation.
  final Relation<TagsRow?> tag;
}

/// Generated values accepted by mutations of 'content.postTags'.
final class PostTagsCompanion implements VoxelCompanion<PostTags> {
  const PostTagsCompanion._({required this.postID, required this.tagID});

  /// Creates values for an insert, leaving defaulted columns absent.
  factory PostTagsCompanion.insert({
    required VoxelValue<PostTags, String, String> postID,
    required VoxelValue<PostTags, String, String> tagID,
  }) => PostTagsCompanion._(postID: postID, tagID: tagID);

  /// Creates values for an update, leaving untouched columns absent.
  factory PostTagsCompanion.update({
    VoxelValue<PostTags, String, String> postID = const VoxelValue.absent(),
    VoxelValue<PostTags, String, String> tagID = const VoxelValue.absent(),
  }) => PostTagsCompanion._(postID: postID, tagID: tagID);

  /// Mutation value for `postID`.
  final VoxelValue<PostTags, String, String> postID;

  /// Mutation value for `tagID`.
  final VoxelValue<PostTags, String, String> tagID;

  /// The generated column assignments in declaration order.
  @override
  List<VoxelAssignment<PostTags>> operator [](VoxelCompanionKey key) => [
    VoxelAssignment('postID', postID),
    VoxelAssignment('tagID', tagID),
  ];
}

final class _$PostTagsDB extends VoxelTableAccessor<PostTags, PostTagsRow> {
  const _$PostTagsDB();

  @override
  VoxelTableSchema<PostTags, PostTagsRow> buildSchema() {
    PostTags createDefinition() {
      final definition = PostTags();

      return definition;
    }

    final definition = createDefinition();
    return VoxelTableSchema<PostTags, PostTagsRow>(
      schemaName: 'content',
      tableName: 'postTags',
      definition: definition,
      definitionType: PostTags,
      rowType: PostTagsRow,
      columns: [
        definition.postID as VoxelColumn<Object?>,
        definition.tagID as VoxelColumn<Object?>,
      ],
      columnNames: ['postID', 'tagID'],
      createDefinition: createDefinition,
      columnsFor: (definition) => [
        definition.postID as VoxelColumn<Object?>,
        definition.tagID as VoxelColumn<Object?>,
      ],
      decode: (values, sqlNulls) => PostTagsRow(
        postID: definition.postID.decodeValue(
          values[0],
          isSqlNull: sqlNulls[0],
        ),
        tagID: definition.tagID.decodeValue(values[1], isSqlNull: sqlNulls[1]),
      ),
      relations: {
        'post': definition.post as VoxelRelationDescriptor<Object?>,
        'tag': definition.tag as VoxelRelationDescriptor<Object?>,
      },
    );
  }
}
