// Static checked artifacts copied from the native cyclic rebuild fixture.
// ignore_for_file: public_member_api_docs, unnecessary_raw_strings

import 'dart:convert';

import 'package:voxel/voxel.dart';

final browserCyclicRebuildBundle = VoxelMigrationBundle(
  databaseId: '00000000000000000000000000000001',
  migrations: [
    VoxelBundledMigration(
      directory: '0000_initial_00000000000000000000000000000013',
      sql: r'''
CREATE TABLE "content"."parents" (
  "tenant" TEXT NOT NULL,
  "id" TEXT NOT NULL,
  "name" TEXT NOT NULL,
  "favoriteChildTenant" TEXT,
  "favoriteChildId" TEXT,
  CONSTRAINT "parents_pk" PRIMARY KEY ("tenant", "id"),
  CONSTRAINT "parents_favorite_child_fk" FOREIGN KEY ("favoriteChildTenant", "favoriteChildId") REFERENCES "children" ("tenant", "id") ON DELETE NO ACTION ON UPDATE NO ACTION
);
CREATE TABLE "content"."children" (
  "tenant" TEXT NOT NULL,
  "id" TEXT NOT NULL,
  "parentTenant" TEXT NOT NULL,
  "parentId" TEXT NOT NULL,
  CONSTRAINT "children_pk" PRIMARY KEY ("tenant", "id"),
  CONSTRAINT "children_parent_fk" FOREIGN KEY ("parentTenant", "parentId") REFERENCES "parents" ("tenant", "id") ON DELETE NO ACTION ON UPDATE NO ACTION
);
CREATE UNIQUE INDEX "content"."parents_name_unique" ON "parents" ("name" ASC) WHERE "favoriteChildId" IS NULL;
''',
      metadata: jsonDecode(r'''
{
  "checksum": "98c9b8e457e3fad63e491007db8cfc29505b50b2bfb3b368a106e91bd40adb80",
  "databaseId": "00000000000000000000000000000001",
  "dialect": "voxel",
  "formatVersion": 1,
  "id": "00000000000000000000000000000013",
  "parentId": null,
  "phases": [
    {
      "id": "0",
      "mode": "transactional",
      "platforms": [
        "native",
        "browser"
      ],
      "recovery": null,
      "scopeId": "00000000000000000000000000000002",
      "statements": [
        {
          "endByte": 396,
          "startByte": 0
        },
        {
          "endByte": 753,
          "startByte": 397
        },
        {
          "endByte": 864,
          "startByte": 754
        }
      ],
      "writeScopeIds": [
        "00000000000000000000000000000002"
      ]
    }
  ]
}
''') as Map<String, Object?>,
      snapshot: jsonDecode(r'''
{
  "databaseId": "00000000000000000000000000000001",
  "dialect": "voxel",
  "enums": [],
  "formatVersion": 1,
  "migrationId": "00000000000000000000000000000013",
  "requirements": [],
  "schemas": [
    {
      "id": "00000000000000000000000000000002",
      "name": "content"
    }
  ],
  "tables": [
    {
      "columns": [
        {
          "id": "00000000000000000000000000000004",
          "name": "tenant",
          "primaryKey": false,
          "storage": {
            "codecVersion": 1,
            "kind": "text",
            "nullable": false
          },
          "tableId": "00000000000000000000000000000003"
        },
        {
          "id": "00000000000000000000000000000005",
          "name": "id",
          "primaryKey": false,
          "storage": {
            "codecVersion": 1,
            "kind": "text",
            "nullable": false
          },
          "tableId": "00000000000000000000000000000003"
        },
        {
          "id": "00000000000000000000000000000006",
          "name": "name",
          "primaryKey": false,
          "storage": {
            "codecVersion": 1,
            "kind": "text",
            "nullable": false
          },
          "tableId": "00000000000000000000000000000003"
        },
        {
          "id": "00000000000000000000000000000007",
          "name": "favoriteChildTenant",
          "primaryKey": false,
          "storage": {
            "codecVersion": 1,
            "kind": "text",
            "nullable": true
          },
          "tableId": "00000000000000000000000000000003"
        },
        {
          "id": "00000000000000000000000000000008",
          "name": "favoriteChildId",
          "primaryKey": false,
          "storage": {
            "codecVersion": 1,
            "kind": "text",
            "nullable": true
          },
          "tableId": "00000000000000000000000000000003"
        }
      ],
      "constraints": [
        {
          "columnIds": [
            "00000000000000000000000000000004",
            "00000000000000000000000000000005"
          ],
          "id": "0000000000000000000000000000000f",
          "kind": "primaryKey",
          "name": "parents_pk",
          "tableId": "00000000000000000000000000000003"
        },
        {
          "columnIds": [
            "00000000000000000000000000000007",
            "00000000000000000000000000000008"
          ],
          "id": "00000000000000000000000000000010",
          "kind": "foreignKey",
          "name": "parents_favorite_child_fk",
          "onDelete": "noAction",
          "onUpdate": "noAction",
          "referenceColumnIds": [
            "0000000000000000000000000000000a",
            "0000000000000000000000000000000b"
          ],
          "referenceTableId": "00000000000000000000000000000009",
          "tableId": "00000000000000000000000000000003"
        }
      ],
      "id": "00000000000000000000000000000003",
      "indexes": [
        {
          "id": "0000000000000000000000000000000e",
          "name": "parents_name_unique",
          "options": {},
          "platforms": [
            "native",
            "browser"
          ],
          "predicate": {
            "arguments": [
              {
                "formatVersion": 1,
                "kind": "reference",
                "objectId": "00000000000000000000000000000008"
              }
            ],
            "formatVersion": 1,
            "kind": "operator",
            "operator": "IS NULL"
          },
          "tableId": "00000000000000000000000000000003",
          "terms": [
            {
              "columnId": "00000000000000000000000000000006",
              "descending": false
            }
          ],
          "unique": true
        }
      ],
      "name": "parents",
      "schemaId": "00000000000000000000000000000002"
    },
    {
      "columns": [
        {
          "id": "0000000000000000000000000000000a",
          "name": "tenant",
          "primaryKey": false,
          "storage": {
            "codecVersion": 1,
            "kind": "text",
            "nullable": false
          },
          "tableId": "00000000000000000000000000000009"
        },
        {
          "id": "0000000000000000000000000000000b",
          "name": "id",
          "primaryKey": false,
          "storage": {
            "codecVersion": 1,
            "kind": "text",
            "nullable": false
          },
          "tableId": "00000000000000000000000000000009"
        },
        {
          "id": "0000000000000000000000000000000c",
          "name": "parentTenant",
          "primaryKey": false,
          "storage": {
            "codecVersion": 1,
            "kind": "text",
            "nullable": false
          },
          "tableId": "00000000000000000000000000000009"
        },
        {
          "id": "0000000000000000000000000000000d",
          "name": "parentId",
          "primaryKey": false,
          "storage": {
            "codecVersion": 1,
            "kind": "text",
            "nullable": false
          },
          "tableId": "00000000000000000000000000000009"
        }
      ],
      "constraints": [
        {
          "columnIds": [
            "0000000000000000000000000000000a",
            "0000000000000000000000000000000b"
          ],
          "id": "00000000000000000000000000000011",
          "kind": "primaryKey",
          "name": "children_pk",
          "tableId": "00000000000000000000000000000009"
        },
        {
          "columnIds": [
            "0000000000000000000000000000000c",
            "0000000000000000000000000000000d"
          ],
          "id": "00000000000000000000000000000012",
          "kind": "foreignKey",
          "name": "children_parent_fk",
          "onDelete": "noAction",
          "onUpdate": "noAction",
          "referenceColumnIds": [
            "00000000000000000000000000000004",
            "00000000000000000000000000000005"
          ],
          "referenceTableId": "00000000000000000000000000000003",
          "tableId": "00000000000000000000000000000009"
        }
      ],
      "id": "00000000000000000000000000000009",
      "indexes": [],
      "name": "children",
      "schemaId": "00000000000000000000000000000002"
    }
  ]
}
''') as Map<String, Object?>,
    ),
    VoxelBundledMigration(
      directory: '0001_rebuild_parents_00000000000000000000000000000014',
      sql: r'''
CREATE TABLE "content"."__voxel_rebuild_000000000000" (
  "tenant" TEXT NOT NULL,
  "id" TEXT NOT NULL,
  "name" INTEGER NOT NULL,
  "favoriteChildTenant" TEXT,
  "favoriteChildId" TEXT,
  CONSTRAINT "parents_pk" PRIMARY KEY ("tenant", "id"),
  CONSTRAINT "parents_favorite_child_fk" FOREIGN KEY ("favoriteChildTenant", "favoriteChildId") REFERENCES "children" ("tenant", "id") ON DELETE NO ACTION ON UPDATE NO ACTION
);
INSERT INTO "content"."__voxel_rebuild_000000000000" ("tenant", "id", "name", "favoriteChildTenant", "favoriteChildId") SELECT "tenant", "id", CAST("name" AS INTEGER), "favoriteChildTenant", "favoriteChildId" FROM "content"."parents";
DROP TABLE "content"."parents";
ALTER TABLE "content"."__voxel_rebuild_000000000000" RENAME TO "parents";
CREATE UNIQUE INDEX "content"."parents_name_unique" ON "parents" ("name" ASC) WHERE "favoriteChildId" IS NULL;
''',
      metadata: jsonDecode(r'''
{
  "checksum": "e0f1f1d98aab38ccbfae68486f431f7820f777ad6665ab79dcbd7b3e5779f9ab",
  "databaseId": "00000000000000000000000000000001",
  "dialect": "voxel",
  "formatVersion": 1,
  "id": "00000000000000000000000000000014",
  "parentId": "00000000000000000000000000000013",
  "phases": [
    {
      "id": "0",
      "mode": "transactional",
      "platforms": [
        "native",
        "browser"
      ],
      "rebuild": {
        "foreignKeys": "offOutsideTransaction",
        "tables": [
          {
            "expectedBefore": {
              "columns": [
                {
                  "id": "00000000000000000000000000000004",
                  "name": "tenant",
                  "primaryKey": false,
                  "storage": {
                    "codecVersion": 1,
                    "kind": "text",
                    "nullable": false
                  },
                  "tableId": "00000000000000000000000000000003"
                },
                {
                  "id": "00000000000000000000000000000005",
                  "name": "id",
                  "primaryKey": false,
                  "storage": {
                    "codecVersion": 1,
                    "kind": "text",
                    "nullable": false
                  },
                  "tableId": "00000000000000000000000000000003"
                },
                {
                  "id": "00000000000000000000000000000006",
                  "name": "name",
                  "primaryKey": false,
                  "storage": {
                    "codecVersion": 1,
                    "kind": "text",
                    "nullable": false
                  },
                  "tableId": "00000000000000000000000000000003"
                },
                {
                  "id": "00000000000000000000000000000007",
                  "name": "favoriteChildTenant",
                  "primaryKey": false,
                  "storage": {
                    "codecVersion": 1,
                    "kind": "text",
                    "nullable": true
                  },
                  "tableId": "00000000000000000000000000000003"
                },
                {
                  "id": "00000000000000000000000000000008",
                  "name": "favoriteChildId",
                  "primaryKey": false,
                  "storage": {
                    "codecVersion": 1,
                    "kind": "text",
                    "nullable": true
                  },
                  "tableId": "00000000000000000000000000000003"
                }
              ],
              "constraints": [
                {
                  "columnIds": [
                    "00000000000000000000000000000004",
                    "00000000000000000000000000000005"
                  ],
                  "id": "0000000000000000000000000000000f",
                  "kind": "primaryKey",
                  "name": "parents_pk",
                  "tableId": "00000000000000000000000000000003"
                },
                {
                  "columnIds": [
                    "00000000000000000000000000000007",
                    "00000000000000000000000000000008"
                  ],
                  "id": "00000000000000000000000000000010",
                  "kind": "foreignKey",
                  "name": "parents_favorite_child_fk",
                  "onDelete": "noAction",
                  "onUpdate": "noAction",
                  "referenceColumnIds": [
                    "0000000000000000000000000000000a",
                    "0000000000000000000000000000000b"
                  ],
                  "referenceTableId": "00000000000000000000000000000009",
                  "tableId": "00000000000000000000000000000003"
                }
              ],
              "id": "00000000000000000000000000000003",
              "indexes": [
                {
                  "id": "0000000000000000000000000000000e",
                  "name": "parents_name_unique",
                  "options": {},
                  "platforms": [
                    "native",
                    "browser"
                  ],
                  "predicate": {
                    "arguments": [
                      {
                        "formatVersion": 1,
                        "kind": "reference",
                        "objectId": "00000000000000000000000000000008"
                      }
                    ],
                    "formatVersion": 1,
                    "kind": "operator",
                    "operator": "IS NULL"
                  },
                  "tableId": "00000000000000000000000000000003",
                  "terms": [
                    {
                      "columnId": "00000000000000000000000000000006",
                      "descending": false
                    }
                  ],
                  "unique": true
                }
              ],
              "name": "parents",
              "schemaId": "00000000000000000000000000000002"
            },
            "finalName": "parents",
            "managedDependencies": [
              {
                "kind": "index",
                "name": "parents_name_unique",
                "objectId": "0000000000000000000000000000000e"
              }
            ],
            "oldName": "parents",
            "replacementName": "__voxel_rebuild_000000000000",
            "tableId": "00000000000000000000000000000003"
          }
        ],
        "validations": [
          {
            "constraintId": "00000000000000000000000000000010",
            "kind": "foreignKeyAntiJoin",
            "sql": "SELECT NOT EXISTS (SELECT 1 FROM \"content\".\"parents\" AS \"voxel_child\" WHERE \"voxel_child\".\"favoriteChildTenant\" IS NOT NULL AND \"voxel_child\".\"favoriteChildId\" IS NOT NULL AND NOT EXISTS (SELECT 1 FROM \"content\".\"children\" AS \"voxel_parent\" WHERE \"voxel_parent\".\"tenant\" = \"voxel_child\".\"favoriteChildTenant\" AND \"voxel_parent\".\"id\" = \"voxel_child\".\"favoriteChildId\")) AS \"valid\";",
            "tableId": "00000000000000000000000000000003"
          },
          {
            "constraintId": "00000000000000000000000000000012",
            "kind": "foreignKeyAntiJoin",
            "sql": "SELECT NOT EXISTS (SELECT 1 FROM \"content\".\"children\" AS \"voxel_child\" WHERE \"voxel_child\".\"parentTenant\" IS NOT NULL AND \"voxel_child\".\"parentId\" IS NOT NULL AND NOT EXISTS (SELECT 1 FROM \"content\".\"parents\" AS \"voxel_parent\" WHERE \"voxel_parent\".\"tenant\" = \"voxel_child\".\"parentTenant\" AND \"voxel_parent\".\"id\" = \"voxel_child\".\"parentId\")) AS \"valid\";",
            "tableId": "00000000000000000000000000000009"
          }
        ]
      },
      "recovery": null,
      "scopeId": "00000000000000000000000000000002",
      "statements": [
        {
          "endByte": 420,
          "startByte": 0
        },
        {
          "endByte": 655,
          "startByte": 421
        },
        {
          "endByte": 687,
          "startByte": 656
        },
        {
          "endByte": 761,
          "startByte": 688
        },
        {
          "endByte": 872,
          "startByte": 762
        }
      ],
      "writeScopeIds": [
        "00000000000000000000000000000002"
      ]
    }
  ]
}
''') as Map<String, Object?>,
      snapshot: jsonDecode(r'''
{
  "databaseId": "00000000000000000000000000000001",
  "dialect": "voxel",
  "enums": [],
  "formatVersion": 1,
  "migrationId": "00000000000000000000000000000014",
  "requirements": [],
  "schemas": [
    {
      "id": "00000000000000000000000000000002",
      "name": "content"
    }
  ],
  "tables": [
    {
      "columns": [
        {
          "id": "00000000000000000000000000000004",
          "name": "tenant",
          "primaryKey": false,
          "storage": {
            "codecVersion": 1,
            "kind": "text",
            "nullable": false
          },
          "tableId": "00000000000000000000000000000003"
        },
        {
          "id": "00000000000000000000000000000005",
          "name": "id",
          "primaryKey": false,
          "storage": {
            "codecVersion": 1,
            "kind": "text",
            "nullable": false
          },
          "tableId": "00000000000000000000000000000003"
        },
        {
          "id": "00000000000000000000000000000006",
          "name": "name",
          "primaryKey": false,
          "storage": {
            "codecVersion": 1,
            "kind": "integer",
            "nullable": false
          },
          "tableId": "00000000000000000000000000000003"
        },
        {
          "id": "00000000000000000000000000000007",
          "name": "favoriteChildTenant",
          "primaryKey": false,
          "storage": {
            "codecVersion": 1,
            "kind": "text",
            "nullable": true
          },
          "tableId": "00000000000000000000000000000003"
        },
        {
          "id": "00000000000000000000000000000008",
          "name": "favoriteChildId",
          "primaryKey": false,
          "storage": {
            "codecVersion": 1,
            "kind": "text",
            "nullable": true
          },
          "tableId": "00000000000000000000000000000003"
        }
      ],
      "constraints": [
        {
          "columnIds": [
            "00000000000000000000000000000004",
            "00000000000000000000000000000005"
          ],
          "id": "0000000000000000000000000000000f",
          "kind": "primaryKey",
          "name": "parents_pk",
          "tableId": "00000000000000000000000000000003"
        },
        {
          "columnIds": [
            "00000000000000000000000000000007",
            "00000000000000000000000000000008"
          ],
          "id": "00000000000000000000000000000010",
          "kind": "foreignKey",
          "name": "parents_favorite_child_fk",
          "onDelete": "noAction",
          "onUpdate": "noAction",
          "referenceColumnIds": [
            "0000000000000000000000000000000a",
            "0000000000000000000000000000000b"
          ],
          "referenceTableId": "00000000000000000000000000000009",
          "tableId": "00000000000000000000000000000003"
        }
      ],
      "id": "00000000000000000000000000000003",
      "indexes": [
        {
          "id": "0000000000000000000000000000000e",
          "name": "parents_name_unique",
          "options": {},
          "platforms": [
            "native",
            "browser"
          ],
          "predicate": {
            "arguments": [
              {
                "formatVersion": 1,
                "kind": "reference",
                "objectId": "00000000000000000000000000000008"
              }
            ],
            "formatVersion": 1,
            "kind": "operator",
            "operator": "IS NULL"
          },
          "tableId": "00000000000000000000000000000003",
          "terms": [
            {
              "columnId": "00000000000000000000000000000006",
              "descending": false
            }
          ],
          "unique": true
        }
      ],
      "name": "parents",
      "schemaId": "00000000000000000000000000000002"
    },
    {
      "columns": [
        {
          "id": "0000000000000000000000000000000a",
          "name": "tenant",
          "primaryKey": false,
          "storage": {
            "codecVersion": 1,
            "kind": "text",
            "nullable": false
          },
          "tableId": "00000000000000000000000000000009"
        },
        {
          "id": "0000000000000000000000000000000b",
          "name": "id",
          "primaryKey": false,
          "storage": {
            "codecVersion": 1,
            "kind": "text",
            "nullable": false
          },
          "tableId": "00000000000000000000000000000009"
        },
        {
          "id": "0000000000000000000000000000000c",
          "name": "parentTenant",
          "primaryKey": false,
          "storage": {
            "codecVersion": 1,
            "kind": "text",
            "nullable": false
          },
          "tableId": "00000000000000000000000000000009"
        },
        {
          "id": "0000000000000000000000000000000d",
          "name": "parentId",
          "primaryKey": false,
          "storage": {
            "codecVersion": 1,
            "kind": "text",
            "nullable": false
          },
          "tableId": "00000000000000000000000000000009"
        }
      ],
      "constraints": [
        {
          "columnIds": [
            "0000000000000000000000000000000a",
            "0000000000000000000000000000000b"
          ],
          "id": "00000000000000000000000000000011",
          "kind": "primaryKey",
          "name": "children_pk",
          "tableId": "00000000000000000000000000000009"
        },
        {
          "columnIds": [
            "0000000000000000000000000000000c",
            "0000000000000000000000000000000d"
          ],
          "id": "00000000000000000000000000000012",
          "kind": "foreignKey",
          "name": "children_parent_fk",
          "onDelete": "noAction",
          "onUpdate": "noAction",
          "referenceColumnIds": [
            "00000000000000000000000000000004",
            "00000000000000000000000000000005"
          ],
          "referenceTableId": "00000000000000000000000000000003",
          "tableId": "00000000000000000000000000000009"
        }
      ],
      "id": "00000000000000000000000000000009",
      "indexes": [],
      "name": "children",
      "schemaId": "00000000000000000000000000000002"
    }
  ]
}
''') as Map<String, Object?>,
    ),
  ],
);
