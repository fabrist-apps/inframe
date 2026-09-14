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
