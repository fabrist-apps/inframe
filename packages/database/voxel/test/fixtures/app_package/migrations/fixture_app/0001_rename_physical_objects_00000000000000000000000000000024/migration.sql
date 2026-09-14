ALTER TABLE "content"."articles" RENAME TO "posts";
ALTER TABLE "content"."posts" RENAME COLUMN "writerID" TO "authorID";
