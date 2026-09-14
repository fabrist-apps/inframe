CREATE TABLE "content"."authors" (
  "id" TEXT NOT NULL,
  "name" TEXT NOT NULL,
  CONSTRAINT "authors_name_present" CHECK (("name" > '')),
  CONSTRAINT "authors_pkey" PRIMARY KEY ("id")
);
CREATE TABLE "content"."articles" (
  "id" TEXT NOT NULL,
  "writerID" TEXT NOT NULL,
  "status" TEXT NOT NULL,
  CHECK ("status" IN ('draft', 'published')),
  CONSTRAINT "posts_authorID_fkey" FOREIGN KEY ("writerID") REFERENCES "authors" ("id") ON DELETE NO ACTION ON UPDATE NO ACTION,
  CONSTRAINT "articles_pkey" PRIMARY KEY ("id")
);
CREATE TABLE "content"."tags" (
  "id" TEXT NOT NULL,
  CONSTRAINT "tags_pkey" PRIMARY KEY ("id")
);
CREATE TABLE "content"."postTags" (
  "postID" TEXT NOT NULL,
  "tagID" TEXT NOT NULL,
  CONSTRAINT "postTags_postID_fkey" FOREIGN KEY ("postID") REFERENCES "articles" ("id") ON DELETE NO ACTION ON UPDATE NO ACTION,
  CONSTRAINT "postTags_tagID_fkey" FOREIGN KEY ("tagID") REFERENCES "tags" ("id") ON DELETE NO ACTION ON UPDATE NO ACTION
);
CREATE TABLE "content"."locales" (
  "language" TEXT NOT NULL,
  "key" TEXT NOT NULL,
  CONSTRAINT "locales_pk" PRIMARY KEY ("language", "key")
);
CREATE TABLE "content"."translations" (
  "language" TEXT NOT NULL,
  "key" TEXT NOT NULL,
  "value" TEXT NOT NULL,
  CONSTRAINT "translations_locale_fk" FOREIGN KEY ("language", "key") REFERENCES "locales" ("language", "key") ON DELETE CASCADE ON UPDATE NO ACTION
);
CREATE UNIQUE INDEX "content"."authors_name" ON "authors" ("name" ASC) WHERE NOT (("name" = ''));
