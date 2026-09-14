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
