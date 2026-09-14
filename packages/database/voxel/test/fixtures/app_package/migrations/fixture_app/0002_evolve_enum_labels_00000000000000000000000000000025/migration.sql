-- reviewed bundle fixture
CREATE TABLE "content"."__voxel_rebuild_000000000000" (
  "id" TEXT NOT NULL,
  "authorID" TEXT NOT NULL,
  "status" TEXT NOT NULL,
  CHECK ("status" IN ('draft', 'live')),
  CONSTRAINT "posts_authorID_fkey" FOREIGN KEY ("authorID") REFERENCES "authors" ("id") ON DELETE NO ACTION ON UPDATE NO ACTION,
  CONSTRAINT "posts_pkey" PRIMARY KEY ("id")
);
INSERT INTO "content"."__voxel_rebuild_000000000000" ("id", "authorID", "status") SELECT "id", "authorID", CASE "status" WHEN 'published' THEN 'live' ELSE "status" END FROM "content"."posts";
DROP TABLE "content"."posts";
ALTER TABLE "content"."__voxel_rebuild_000000000000" RENAME TO "posts";
