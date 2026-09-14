// GENERATED CODE - DO NOT MODIFY BY HAND

import 'package:voxel/voxel.dart';
import 'package:voxel_fixture_app/app_database.dart';

/// Checked migration history for `FixtureAppDatabase`.
abstract final class FixtureAppDatabaseVoxelMigrations {
  /// Exact artifacts validated against the current composed schema.
  static const bundle = VoxelMigrationBundle(
    databaseId: '00000000000000000000000000000001',
    migrations: [
      VoxelBundledMigration(
        directory: '0000_initial_imported_schema_00000000000000000000000000000023',
        sql: 'CREATE TABLE "content"."authors" (\n  "id" TEXT NOT NULL,\n  "name" TEXT NOT NULL,\n  CONSTRAINT "authors_name_present" CHECK (("name" > \'\')),\n  CONSTRAINT "authors_pkey" PRIMARY KEY ("id")\n);\nCREATE TABLE "content"."articles" (\n  "id" TEXT NOT NULL,\n  "writerID" TEXT NOT NULL,\n  "status" TEXT NOT NULL,\n  CHECK ("status" IN (\'draft\', \'published\')),\n  CONSTRAINT "posts_authorID_fkey" FOREIGN KEY ("writerID") REFERENCES "authors" ("id") ON DELETE NO ACTION ON UPDATE NO ACTION,\n  CONSTRAINT "articles_pkey" PRIMARY KEY ("id")\n);\nCREATE TABLE "content"."tags" (\n  "id" TEXT NOT NULL,\n  CONSTRAINT "tags_pkey" PRIMARY KEY ("id")\n);\nCREATE TABLE "content"."postTags" (\n  "postID" TEXT NOT NULL,\n  "tagID" TEXT NOT NULL,\n  CONSTRAINT "postTags_postID_fkey" FOREIGN KEY ("postID") REFERENCES "articles" ("id") ON DELETE NO ACTION ON UPDATE NO ACTION,\n  CONSTRAINT "postTags_tagID_fkey" FOREIGN KEY ("tagID") REFERENCES "tags" ("id") ON DELETE NO ACTION ON UPDATE NO ACTION\n);\nCREATE TABLE "content"."locales" (\n  "language" TEXT NOT NULL,\n  "key" TEXT NOT NULL,\n  CONSTRAINT "locales_pk" PRIMARY KEY ("language", "key")\n);\nCREATE TABLE "content"."translations" (\n  "language" TEXT NOT NULL,\n  "key" TEXT NOT NULL,\n  "value" TEXT NOT NULL,\n  CONSTRAINT "translations_locale_fk" FOREIGN KEY ("language", "key") REFERENCES "locales" ("language", "key") ON DELETE CASCADE ON UPDATE NO ACTION\n);\nCREATE UNIQUE INDEX "content"."authors_name" ON "authors" ("name" ASC) WHERE NOT (("name" = \'\'));\n',
        metadata: <String, Object?>{
          'checksum': 'b63e20ac33713e6cc58eeb36ce087500611ee551cf175ebc7c90463eb9109c85',
          'databaseId': '00000000000000000000000000000001',
          'dialect': 'voxel',
          'formatVersion': 1,
          'id': '00000000000000000000000000000023',
          'parentId': null,
          'phases': <Object?>[
            <String, Object?>{
              'id': '0',
              'mode': 'transactional',
              'platforms': <Object?>['native', 'browser'],
              'recovery': null,
              'scopeId': '00000000000000000000000000000002',
              'statements': <Object?>[
                <String, Object?>{'endByte': 189, 'startByte': 0},
                <String, Object?>{'endByte': 527, 'startByte': 190},
                <String, Object?>{'endByte': 628, 'startByte': 528},
                <String, Object?>{'endByte': 969, 'startByte': 629},
                <String, Object?>{'endByte': 1116, 'startByte': 970},
                <String, Object?>{'endByte': 1384, 'startByte': 1117},
                <String, Object?>{'endByte': 1482, 'startByte': 1385},
              ],
            },
          ],
        },
        snapshot: <String, Object?>{
          'databaseId': '00000000000000000000000000000001',
          'dialect': 'voxel',
          'enums': <Object?>[
            <String, Object?>{
              'id': '00000000000000000000000000000018',
              'name': 'articleStatus',
              'schemaId': '00000000000000000000000000000002',
              'values': <Object?>[
                <String, Object?>{
                  'enumId': '00000000000000000000000000000018',
                  'id': '00000000000000000000000000000016',
                  'label': 'draft',
                },
                <String, Object?>{
                  'enumId': '00000000000000000000000000000018',
                  'id': '00000000000000000000000000000017',
                  'label': 'published',
                },
              ],
            },
          ],
          'formatVersion': 1,
          'migrationId': '00000000000000000000000000000023',
          'requirements': <Object?>[],
          'schemas': <Object?>[
            <String, Object?>{'id': '00000000000000000000000000000002', 'name': 'content'},
          ],
          'tables': <Object?>[
            <String, Object?>{
              'columns': <Object?>[
                <String, Object?>{
                  'id': '00000000000000000000000000000004',
                  'name': 'id',
                  'primaryKey': true,
                  'storage': <String, Object?>{
                    'codecVersion': 1,
                    'kind': 'text',
                    'nullable': false,
                  },
                  'tableId': '00000000000000000000000000000003',
                },
                <String, Object?>{
                  'id': '00000000000000000000000000000005',
                  'name': 'name',
                  'primaryKey': false,
                  'storage': <String, Object?>{
                    'codecVersion': 1,
                    'kind': 'text',
                    'nullable': false,
                  },
                  'tableId': '00000000000000000000000000000003',
                },
              ],
              'constraints': <Object?>[
                <String, Object?>{
                  'columnIds': <Object?>[],
                  'expression': <String, Object?>{
                    'arguments': <Object?>[
                      <String, Object?>{
                        'formatVersion': 1,
                        'kind': 'reference',
                        'objectId': '00000000000000000000000000000005',
                      },
                      <String, Object?>{
                        'formatVersion': 1,
                        'kind': 'literal',
                        'literalType': 'string',
                        'value': '',
                      },
                    ],
                    'formatVersion': 1,
                    'kind': 'operator',
                    'operator': '>',
                  },
                  'id': '0000000000000000000000000000001a',
                  'kind': 'check',
                  'name': 'authors_name_present',
                  'tableId': '00000000000000000000000000000003',
                },
                <String, Object?>{
                  'columnIds': <Object?>['00000000000000000000000000000004'],
                  'id': '0000000000000000000000000000001b',
                  'kind': 'primaryKey',
                  'name': 'authors_pkey',
                  'tableId': '00000000000000000000000000000003',
                },
              ],
              'id': '00000000000000000000000000000003',
              'indexes': <Object?>[
                <String, Object?>{
                  'id': '00000000000000000000000000000019',
                  'name': 'authors_name',
                  'options': <String, Object?>{},
                  'platforms': <Object?>['native', 'browser'],
                  'predicate': <String, Object?>{
                    'arguments': <Object?>[
                      <String, Object?>{
                        'arguments': <Object?>[
                          <String, Object?>{
                            'formatVersion': 1,
                            'kind': 'reference',
                            'objectId': '00000000000000000000000000000005',
                          },
                          <String, Object?>{
                            'formatVersion': 1,
                            'kind': 'literal',
                            'literalType': 'string',
                            'value': '',
                          },
                        ],
                        'formatVersion': 1,
                        'kind': 'operator',
                        'operator': '=',
                      },
                    ],
                    'formatVersion': 1,
                    'kind': 'operator',
                    'operator': 'NOT',
                  },
                  'tableId': '00000000000000000000000000000003',
                  'terms': <Object?>[
                    <String, Object?>{
                      'columnId': '00000000000000000000000000000005',
                      'descending': false,
                    },
                  ],
                  'unique': true,
                },
              ],
              'name': 'authors',
              'schemaId': '00000000000000000000000000000002',
            },
            <String, Object?>{
              'columns': <Object?>[
                <String, Object?>{
                  'id': '00000000000000000000000000000007',
                  'name': 'id',
                  'primaryKey': true,
                  'storage': <String, Object?>{
                    'codecVersion': 1,
                    'kind': 'text',
                    'nullable': false,
                  },
                  'tableId': '00000000000000000000000000000006',
                },
                <String, Object?>{
                  'id': '00000000000000000000000000000008',
                  'name': 'writerID',
                  'primaryKey': false,
                  'storage': <String, Object?>{
                    'codecVersion': 1,
                    'kind': 'text',
                    'nullable': false,
                  },
                  'tableId': '00000000000000000000000000000006',
                },
                <String, Object?>{
                  'id': '00000000000000000000000000000009',
                  'name': 'status',
                  'primaryKey': false,
                  'storage': <String, Object?>{
                    'codecVersion': 1,
                    'enumId': '00000000000000000000000000000018',
                    'kind': 'enum',
                    'nullable': false,
                  },
                  'tableId': '00000000000000000000000000000006',
                },
              ],
              'constraints': <Object?>[
                <String, Object?>{
                  'columnIds': <Object?>['00000000000000000000000000000008'],
                  'id': '0000000000000000000000000000001c',
                  'kind': 'foreignKey',
                  'name': 'posts_authorID_fkey',
                  'onDelete': 'noAction',
                  'onUpdate': 'noAction',
                  'referenceColumnIds': <Object?>['00000000000000000000000000000004'],
                  'referenceTableId': '00000000000000000000000000000003',
                  'tableId': '00000000000000000000000000000006',
                },
                <String, Object?>{
                  'columnIds': <Object?>['00000000000000000000000000000007'],
                  'id': '0000000000000000000000000000001d',
                  'kind': 'primaryKey',
                  'name': 'articles_pkey',
                  'tableId': '00000000000000000000000000000006',
                },
              ],
              'id': '00000000000000000000000000000006',
              'indexes': <Object?>[],
              'name': 'articles',
              'schemaId': '00000000000000000000000000000002',
            },
            <String, Object?>{
              'columns': <Object?>[
                <String, Object?>{
                  'id': '0000000000000000000000000000000b',
                  'name': 'id',
                  'primaryKey': true,
                  'storage': <String, Object?>{
                    'codecVersion': 1,
                    'kind': 'text',
                    'nullable': false,
                  },
                  'tableId': '0000000000000000000000000000000a',
                },
              ],
              'constraints': <Object?>[
                <String, Object?>{
                  'columnIds': <Object?>['0000000000000000000000000000000b'],
                  'id': '0000000000000000000000000000001e',
                  'kind': 'primaryKey',
                  'name': 'tags_pkey',
                  'tableId': '0000000000000000000000000000000a',
                },
              ],
              'id': '0000000000000000000000000000000a',
              'indexes': <Object?>[],
              'name': 'tags',
              'schemaId': '00000000000000000000000000000002',
            },
            <String, Object?>{
              'columns': <Object?>[
                <String, Object?>{
                  'id': '0000000000000000000000000000000d',
                  'name': 'postID',
                  'primaryKey': false,
                  'storage': <String, Object?>{
                    'codecVersion': 1,
                    'kind': 'text',
                    'nullable': false,
                  },
                  'tableId': '0000000000000000000000000000000c',
                },
                <String, Object?>{
                  'id': '0000000000000000000000000000000e',
                  'name': 'tagID',
                  'primaryKey': false,
                  'storage': <String, Object?>{
                    'codecVersion': 1,
                    'kind': 'text',
                    'nullable': false,
                  },
                  'tableId': '0000000000000000000000000000000c',
                },
              ],
              'constraints': <Object?>[
                <String, Object?>{
                  'columnIds': <Object?>['0000000000000000000000000000000d'],
                  'id': '0000000000000000000000000000001f',
                  'kind': 'foreignKey',
                  'name': 'postTags_postID_fkey',
                  'onDelete': 'noAction',
                  'onUpdate': 'noAction',
                  'referenceColumnIds': <Object?>['00000000000000000000000000000007'],
                  'referenceTableId': '00000000000000000000000000000006',
                  'tableId': '0000000000000000000000000000000c',
                },
                <String, Object?>{
                  'columnIds': <Object?>['0000000000000000000000000000000e'],
                  'id': '00000000000000000000000000000020',
                  'kind': 'foreignKey',
                  'name': 'postTags_tagID_fkey',
                  'onDelete': 'noAction',
                  'onUpdate': 'noAction',
                  'referenceColumnIds': <Object?>['0000000000000000000000000000000b'],
                  'referenceTableId': '0000000000000000000000000000000a',
                  'tableId': '0000000000000000000000000000000c',
                },
              ],
              'id': '0000000000000000000000000000000c',
              'indexes': <Object?>[],
              'name': 'postTags',
              'schemaId': '00000000000000000000000000000002',
            },
            <String, Object?>{
              'columns': <Object?>[
                <String, Object?>{
                  'id': '00000000000000000000000000000010',
                  'name': 'language',
                  'primaryKey': false,
                  'storage': <String, Object?>{
                    'codecVersion': 1,
                    'kind': 'text',
                    'nullable': false,
                  },
                  'tableId': '0000000000000000000000000000000f',
                },
                <String, Object?>{
                  'id': '00000000000000000000000000000011',
                  'name': 'key',
                  'primaryKey': false,
                  'storage': <String, Object?>{
                    'codecVersion': 1,
                    'kind': 'text',
                    'nullable': false,
                  },
                  'tableId': '0000000000000000000000000000000f',
                },
              ],
              'constraints': <Object?>[
                <String, Object?>{
                  'columnIds': <Object?>[
                    '00000000000000000000000000000010',
                    '00000000000000000000000000000011',
                  ],
                  'id': '00000000000000000000000000000021',
                  'kind': 'primaryKey',
                  'name': 'locales_pk',
                  'tableId': '0000000000000000000000000000000f',
                },
              ],
              'id': '0000000000000000000000000000000f',
              'indexes': <Object?>[],
              'name': 'locales',
              'schemaId': '00000000000000000000000000000002',
            },
            <String, Object?>{
              'columns': <Object?>[
                <String, Object?>{
                  'id': '00000000000000000000000000000013',
                  'name': 'language',
                  'primaryKey': false,
                  'storage': <String, Object?>{
                    'codecVersion': 1,
                    'kind': 'text',
                    'nullable': false,
                  },
                  'tableId': '00000000000000000000000000000012',
                },
                <String, Object?>{
                  'id': '00000000000000000000000000000014',
                  'name': 'key',
                  'primaryKey': false,
                  'storage': <String, Object?>{
                    'codecVersion': 1,
                    'kind': 'text',
                    'nullable': false,
                  },
                  'tableId': '00000000000000000000000000000012',
                },
                <String, Object?>{
                  'id': '00000000000000000000000000000015',
                  'name': 'value',
                  'primaryKey': false,
                  'storage': <String, Object?>{
                    'codecVersion': 1,
                    'kind': 'text',
                    'nullable': false,
                  },
                  'tableId': '00000000000000000000000000000012',
                },
              ],
              'constraints': <Object?>[
                <String, Object?>{
                  'columnIds': <Object?>[
                    '00000000000000000000000000000013',
                    '00000000000000000000000000000014',
                  ],
                  'id': '00000000000000000000000000000022',
                  'kind': 'foreignKey',
                  'name': 'translations_locale_fk',
                  'onDelete': 'cascade',
                  'onUpdate': 'noAction',
                  'referenceColumnIds': <Object?>[
                    '00000000000000000000000000000010',
                    '00000000000000000000000000000011',
                  ],
                  'referenceTableId': '0000000000000000000000000000000f',
                  'tableId': '00000000000000000000000000000012',
                },
              ],
              'id': '00000000000000000000000000000012',
              'indexes': <Object?>[],
              'name': 'translations',
              'schemaId': '00000000000000000000000000000002',
            },
          ],
        },
      ),
      VoxelBundledMigration(
        directory: '0001_rename_physical_objects_00000000000000000000000000000024',
        sql: 'ALTER TABLE "content"."articles" RENAME TO "posts";\nALTER TABLE "content"."posts" RENAME COLUMN "writerID" TO "authorID";\n',
        metadata: <String, Object?>{
          'checksum': 'ed0b7ba45cf318d72fdeaa602b20b2eb3d3422c606cad93077851c4f314396a4',
          'databaseId': '00000000000000000000000000000001',
          'dialect': 'voxel',
          'formatVersion': 1,
          'id': '00000000000000000000000000000024',
          'parentId': '00000000000000000000000000000023',
          'phases': <Object?>[
            <String, Object?>{
              'id': '0',
              'mode': 'transactional',
              'platforms': <Object?>['native', 'browser'],
              'recovery': null,
              'scopeId': '00000000000000000000000000000002',
              'statements': <Object?>[
                <String, Object?>{'endByte': 51, 'startByte': 0},
                <String, Object?>{'endByte': 121, 'startByte': 52},
              ],
            },
          ],
        },
        snapshot: <String, Object?>{
          'databaseId': '00000000000000000000000000000001',
          'dialect': 'voxel',
          'enums': <Object?>[
            <String, Object?>{
              'id': '00000000000000000000000000000018',
              'name': 'articleStatus',
              'schemaId': '00000000000000000000000000000002',
              'values': <Object?>[
                <String, Object?>{
                  'enumId': '00000000000000000000000000000018',
                  'id': '00000000000000000000000000000016',
                  'label': 'draft',
                },
                <String, Object?>{
                  'enumId': '00000000000000000000000000000018',
                  'id': '00000000000000000000000000000017',
                  'label': 'published',
                },
              ],
            },
          ],
          'formatVersion': 1,
          'migrationId': '00000000000000000000000000000024',
          'requirements': <Object?>[],
          'schemas': <Object?>[
            <String, Object?>{'id': '00000000000000000000000000000002', 'name': 'content'},
          ],
          'tables': <Object?>[
            <String, Object?>{
              'columns': <Object?>[
                <String, Object?>{
                  'id': '00000000000000000000000000000004',
                  'name': 'id',
                  'primaryKey': true,
                  'storage': <String, Object?>{
                    'codecVersion': 1,
                    'kind': 'text',
                    'nullable': false,
                  },
                  'tableId': '00000000000000000000000000000003',
                },
                <String, Object?>{
                  'id': '00000000000000000000000000000005',
                  'name': 'name',
                  'primaryKey': false,
                  'storage': <String, Object?>{
                    'codecVersion': 1,
                    'kind': 'text',
                    'nullable': false,
                  },
                  'tableId': '00000000000000000000000000000003',
                },
              ],
              'constraints': <Object?>[
                <String, Object?>{
                  'columnIds': <Object?>[],
                  'expression': <String, Object?>{
                    'arguments': <Object?>[
                      <String, Object?>{
                        'formatVersion': 1,
                        'kind': 'reference',
                        'objectId': '00000000000000000000000000000005',
                      },
                      <String, Object?>{
                        'formatVersion': 1,
                        'kind': 'literal',
                        'literalType': 'string',
                        'value': '',
                      },
                    ],
                    'formatVersion': 1,
                    'kind': 'operator',
                    'operator': '>',
                  },
                  'id': '0000000000000000000000000000001a',
                  'kind': 'check',
                  'name': 'authors_name_present',
                  'tableId': '00000000000000000000000000000003',
                },
                <String, Object?>{
                  'columnIds': <Object?>['00000000000000000000000000000004'],
                  'id': '0000000000000000000000000000001b',
                  'kind': 'primaryKey',
                  'name': 'authors_pkey',
                  'tableId': '00000000000000000000000000000003',
                },
              ],
              'id': '00000000000000000000000000000003',
              'indexes': <Object?>[
                <String, Object?>{
                  'id': '00000000000000000000000000000019',
                  'name': 'authors_name',
                  'options': <String, Object?>{},
                  'platforms': <Object?>['native', 'browser'],
                  'predicate': <String, Object?>{
                    'arguments': <Object?>[
                      <String, Object?>{
                        'arguments': <Object?>[
                          <String, Object?>{
                            'formatVersion': 1,
                            'kind': 'reference',
                            'objectId': '00000000000000000000000000000005',
                          },
                          <String, Object?>{
                            'formatVersion': 1,
                            'kind': 'literal',
                            'literalType': 'string',
                            'value': '',
                          },
                        ],
                        'formatVersion': 1,
                        'kind': 'operator',
                        'operator': '=',
                      },
                    ],
                    'formatVersion': 1,
                    'kind': 'operator',
                    'operator': 'NOT',
                  },
                  'tableId': '00000000000000000000000000000003',
                  'terms': <Object?>[
                    <String, Object?>{
                      'columnId': '00000000000000000000000000000005',
                      'descending': false,
                    },
                  ],
                  'unique': true,
                },
              ],
              'name': 'authors',
              'schemaId': '00000000000000000000000000000002',
            },
            <String, Object?>{
              'columns': <Object?>[
                <String, Object?>{
                  'id': '00000000000000000000000000000007',
                  'name': 'id',
                  'primaryKey': true,
                  'storage': <String, Object?>{
                    'codecVersion': 1,
                    'kind': 'text',
                    'nullable': false,
                  },
                  'tableId': '00000000000000000000000000000006',
                },
                <String, Object?>{
                  'id': '00000000000000000000000000000008',
                  'name': 'authorID',
                  'primaryKey': false,
                  'storage': <String, Object?>{
                    'codecVersion': 1,
                    'kind': 'text',
                    'nullable': false,
                  },
                  'tableId': '00000000000000000000000000000006',
                },
                <String, Object?>{
                  'id': '00000000000000000000000000000009',
                  'name': 'status',
                  'primaryKey': false,
                  'storage': <String, Object?>{
                    'codecVersion': 1,
                    'enumId': '00000000000000000000000000000018',
                    'kind': 'enum',
                    'nullable': false,
                  },
                  'tableId': '00000000000000000000000000000006',
                },
              ],
              'constraints': <Object?>[
                <String, Object?>{
                  'columnIds': <Object?>['00000000000000000000000000000008'],
                  'id': '0000000000000000000000000000001c',
                  'kind': 'foreignKey',
                  'name': 'posts_authorID_fkey',
                  'onDelete': 'noAction',
                  'onUpdate': 'noAction',
                  'referenceColumnIds': <Object?>['00000000000000000000000000000004'],
                  'referenceTableId': '00000000000000000000000000000003',
                  'tableId': '00000000000000000000000000000006',
                },
                <String, Object?>{
                  'columnIds': <Object?>['00000000000000000000000000000007'],
                  'id': '0000000000000000000000000000001d',
                  'kind': 'primaryKey',
                  'name': 'posts_pkey',
                  'tableId': '00000000000000000000000000000006',
                },
              ],
              'id': '00000000000000000000000000000006',
              'indexes': <Object?>[],
              'name': 'posts',
              'schemaId': '00000000000000000000000000000002',
            },
            <String, Object?>{
              'columns': <Object?>[
                <String, Object?>{
                  'id': '0000000000000000000000000000000b',
                  'name': 'id',
                  'primaryKey': true,
                  'storage': <String, Object?>{
                    'codecVersion': 1,
                    'kind': 'text',
                    'nullable': false,
                  },
                  'tableId': '0000000000000000000000000000000a',
                },
              ],
              'constraints': <Object?>[
                <String, Object?>{
                  'columnIds': <Object?>['0000000000000000000000000000000b'],
                  'id': '0000000000000000000000000000001e',
                  'kind': 'primaryKey',
                  'name': 'tags_pkey',
                  'tableId': '0000000000000000000000000000000a',
                },
              ],
              'id': '0000000000000000000000000000000a',
              'indexes': <Object?>[],
              'name': 'tags',
              'schemaId': '00000000000000000000000000000002',
            },
            <String, Object?>{
              'columns': <Object?>[
                <String, Object?>{
                  'id': '0000000000000000000000000000000d',
                  'name': 'postID',
                  'primaryKey': false,
                  'storage': <String, Object?>{
                    'codecVersion': 1,
                    'kind': 'text',
                    'nullable': false,
                  },
                  'tableId': '0000000000000000000000000000000c',
                },
                <String, Object?>{
                  'id': '0000000000000000000000000000000e',
                  'name': 'tagID',
                  'primaryKey': false,
                  'storage': <String, Object?>{
                    'codecVersion': 1,
                    'kind': 'text',
                    'nullable': false,
                  },
                  'tableId': '0000000000000000000000000000000c',
                },
              ],
              'constraints': <Object?>[
                <String, Object?>{
                  'columnIds': <Object?>['0000000000000000000000000000000d'],
                  'id': '0000000000000000000000000000001f',
                  'kind': 'foreignKey',
                  'name': 'postTags_postID_fkey',
                  'onDelete': 'noAction',
                  'onUpdate': 'noAction',
                  'referenceColumnIds': <Object?>['00000000000000000000000000000007'],
                  'referenceTableId': '00000000000000000000000000000006',
                  'tableId': '0000000000000000000000000000000c',
                },
                <String, Object?>{
                  'columnIds': <Object?>['0000000000000000000000000000000e'],
                  'id': '00000000000000000000000000000020',
                  'kind': 'foreignKey',
                  'name': 'postTags_tagID_fkey',
                  'onDelete': 'noAction',
                  'onUpdate': 'noAction',
                  'referenceColumnIds': <Object?>['0000000000000000000000000000000b'],
                  'referenceTableId': '0000000000000000000000000000000a',
                  'tableId': '0000000000000000000000000000000c',
                },
              ],
              'id': '0000000000000000000000000000000c',
              'indexes': <Object?>[],
              'name': 'postTags',
              'schemaId': '00000000000000000000000000000002',
            },
            <String, Object?>{
              'columns': <Object?>[
                <String, Object?>{
                  'id': '00000000000000000000000000000010',
                  'name': 'language',
                  'primaryKey': false,
                  'storage': <String, Object?>{
                    'codecVersion': 1,
                    'kind': 'text',
                    'nullable': false,
                  },
                  'tableId': '0000000000000000000000000000000f',
                },
                <String, Object?>{
                  'id': '00000000000000000000000000000011',
                  'name': 'key',
                  'primaryKey': false,
                  'storage': <String, Object?>{
                    'codecVersion': 1,
                    'kind': 'text',
                    'nullable': false,
                  },
                  'tableId': '0000000000000000000000000000000f',
                },
              ],
              'constraints': <Object?>[
                <String, Object?>{
                  'columnIds': <Object?>[
                    '00000000000000000000000000000010',
                    '00000000000000000000000000000011',
                  ],
                  'id': '00000000000000000000000000000021',
                  'kind': 'primaryKey',
                  'name': 'locales_pk',
                  'tableId': '0000000000000000000000000000000f',
                },
              ],
              'id': '0000000000000000000000000000000f',
              'indexes': <Object?>[],
              'name': 'locales',
              'schemaId': '00000000000000000000000000000002',
            },
            <String, Object?>{
              'columns': <Object?>[
                <String, Object?>{
                  'id': '00000000000000000000000000000013',
                  'name': 'language',
                  'primaryKey': false,
                  'storage': <String, Object?>{
                    'codecVersion': 1,
                    'kind': 'text',
                    'nullable': false,
                  },
                  'tableId': '00000000000000000000000000000012',
                },
                <String, Object?>{
                  'id': '00000000000000000000000000000014',
                  'name': 'key',
                  'primaryKey': false,
                  'storage': <String, Object?>{
                    'codecVersion': 1,
                    'kind': 'text',
                    'nullable': false,
                  },
                  'tableId': '00000000000000000000000000000012',
                },
                <String, Object?>{
                  'id': '00000000000000000000000000000015',
                  'name': 'value',
                  'primaryKey': false,
                  'storage': <String, Object?>{
                    'codecVersion': 1,
                    'kind': 'text',
                    'nullable': false,
                  },
                  'tableId': '00000000000000000000000000000012',
                },
              ],
              'constraints': <Object?>[
                <String, Object?>{
                  'columnIds': <Object?>[
                    '00000000000000000000000000000013',
                    '00000000000000000000000000000014',
                  ],
                  'id': '00000000000000000000000000000022',
                  'kind': 'foreignKey',
                  'name': 'translations_locale_fk',
                  'onDelete': 'cascade',
                  'onUpdate': 'noAction',
                  'referenceColumnIds': <Object?>[
                    '00000000000000000000000000000010',
                    '00000000000000000000000000000011',
                  ],
                  'referenceTableId': '0000000000000000000000000000000f',
                  'tableId': '00000000000000000000000000000012',
                },
              ],
              'id': '00000000000000000000000000000012',
              'indexes': <Object?>[],
              'name': 'translations',
              'schemaId': '00000000000000000000000000000002',
            },
          ],
        },
      ),
      VoxelBundledMigration(
        directory: '0002_evolve_enum_labels_00000000000000000000000000000025',
        sql: '-- reviewed bundle fixture\nCREATE TABLE "content"."__voxel_rebuild_000000000000" (\n  "id" TEXT NOT NULL,\n  "authorID" TEXT NOT NULL,\n  "status" TEXT NOT NULL,\n  CHECK ("status" IN (\'draft\', \'live\')),\n  CONSTRAINT "posts_authorID_fkey" FOREIGN KEY ("authorID") REFERENCES "authors" ("id") ON DELETE NO ACTION ON UPDATE NO ACTION,\n  CONSTRAINT "posts_pkey" PRIMARY KEY ("id")\n);\nINSERT INTO "content"."__voxel_rebuild_000000000000" ("id", "authorID", "status") SELECT "id", "authorID", CASE "status" WHEN \'published\' THEN \'live\' ELSE "status" END FROM "content"."posts";\nDROP TABLE "content"."posts";\nALTER TABLE "content"."__voxel_rebuild_000000000000" RENAME TO "posts";\n',
        metadata: <String, Object?>{
          'checksum': '8ab80af084c54d4797cc66551226fa08b649f0768cb72d6c90cdf52fcac0ccf8',
          'databaseId': '00000000000000000000000000000001',
          'dialect': 'voxel',
          'formatVersion': 1,
          'id': '00000000000000000000000000000025',
          'parentId': '00000000000000000000000000000024',
          'phases': <Object?>[
            <String, Object?>{
              'id': '0',
              'mode': 'transactional',
              'platforms': <Object?>['native', 'browser'],
              'rebuild': <String, Object?>{
                'foreignKeys': 'offOutsideTransaction',
                'validations': <Object?>[
                  <String, Object?>{
                    'constraintId': '0000000000000000000000000000001c',
                    'kind': 'foreignKeyAntiJoin',
                    'sql': 'SELECT NOT EXISTS (SELECT 1 FROM "content"."posts" AS "voxel_child" WHERE "voxel_child"."authorID" IS NOT NULL AND NOT EXISTS (SELECT 1 FROM "content"."authors" AS "voxel_parent" WHERE "voxel_parent"."id" = "voxel_child"."authorID")) AS "valid";',
                    'tableId': '00000000000000000000000000000006',
                  },
                  <String, Object?>{
                    'constraintId': '0000000000000000000000000000001f',
                    'kind': 'foreignKeyAntiJoin',
                    'sql': 'SELECT NOT EXISTS (SELECT 1 FROM "content"."postTags" AS "voxel_child" WHERE "voxel_child"."postID" IS NOT NULL AND NOT EXISTS (SELECT 1 FROM "content"."posts" AS "voxel_parent" WHERE "voxel_parent"."id" = "voxel_child"."postID")) AS "valid";',
                    'tableId': '0000000000000000000000000000000c',
                  },
                  <String, Object?>{
                    'constraintId': '00000000000000000000000000000020',
                    'kind': 'foreignKeyAntiJoin',
                    'sql': 'SELECT NOT EXISTS (SELECT 1 FROM "content"."postTags" AS "voxel_child" WHERE "voxel_child"."tagID" IS NOT NULL AND NOT EXISTS (SELECT 1 FROM "content"."tags" AS "voxel_parent" WHERE "voxel_parent"."id" = "voxel_child"."tagID")) AS "valid";',
                    'tableId': '0000000000000000000000000000000c',
                  },
                  <String, Object?>{
                    'constraintId': '00000000000000000000000000000022',
                    'kind': 'foreignKeyAntiJoin',
                    'sql': 'SELECT NOT EXISTS (SELECT 1 FROM "content"."translations" AS "voxel_child" WHERE "voxel_child"."language" IS NOT NULL AND "voxel_child"."key" IS NOT NULL AND NOT EXISTS (SELECT 1 FROM "content"."locales" AS "voxel_parent" WHERE "voxel_parent"."language" = "voxel_child"."language" AND "voxel_parent"."key" = "voxel_child"."key")) AS "valid";',
                    'tableId': '00000000000000000000000000000012',
                  },
                ],
              },
              'recovery': null,
              'scopeId': '00000000000000000000000000000002',
              'statements': <Object?>[
                <String, Object?>{'endByte': 376, 'startByte': 0},
                <String, Object?>{'endByte': 568, 'startByte': 377},
                <String, Object?>{'endByte': 598, 'startByte': 569},
                <String, Object?>{'endByte': 670, 'startByte': 599},
              ],
            },
          ],
        },
        snapshot: <String, Object?>{
          'databaseId': '00000000000000000000000000000001',
          'dialect': 'voxel',
          'enums': <Object?>[
            <String, Object?>{
              'id': '00000000000000000000000000000018',
              'name': 'postStatus',
              'schemaId': '00000000000000000000000000000002',
              'values': <Object?>[
                <String, Object?>{
                  'enumId': '00000000000000000000000000000018',
                  'id': '00000000000000000000000000000016',
                  'label': 'draft',
                },
                <String, Object?>{
                  'enumId': '00000000000000000000000000000018',
                  'id': '00000000000000000000000000000017',
                  'label': 'live',
                },
              ],
            },
          ],
          'formatVersion': 1,
          'migrationId': '00000000000000000000000000000025',
          'requirements': <Object?>[],
          'schemas': <Object?>[
            <String, Object?>{'id': '00000000000000000000000000000002', 'name': 'content'},
          ],
          'tables': <Object?>[
            <String, Object?>{
              'columns': <Object?>[
                <String, Object?>{
                  'id': '00000000000000000000000000000004',
                  'name': 'id',
                  'primaryKey': true,
                  'storage': <String, Object?>{
                    'codecVersion': 1,
                    'kind': 'text',
                    'nullable': false,
                  },
                  'tableId': '00000000000000000000000000000003',
                },
                <String, Object?>{
                  'id': '00000000000000000000000000000005',
                  'name': 'name',
                  'primaryKey': false,
                  'storage': <String, Object?>{
                    'codecVersion': 1,
                    'kind': 'text',
                    'nullable': false,
                  },
                  'tableId': '00000000000000000000000000000003',
                },
              ],
              'constraints': <Object?>[
                <String, Object?>{
                  'columnIds': <Object?>[],
                  'expression': <String, Object?>{
                    'arguments': <Object?>[
                      <String, Object?>{
                        'formatVersion': 1,
                        'kind': 'reference',
                        'objectId': '00000000000000000000000000000005',
                      },
                      <String, Object?>{
                        'formatVersion': 1,
                        'kind': 'literal',
                        'literalType': 'string',
                        'value': '',
                      },
                    ],
                    'formatVersion': 1,
                    'kind': 'operator',
                    'operator': '>',
                  },
                  'id': '0000000000000000000000000000001a',
                  'kind': 'check',
                  'name': 'authors_name_present',
                  'tableId': '00000000000000000000000000000003',
                },
                <String, Object?>{
                  'columnIds': <Object?>['00000000000000000000000000000004'],
                  'id': '0000000000000000000000000000001b',
                  'kind': 'primaryKey',
                  'name': 'authors_pkey',
                  'tableId': '00000000000000000000000000000003',
                },
              ],
              'id': '00000000000000000000000000000003',
              'indexes': <Object?>[
                <String, Object?>{
                  'id': '00000000000000000000000000000019',
                  'name': 'authors_name',
                  'options': <String, Object?>{},
                  'platforms': <Object?>['native', 'browser'],
                  'predicate': <String, Object?>{
                    'arguments': <Object?>[
                      <String, Object?>{
                        'arguments': <Object?>[
                          <String, Object?>{
                            'formatVersion': 1,
                            'kind': 'reference',
                            'objectId': '00000000000000000000000000000005',
                          },
                          <String, Object?>{
                            'formatVersion': 1,
                            'kind': 'literal',
                            'literalType': 'string',
                            'value': '',
                          },
                        ],
                        'formatVersion': 1,
                        'kind': 'operator',
                        'operator': '=',
                      },
                    ],
                    'formatVersion': 1,
                    'kind': 'operator',
                    'operator': 'NOT',
                  },
                  'tableId': '00000000000000000000000000000003',
                  'terms': <Object?>[
                    <String, Object?>{
                      'columnId': '00000000000000000000000000000005',
                      'descending': false,
                    },
                  ],
                  'unique': true,
                },
              ],
              'name': 'authors',
              'schemaId': '00000000000000000000000000000002',
            },
            <String, Object?>{
              'columns': <Object?>[
                <String, Object?>{
                  'id': '00000000000000000000000000000007',
                  'name': 'id',
                  'primaryKey': true,
                  'storage': <String, Object?>{
                    'codecVersion': 1,
                    'kind': 'text',
                    'nullable': false,
                  },
                  'tableId': '00000000000000000000000000000006',
                },
                <String, Object?>{
                  'id': '00000000000000000000000000000008',
                  'name': 'authorID',
                  'primaryKey': false,
                  'storage': <String, Object?>{
                    'codecVersion': 1,
                    'kind': 'text',
                    'nullable': false,
                  },
                  'tableId': '00000000000000000000000000000006',
                },
                <String, Object?>{
                  'id': '00000000000000000000000000000009',
                  'name': 'status',
                  'primaryKey': false,
                  'storage': <String, Object?>{
                    'codecVersion': 1,
                    'enumId': '00000000000000000000000000000018',
                    'kind': 'enum',
                    'nullable': false,
                  },
                  'tableId': '00000000000000000000000000000006',
                },
              ],
              'constraints': <Object?>[
                <String, Object?>{
                  'columnIds': <Object?>['00000000000000000000000000000008'],
                  'id': '0000000000000000000000000000001c',
                  'kind': 'foreignKey',
                  'name': 'posts_authorID_fkey',
                  'onDelete': 'noAction',
                  'onUpdate': 'noAction',
                  'referenceColumnIds': <Object?>['00000000000000000000000000000004'],
                  'referenceTableId': '00000000000000000000000000000003',
                  'tableId': '00000000000000000000000000000006',
                },
                <String, Object?>{
                  'columnIds': <Object?>['00000000000000000000000000000007'],
                  'id': '0000000000000000000000000000001d',
                  'kind': 'primaryKey',
                  'name': 'posts_pkey',
                  'tableId': '00000000000000000000000000000006',
                },
              ],
              'id': '00000000000000000000000000000006',
              'indexes': <Object?>[],
              'name': 'posts',
              'schemaId': '00000000000000000000000000000002',
            },
            <String, Object?>{
              'columns': <Object?>[
                <String, Object?>{
                  'id': '0000000000000000000000000000000b',
                  'name': 'id',
                  'primaryKey': true,
                  'storage': <String, Object?>{
                    'codecVersion': 1,
                    'kind': 'text',
                    'nullable': false,
                  },
                  'tableId': '0000000000000000000000000000000a',
                },
              ],
              'constraints': <Object?>[
                <String, Object?>{
                  'columnIds': <Object?>['0000000000000000000000000000000b'],
                  'id': '0000000000000000000000000000001e',
                  'kind': 'primaryKey',
                  'name': 'tags_pkey',
                  'tableId': '0000000000000000000000000000000a',
                },
              ],
              'id': '0000000000000000000000000000000a',
              'indexes': <Object?>[],
              'name': 'tags',
              'schemaId': '00000000000000000000000000000002',
            },
            <String, Object?>{
              'columns': <Object?>[
                <String, Object?>{
                  'id': '0000000000000000000000000000000d',
                  'name': 'postID',
                  'primaryKey': false,
                  'storage': <String, Object?>{
                    'codecVersion': 1,
                    'kind': 'text',
                    'nullable': false,
                  },
                  'tableId': '0000000000000000000000000000000c',
                },
                <String, Object?>{
                  'id': '0000000000000000000000000000000e',
                  'name': 'tagID',
                  'primaryKey': false,
                  'storage': <String, Object?>{
                    'codecVersion': 1,
                    'kind': 'text',
                    'nullable': false,
                  },
                  'tableId': '0000000000000000000000000000000c',
                },
              ],
              'constraints': <Object?>[
                <String, Object?>{
                  'columnIds': <Object?>['0000000000000000000000000000000d'],
                  'id': '0000000000000000000000000000001f',
                  'kind': 'foreignKey',
                  'name': 'postTags_postID_fkey',
                  'onDelete': 'noAction',
                  'onUpdate': 'noAction',
                  'referenceColumnIds': <Object?>['00000000000000000000000000000007'],
                  'referenceTableId': '00000000000000000000000000000006',
                  'tableId': '0000000000000000000000000000000c',
                },
                <String, Object?>{
                  'columnIds': <Object?>['0000000000000000000000000000000e'],
                  'id': '00000000000000000000000000000020',
                  'kind': 'foreignKey',
                  'name': 'postTags_tagID_fkey',
                  'onDelete': 'noAction',
                  'onUpdate': 'noAction',
                  'referenceColumnIds': <Object?>['0000000000000000000000000000000b'],
                  'referenceTableId': '0000000000000000000000000000000a',
                  'tableId': '0000000000000000000000000000000c',
                },
              ],
              'id': '0000000000000000000000000000000c',
              'indexes': <Object?>[],
              'name': 'postTags',
              'schemaId': '00000000000000000000000000000002',
            },
            <String, Object?>{
              'columns': <Object?>[
                <String, Object?>{
                  'id': '00000000000000000000000000000010',
                  'name': 'language',
                  'primaryKey': false,
                  'storage': <String, Object?>{
                    'codecVersion': 1,
                    'kind': 'text',
                    'nullable': false,
                  },
                  'tableId': '0000000000000000000000000000000f',
                },
                <String, Object?>{
                  'id': '00000000000000000000000000000011',
                  'name': 'key',
                  'primaryKey': false,
                  'storage': <String, Object?>{
                    'codecVersion': 1,
                    'kind': 'text',
                    'nullable': false,
                  },
                  'tableId': '0000000000000000000000000000000f',
                },
              ],
              'constraints': <Object?>[
                <String, Object?>{
                  'columnIds': <Object?>[
                    '00000000000000000000000000000010',
                    '00000000000000000000000000000011',
                  ],
                  'id': '00000000000000000000000000000021',
                  'kind': 'primaryKey',
                  'name': 'locales_pk',
                  'tableId': '0000000000000000000000000000000f',
                },
              ],
              'id': '0000000000000000000000000000000f',
              'indexes': <Object?>[],
              'name': 'locales',
              'schemaId': '00000000000000000000000000000002',
            },
            <String, Object?>{
              'columns': <Object?>[
                <String, Object?>{
                  'id': '00000000000000000000000000000013',
                  'name': 'language',
                  'primaryKey': false,
                  'storage': <String, Object?>{
                    'codecVersion': 1,
                    'kind': 'text',
                    'nullable': false,
                  },
                  'tableId': '00000000000000000000000000000012',
                },
                <String, Object?>{
                  'id': '00000000000000000000000000000014',
                  'name': 'key',
                  'primaryKey': false,
                  'storage': <String, Object?>{
                    'codecVersion': 1,
                    'kind': 'text',
                    'nullable': false,
                  },
                  'tableId': '00000000000000000000000000000012',
                },
                <String, Object?>{
                  'id': '00000000000000000000000000000015',
                  'name': 'value',
                  'primaryKey': false,
                  'storage': <String, Object?>{
                    'codecVersion': 1,
                    'kind': 'text',
                    'nullable': false,
                  },
                  'tableId': '00000000000000000000000000000012',
                },
              ],
              'constraints': <Object?>[
                <String, Object?>{
                  'columnIds': <Object?>[
                    '00000000000000000000000000000013',
                    '00000000000000000000000000000014',
                  ],
                  'id': '00000000000000000000000000000022',
                  'kind': 'foreignKey',
                  'name': 'translations_locale_fk',
                  'onDelete': 'cascade',
                  'onUpdate': 'noAction',
                  'referenceColumnIds': <Object?>[
                    '00000000000000000000000000000010',
                    '00000000000000000000000000000011',
                  ],
                  'referenceTableId': '0000000000000000000000000000000f',
                  'tableId': '00000000000000000000000000000012',
                },
              ],
              'id': '00000000000000000000000000000012',
              'indexes': <Object?>[],
              'name': 'translations',
              'schemaId': '00000000000000000000000000000002',
            },
          ],
        },
      ),
    ],
  );
}

/// Opens [FixtureAppDatabase] through its checked migration bundle.
extension FixtureAppDatabaseVoxelOpen on FixtureAppDatabase {
  /// Opens and owns a fully initialized Voxel database.
  Future<VoxelDb> open({
    VoxelStorage? storage,
    Map<String, VoxelStorage> schemaStorage = const {},
    VoxelEncryption? encryption,
    Map<String, VoxelEncryption?> schemaEncryption = const {},
    VoxelMigrationOptions migrations = const VoxelMigrationOptions(),
  }) => VoxelDatabaseRuntime.open(
    schema: schema,
    bundle: FixtureAppDatabaseVoxelMigrations.bundle,
    storage: storage,
    schemaStorage: schemaStorage,
    encryption: encryption,
    schemaEncryption: schemaEncryption,
    migrations: migrations,
  );
}
