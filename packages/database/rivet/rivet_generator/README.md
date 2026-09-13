# Rivet generator

`rivet_generator` creates and checks reviewable PostgreSQL migrations from a
generated Rivet application schema. It never opens a database.

Generate the first or next migration from an annotated database:

```sh
dart run rivet_generator:rivet generate \
  --database package:my_app/database.dart#AppDatabase \
  --out migrations \
  --name create_accounts
```

The command writes `migration.sql`, `snapshot.json`, and `migration.json` in a
new migration directory, then atomically replaces root `journal.json`. The
journal records its generated source locator so the ordinary check command can
also compare the final snapshot with the current generated schema:

```sh
dart run rivet_generator:rivet check --dir migrations
```

`check` validates only the supplied files and current generated metadata. It
does not know whether a migration has started or been applied, and it does not
claim that reviewed custom SQL produces the declared snapshot. Deployment
history, locks, receipts, recovery, status, and resolution belong to Rivet's
separate migration runner.

Format version 1 is described by the checked-in JSON Schemas in `schemas/`.
Migration checksums cover the exact decoded UTF-8 SQL plus canonicalized
snapshot and migration metadata. JSON whitespace and key order therefore do
not change a checksum, while SQL whitespace and comments do.
