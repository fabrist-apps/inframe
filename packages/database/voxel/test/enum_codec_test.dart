import 'package:test/test.dart';
import 'package:voxel_fixture_app/posts.dart';
import 'package:voxel_fixture_schema/authors.dart';

void main() {
  test('uses imported generated enum labels rather than ordinals', () {
    final status = Posts.db.buildSchema().definition.status;
    expect(status.codec.encode(PostStatus.draft), 'draft');
    expect(status.codec.encode(PostStatus.published), 'live');
    expect(status.codec.decode('draft', isSqlNull: false), PostStatus.draft);
    expect(status.codec.decode('live', isSqlNull: false), PostStatus.published);
    expect(() => status.codec.decode('published', isSqlNull: false), throwsFormatException);
    expect(status.defaultFn!(), PostStatus.draft);
    expect(PostStatusVoxelEnum.codec.schemaName, 'content');
    expect(PostStatusVoxelEnum.codec.typeName, 'postStatus');
    expect(PostStatusVoxelEnum.codec.renamedFrom, 'articleStatus');
    expect(PostStatusVoxelEnum.codec.renamedLabels, {'live': 'published'});
  });
}
