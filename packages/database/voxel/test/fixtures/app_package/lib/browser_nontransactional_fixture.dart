// Static checked artifacts for browser recovery integration coverage.
// ignore_for_file: leading_newlines_in_multiline_strings, public_member_api_docs

import 'dart:convert';

import 'package:voxel/voxel.dart';
import 'package:voxel_fixture_schema/authors.dart';

final browserRecoverySchema = VoxelDatabaseSchema(
  name: 'browser_recovery_fixture',
  tables: [Authors.db.buildSchema() as VoxelTableSchema<Object?, Object?>],
);

final browserRecoveryBundle = VoxelMigrationBundle(
  databaseId: '04a3d4ee1b72bf9acfb8fed038fff027',
  migrations: [
    VoxelBundledMigration(
      directory: '0000_initial_0a07daacc7389f15990bfb8047fb8ed9',
      sql: _sql,
      metadata: jsonDecode(_metadata) as Map<String, Object?>,
      snapshot: jsonDecode(_snapshot) as Map<String, Object?>,
    ),
  ],
);

const _sql = '''CREATE TABLE "content"."authors" (
  "id" TEXT NOT NULL,
  "name" TEXT NOT NULL,
  CONSTRAINT "authors_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "authors_name_present" CHECK (("name" > ''))
);
CREATE UNIQUE INDEX "content"."authors_name" ON "authors" ("name" ASC) WHERE NOT (("name" = ''));
''';

const _metadata = r'''
{
  "checksum": "1935ae646770bc9247e6bd14c27e842ec72d12bb84ee1735913b211307c3d26c",
  "databaseId": "04a3d4ee1b72bf9acfb8fed038fff027",
  "dialect": "voxel",
  "formatVersion": 1,
  "id": "0a07daacc7389f15990bfb8047fb8ed9",
  "parentId": null,
  "phases": [
    {
      "id": "0",
      "mode": "nontransactional",
      "platforms": ["native", "browser"],
      "recovery": {
        "after": {
          "schema": "content",
          "sql": "CREATE TABLE \"authors\" (\"id\" TEXT NOT NULL, \"name\" TEXT NOT NULL, CONSTRAINT \"authors_pkey\" PRIMARY KEY (\"id\"), CONSTRAINT \"authors_name_present\" CHECK ((\"name\" > '')))",
          "table": "authors"
        },
        "before": {"exists": false, "schema": "content", "table": "authors"},
        "checks": [
          {
            "expected": false,
            "parameters": [
              {"type": "string", "value": "table"},
              {"type": "string", "value": "authors"},
              {"type": "string", "value": "authors"}
            ],
            "sql": "SELECT NOT EXISTS (SELECT 1 FROM \"content\".sqlite_schema WHERE type = ? AND name = ? AND tbl_name = ?)"
          },
          {
            "expected": true,
            "parameters": [
              {"type": "string", "value": "table"},
              {"type": "string", "value": "authors"},
              {"type": "string", "value": "authors"},
              {"type": "string", "value": "CREATE TABLE \"authors\" (\"id\" TEXT NOT NULL, \"name\" TEXT NOT NULL, CONSTRAINT \"authors_pkey\" PRIMARY KEY (\"id\"), CONSTRAINT \"authors_name_present\" CHECK ((\"name\" > '')))"}
            ],
            "sql": "SELECT EXISTS (SELECT 1 FROM \"content\".sqlite_schema WHERE type = ? AND name = ? AND tbl_name = ? AND sql = ?)"
          }
        ],
        "kind": "catalog",
        "operationId": "11111111111111111111111111111111"
      },
      "scopeId": "8bbd3cc0aa82067e8adefab4b0a8fdd9",
      "statements": [
        {"endByte": 189, "startByte": 0},
        {"endByte": 287, "startByte": 190}
      ],
      "writeScopeIds": ["8bbd3cc0aa82067e8adefab4b0a8fdd9"]
    }
  ]
}
''';

const _snapshot = '''
{
  "databaseId": "04a3d4ee1b72bf9acfb8fed038fff027",
  "dialect": "voxel",
  "enums": [],
  "formatVersion": 1,
  "migrationId": "0a07daacc7389f15990bfb8047fb8ed9",
  "requirements": [],
  "schemas": [{"id": "8bbd3cc0aa82067e8adefab4b0a8fdd9", "name": "content"}],
  "tables": [
    {
      "columns": [
        {
          "id": "a98f215bc44c5b42eb5e1726bf6fe4e3",
          "name": "id",
          "primaryKey": true,
          "storage": {"codecVersion": 1, "kind": "text", "nullable": false},
          "tableId": "f0b87b4935a234c90e29b4293323c301"
        },
        {
          "id": "c2852dda018d01a3ea459ae4534c992e",
          "name": "name",
          "primaryKey": false,
          "storage": {"codecVersion": 1, "kind": "text", "nullable": false},
          "tableId": "f0b87b4935a234c90e29b4293323c301"
        }
      ],
      "constraints": [
        {
          "columnIds": ["a98f215bc44c5b42eb5e1726bf6fe4e3"],
          "id": "1246d27a8130651b0528265823a2dc4c",
          "kind": "primaryKey",
          "name": "authors_pkey",
          "tableId": "f0b87b4935a234c90e29b4293323c301"
        },
        {
          "columnIds": [],
          "expression": {
            "arguments": [
              {"formatVersion": 1, "kind": "reference", "objectId": "c2852dda018d01a3ea459ae4534c992e"},
              {"formatVersion": 1, "kind": "literal", "literalType": "string", "value": ""}
            ],
            "formatVersion": 1,
            "kind": "operator",
            "operator": ">"
          },
          "id": "ab09fe0366efe05fdbeb4f4f75e74b34",
          "kind": "check",
          "name": "authors_name_present",
          "tableId": "f0b87b4935a234c90e29b4293323c301"
        }
      ],
      "id": "f0b87b4935a234c90e29b4293323c301",
      "indexes": [
        {
          "id": "1429889b910010cda90aba24ba9bf7b1",
          "name": "authors_name",
          "options": {},
          "platforms": ["native", "browser"],
          "predicate": {
            "arguments": [
              {
                "arguments": [
                  {"formatVersion": 1, "kind": "reference", "objectId": "c2852dda018d01a3ea459ae4534c992e"},
                  {"formatVersion": 1, "kind": "literal", "literalType": "string", "value": ""}
                ],
                "formatVersion": 1,
                "kind": "operator",
                "operator": "="
              }
            ],
            "formatVersion": 1,
            "kind": "operator",
            "operator": "NOT"
          },
          "tableId": "f0b87b4935a234c90e29b4293323c301",
          "terms": [{"columnId": "c2852dda018d01a3ea459ae4534c992e", "descending": false}],
          "unique": true
        }
      ],
      "name": "authors",
      "schemaId": "8bbd3cc0aa82067e8adefab4b0a8fdd9"
    }
  ]
}
''';
