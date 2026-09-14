import 'package:test/test.dart';
import 'package:voxel/src/testing.dart';

void main() {
  test('scope rewriting changes qualified identifiers without changing SQL text', () {
    const sql = '''
-- keep "old".comment
CREATE TABLE "old"."items" (
  "value" TEXT DEFAULT 'keep "old".literal'
);
/* keep "old".block */
INSERT INTO "old"."items" VALUES ('it''s "old".data');
''';

    expect(
      rewriteVoxelMigrationScopeForTesting(sql, 'old', 'new'),
      '''
-- keep "old".comment
CREATE TABLE "new"."items" (
  "value" TEXT DEFAULT 'keep "old".literal'
);
/* keep "old".block */
INSERT INTO "new"."items" VALUES ('it''s "old".data');
''',
    );
  });
}
