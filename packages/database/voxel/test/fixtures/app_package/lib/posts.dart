// Fixture declarations intentionally rely on inferred DSL types.
// ignore_for_file: public_member_api_docs, specify_nonobvious_property_types

import 'package:voxel/voxel.dart';
import 'package:voxel_fixture_schema/authors.dart' as schema;

part 'posts.voxel.dart';

@VoxelTable(schema: 'content')
final class Posts extends VoxelTableDefinition<Posts> {
  static const db = _$PostsDB();

  late final id = text().primaryKey()();
  late final authorID = text().references<schema.Authors>((author) => author.id)();
  late final VoxelOrderableColumn<schema.PostStatus> status = enumText<schema.PostStatus>()
      .defaultValue(() => schema.PostStatus.draft)();
  late final VoxelOneRelation<schema.Authors> author = one<schema.Authors>(
    fields: [authorID],
    references: (author) => [author.id],
  )();
  late final tags = many<Tags>().through<PostTags>(
    source: (link) => link.post,
    target: (link) => link.tag,
  )();
}

@VoxelTable(schema: 'content')
final class Tags extends VoxelTableDefinition<Tags> {
  static const db = _$TagsDB();

  late final id = text().primaryKey()();
}

@VoxelTable(schema: 'content')
final class PostTags extends VoxelTableDefinition<PostTags> {
  static const db = _$PostTagsDB();

  late final postID = text().references<Posts>((post) => post.id)();
  late final tagID = text().references<Tags>((tag) => tag.id)();
  late final post = one<Posts>(fields: [postID], references: (post) => [post.id])();
  late final tag = one<Tags>(fields: [tagID], references: (tag) => [tag.id])();
}

@VoxelTable(schema: 'content')
final class Locales extends VoxelTableDefinition<Locales> {
  static const db = _$LocalesDB();

  late final language = text()();
  late final key = text()();
  late final _constraints = [
    primaryKey('locales_pk', [language, key]),
  ];
}

@VoxelTable(schema: 'content')
final class Translations extends VoxelTableDefinition<Translations> {
  static const db = _$TranslationsDB();

  late final language = text()();
  late final key = text()();
  late final value = text()();
  late final _constraints = [
    foreignKey<Locales>(
      'translations_locale_fk',
      fields: [language, key],
      references: (locale) => [locale.language, locale.key],
      onDelete: VoxelReferentialAction.cascade,
    ),
  ];
}
