import 'package:test/test.dart';
import 'package:turso/turso.dart';
import 'package:voxel_fixture_app/posts.dart';
import 'package:voxel_fixture_schema/authors.dart';

void main() {
  test('round-trips imported enum labels through Turso TEXT storage', () async {
    final status = Posts.db.buildSchema().definition.status;
    final database = await TursoDatabase.open(TursoLocation.memory());
    addTearDown(database.close);
    await database.execute('CREATE TABLE values_table (status TEXT)');
    await database.execute(
      'INSERT INTO values_table VALUES (?), (?)',
      parameters: [
        status.codec.encode(PostStatus.draft),
        status.codec.encode(PostStatus.published),
      ],
    );
    final rows = (await database.query('SELECT status FROM values_table ORDER BY rowid')).rows;
    expect(
      rows.map((row) => status.codec.decode(row.value('status'), isSqlNull: false)),
      [PostStatus.draft, PostStatus.published],
    );
    await database.execute('INSERT INTO values_table VALUES (?)', parameters: const ['unknown']);
    final malformed = (await database.query(
      'SELECT status FROM values_table ORDER BY rowid DESC LIMIT 1',
    )).rows.single;
    expect(
      () => status.decodeValue(malformed.value('status'), isSqlNull: false),
      throwsException,
    );
  });
}
