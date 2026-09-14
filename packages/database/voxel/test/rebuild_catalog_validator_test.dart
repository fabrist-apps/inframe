import 'package:test/test.dart';
import 'package:turso/turso.dart';
import 'package:voxel/src/rebuild_catalog_validator.dart';

void main() {
  group('VoxelRebuildCatalogValidator', () {
    late TursoDatabase database;
    late VoxelCatalogQuery query;

    setUp(() async {
      database = await TursoDatabase.open(TursoLocation.memory());
      await database.execute("ATTACH DATABASE ':memory:' AS auth");
      query = (sql) async {
        final result = await database.query(sql);
        return [
          for (final row in result.rows)
            {
              for (var index = 0; index < result.columns.length; index++)
                result.columns[index].name: row.valueAt(index),
            },
        ];
      };
    });

    tearDown(() => database.close());

    test('should accept matching columns, constraints, indexes, and autoindexes', () async {
      await database.execute('''
CREATE TABLE auth.parents (
  id TEXT NOT NULL,
  locale TEXT NOT NULL,
  name TEXT NOT NULL DEFAULT 'unknown',
  CONSTRAINT parents_name_present CHECK ((name > '')),
  CONSTRAINT parents_pkey PRIMARY KEY (id, locale)
)
''');
      await database.execute(
        "CREATE UNIQUE INDEX auth.parents_name ON parents (name DESC) WHERE NOT ((name = ''))",
      );
      await database.execute(
        'CREATE VIEW auth.unrelated AS SELECT 1 AS parents /* FROM parents */',
      );

      await const VoxelRebuildCatalogValidator().validate(
        scopeName: 'auth',
        rebuild: _rebuildMetadata(),
        previousSnapshot: _previousSnapshot(),
        query: query,
      );
    });

    test('should reject unmanaged indexes, triggers, and dependent views', () async {
      for (final fixture in <({String name, String sql})>[
        (
          name: 'index',
          sql: 'CREATE INDEX auth.external_index ON parents (locale)',
        ),
        (
          name: 'trigger',
          sql: 'CREATE TRIGGER auth.external_trigger AFTER INSERT ON parents BEGIN SELECT 1; END',
        ),
        (
          name: 'view',
          sql: 'CREATE VIEW auth.external_view AS SELECT id FROM parents',
        ),
      ]) {
        await database.execute('DROP TABLE IF EXISTS auth.parents');
        await database.execute('''
CREATE TABLE auth.parents (
  id TEXT NOT NULL,
  locale TEXT NOT NULL,
  name TEXT NOT NULL DEFAULT 'unknown',
  CONSTRAINT parents_name_present CHECK ((name > '')),
  CONSTRAINT parents_pkey PRIMARY KEY (id, locale)
)
''');
        await database.execute(
          "CREATE UNIQUE INDEX auth.parents_name ON parents (name DESC) WHERE NOT ((name = ''))",
        );
        await database.execute(fixture.sql);

        await expectLater(
          const VoxelRebuildCatalogValidator().validate(
            scopeName: 'auth',
            rebuild: _rebuildMetadata(),
            previousSnapshot: _previousSnapshot(),
            query: query,
          ),
          throwsA(
            isA<VoxelRebuildCatalogException>()
                .having(
                  (error) => error.kind,
                  'kind',
                  VoxelRebuildCatalogMismatch.unmanagedDependency,
                )
                .having(
                  (error) => error.objectName,
                  'objectName',
                  fixture.name == 'index'
                      ? 'external_index'
                      : fixture.name == 'trigger'
                      ? 'external_trigger'
                      : 'external_view',
                ),
          ),
        );
        if (fixture.name != 'view') {
          await database.execute(
            'DROP ${fixture.name.toUpperCase()} auth.external_${fixture.name}',
          );
        }
      }
    });

    test('should reject a live structural mismatch without exposing catalog SQL', () async {
      await database.execute('''
CREATE TABLE auth.parents (
  id TEXT NOT NULL,
  locale INTEGER NOT NULL,
  name TEXT NOT NULL DEFAULT 'secret-live-default',
  CONSTRAINT parents_name_present CHECK ((name > '')),
  CONSTRAINT parents_pkey PRIMARY KEY (id, locale)
)
''');
      await database.execute(
        "CREATE UNIQUE INDEX auth.parents_name ON parents (name DESC) WHERE NOT ((name = ''))",
      );

      await expectLater(
        const VoxelRebuildCatalogValidator().validate(
          scopeName: 'auth',
          rebuild: _rebuildMetadata(),
          previousSnapshot: _previousSnapshot(),
          query: query,
        ),
        throwsA(
          isA<VoxelRebuildCatalogException>()
              .having((error) => error.kind, 'kind', VoxelRebuildCatalogMismatch.structure)
              .having((error) => error.toString(), 'safe message', isNot(contains('secret'))),
        ),
      );
    });

    test('should reject check and index drift independently', () async {
      await database.execute('''
CREATE TABLE auth.parents (
  id TEXT NOT NULL,
  locale TEXT NOT NULL,
  name TEXT NOT NULL DEFAULT 'unknown',
  CONSTRAINT parents_pkey PRIMARY KEY (id, locale)
)
''');
      await database.execute(
        "CREATE UNIQUE INDEX auth.parents_name ON parents (name DESC) WHERE NOT ((name = ''))",
      );
      await expectLater(
        const VoxelRebuildCatalogValidator().validate(
          scopeName: 'auth',
          rebuild: _rebuildMetadata(),
          previousSnapshot: _previousSnapshot(),
          query: query,
        ),
        throwsA(
          isA<VoxelRebuildCatalogException>().having(
            (error) => error.objectName,
            'objectName',
            'parents_name_present',
          ),
        ),
      );

      await database.execute('DROP TABLE auth.parents');
      await database.execute('''
CREATE TABLE auth.parents (
  id TEXT NOT NULL,
  locale TEXT NOT NULL,
  name TEXT NOT NULL DEFAULT 'unknown',
  CONSTRAINT parents_name_present CHECK ((name > '')),
  CONSTRAINT parents_pkey PRIMARY KEY (id, locale)
)
''');
      await database.execute(
        "CREATE UNIQUE INDEX auth.parents_name ON parents (name ASC) WHERE NOT ((name = ''))",
      );
      await expectLater(
        const VoxelRebuildCatalogValidator().validate(
          scopeName: 'auth',
          rebuild: _rebuildMetadata(),
          previousSnapshot: _previousSnapshot(),
          query: query,
        ),
        throwsA(
          isA<VoxelRebuildCatalogException>().having(
            (error) => error.objectName,
            'objectName',
            'parents_name',
          ),
        ),
      );
    });

    test('should validate composite foreign keys by physical names and actions', () async {
      await database.execute('PRAGMA foreign_keys=ON');
      await database.execute('''
CREATE TABLE auth.parents (
  id TEXT NOT NULL,
  locale TEXT NOT NULL,
  name TEXT NOT NULL DEFAULT 'unknown',
  CONSTRAINT parents_name_present CHECK ((name > '')),
  CONSTRAINT parents_self_fk FOREIGN KEY (id, locale)
    REFERENCES parents (id, locale) ON DELETE CASCADE ON UPDATE NO ACTION,
  CONSTRAINT parents_pkey PRIMARY KEY (id, locale)
)
''');
      await database.execute(
        "CREATE UNIQUE INDEX auth.parents_name ON parents (name DESC) WHERE NOT ((name = ''))",
      );
      final rebuild = _selfReferencingRebuildMetadata();

      await const VoxelRebuildCatalogValidator().validate(
        scopeName: 'auth',
        rebuild: rebuild,
        previousSnapshot: _previousSnapshot(rebuild),
        query: query,
      );
    });
  });
}

Map<String, Object?> _rebuildMetadata() => {
  'foreignKeys': 'offOutsideTransaction',
  'validations': <Object?>[],
  'tables': [
    {
      'tableId': '11111111111111111111111111111111',
      'oldName': 'parents',
      'replacementName': '__voxel_rebuild_111111111111',
      'finalName': 'parents',
      'managedDependencies': [
        {
          'kind': 'index',
          'objectId': '77777777777777777777777777777777',
          'name': 'parents_name',
        },
      ],
      'expectedBefore': {
        'id': '11111111111111111111111111111111',
        'schemaId': '22222222222222222222222222222222',
        'name': 'parents',
        'columns': [
          _column('33333333333333333333333333333333', 'id'),
          _column('44444444444444444444444444444444', 'locale'),
          _column(
            '55555555555555555555555555555555',
            'name',
            defaultValue: {
              'formatVersion': 1,
              'kind': 'literal',
              'literalType': 'string',
              'value': 'unknown',
            },
          ),
        ],
        'indexes': [
          {
            'id': '77777777777777777777777777777777',
            'tableId': '11111111111111111111111111111111',
            'name': 'parents_name',
            'unique': true,
            'terms': [
              {'columnId': '55555555555555555555555555555555', 'descending': true},
            ],
            'predicate': {
              'formatVersion': 1,
              'kind': 'operator',
              'operator': 'NOT',
              'arguments': [
                {
                  'formatVersion': 1,
                  'kind': 'operator',
                  'operator': '=',
                  'arguments': [
                    {
                      'formatVersion': 1,
                      'kind': 'reference',
                      'objectId': '55555555555555555555555555555555',
                    },
                    {
                      'formatVersion': 1,
                      'kind': 'literal',
                      'literalType': 'string',
                      'value': '',
                    },
                  ],
                },
              ],
            },
            'options': <String, Object?>{},
            'platforms': ['native', 'browser'],
          },
        ],
        'constraints': [
          {
            'id': '88888888888888888888888888888888',
            'tableId': '11111111111111111111111111111111',
            'name': 'parents_name_present',
            'kind': 'check',
            'columnIds': <Object?>[],
            'expression': {
              'formatVersion': 1,
              'kind': 'operator',
              'operator': '>',
              'arguments': [
                {
                  'formatVersion': 1,
                  'kind': 'reference',
                  'objectId': '55555555555555555555555555555555',
                },
                {
                  'formatVersion': 1,
                  'kind': 'literal',
                  'literalType': 'string',
                  'value': '',
                },
              ],
            },
          },
          {
            'id': '99999999999999999999999999999999',
            'tableId': '11111111111111111111111111111111',
            'name': 'parents_pkey',
            'kind': 'primaryKey',
            'columnIds': [
              '33333333333333333333333333333333',
              '44444444444444444444444444444444',
            ],
          },
        ],
      },
    },
  ],
};

Map<String, Object?> _previousSnapshot([Map<String, Object?>? metadata]) {
  final rebuild = metadata ?? _rebuildMetadata();
  final table = _mapList(rebuild['tables']).single['expectedBefore']!;
  return {
    'tables': [table],
  };
}

Map<String, Object?> _selfReferencingRebuildMetadata() {
  final rebuild = _rebuildMetadata();
  final table = _mapList(rebuild['tables']).single;
  final expected = table['expectedBefore']! as Map<String, Object?>;
  (expected['constraints']! as List<Object?>).insert(1, {
    'id': 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    'tableId': '11111111111111111111111111111111',
    'name': 'parents_self_fk',
    'kind': 'foreignKey',
    'columnIds': [
      '33333333333333333333333333333333',
      '44444444444444444444444444444444',
    ],
    'referenceTableId': '11111111111111111111111111111111',
    'referenceColumnIds': [
      '33333333333333333333333333333333',
      '44444444444444444444444444444444',
    ],
    'onDelete': 'cascade',
    'onUpdate': 'noAction',
  });
  return rebuild;
}

List<Map<String, Object?>> _mapList(Object? value) =>
    (value! as List<Object?>).cast<Map<String, Object?>>();

Map<String, Object?> _column(
  String id,
  String name, {
  Map<String, Object?>? defaultValue,
}) {
  final column = <String, Object?>{
    'id': id,
    'tableId': '11111111111111111111111111111111',
    'name': name,
    'storage': {'kind': 'text', 'nullable': false, 'codecVersion': 1},
    'primaryKey': name == 'id' || name == 'locale',
  };
  if (defaultValue != null) column['default'] = defaultValue;
  return column;
}
