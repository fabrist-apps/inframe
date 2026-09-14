# Voxel generator

`voxel_generator` creates, checks, seals, and bundles reviewable Turso migrations
from generated Voxel application schemas. The tooling uses checked files and
does not open an application database.

Run build_runner once after changing declarations, then generate the first or
next migration. Put each database history under `migrations/<database-name>` so
the bundle builder can derive `lib/<database-name>.voxel_migrations.dart`.

```sh
dart run build_runner build
dart run voxel_generator:voxel generate \
  --database package:my_app/database.dart#AppDatabase \
  --out migrations/app \
  --name create_accounts
```

Table rebuilds require explicit SQL expressions for incompatible storage
changes, required columns without SQL defaults, and destructive enum label
changes. The JSON keys are resulting `schema.table.column` paths.

```json
{
  "main.accounts.status": "CASE \"status\" WHEN 'old' THEN 'active' ELSE \"status\" END"
}
```

Pass the file with `--transforms storage-transforms.json`. Runtime defaults,
update callbacks, and converters are not migration backfills.

Review the generated SQL, seal reviewed edits, and check the complete history:

```sh
dart run voxel_generator:voxel seal \
  --dir migrations/app \
  --migration <id>
dart run voxel_generator:voxel check --dir migrations/app
dart run build_runner build
```

The final build validates every journaled artifact and compares the final
snapshot with the current generated schema before emitting the Dart bundle.
The bundle preserves exact SQL bytes, journal order, identities, parent links,
checksums, snapshots, platforms, phases, rebuild validation, and recovery
metadata. It is derived output; edit and reseal the source artifacts instead.

`check` and `seal` do not know whether deployment has started and do not prove
that arbitrary reviewed SQL produces its claimed snapshot. Started or applied
migrations are immutable and need a new corrective migration. Execution,
locking, receipts, status, and recovery belong to Voxel's migration lifecycle.

Format version 1 is described by the checked-in JSON Schemas in `schemas/`.
Checksums cover exact decoded UTF-8 SQL and canonicalized snapshot and migration
metadata. JSON formatting does not change a checksum; SQL comments and
whitespace do.
