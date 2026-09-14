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

Removing a native enum label requires an explicit JSON transform file. Keys
identify the resulting schema, enum, and removed label; values name a retained
replacement label:

```json
{"public.order_status.cancelled": "archived"}
```

Pass it with `--transforms enum-transforms.json`. The reviewed migration updates
every dependent scalar and array column before rebuilding the native type.

The command writes `migration.sql`, `snapshot.json`, and `migration.json` in a
new migration directory, then atomically replaces root `journal.json`. The
journal records its generated source locator so the ordinary check command can
also compare the final snapshot with the current generated schema:

```sh
dart run rivet_generator:rivet check --dir migrations
```

`check` validates only the supplied files and current generated metadata. It
does not know whether a migration has started or been applied, and it does not
claim that reviewed custom SQL produces the declared snapshot.

After reviewing an unapplied migration's SQL, reseal its statement ranges and
integrity metadata:

```sh
dart run rivet_generator:rivet seal --dir migrations --migration <id>
```

The sealer parses PostgreSQL comments, quoted strings and identifiers,
dollar-quoted bodies, and UTF-8 byte offsets. It preserves the existing phase
statement counts so an edit cannot silently change phase assignment. Reviewed
nontransactional SQL must carry either manual recovery metadata or checked
catalog recovery metadata; `CREATE INDEX CONCURRENTLY` requires the versioned
PostgreSQL index inspector description, including qualified identity,
definition, uniqueness, validity, and readiness.

Started or applied migrations are immutable and require a new corrective
migration. Offline sealing cannot inspect deployment receipts or prove that
arbitrary reviewed SQL produces the declared snapshot. It only validates and
reseals the supplied artifacts.

Deployment commands read a PostgreSQL URL from the named environment variable.
They validate the checked artifacts before connecting and hold Rivet's
database-wide session lock while inspecting or changing migration history:

```sh
export APP_DATABASE_URL='postgresql://...'
dart run rivet_generator:rivet migrate \
  --dir migrations --connection-env APP_DATABASE_URL
dart run rivet_generator:rivet status \
  --dir migrations --connection-env APP_DATABASE_URL
```

`status` emits one JSON object containing each journaled phase, its state, and
any durable attempt evidence. It does not bootstrap or modify migration state.
Use `--lock-timeout 0` for one lock attempt; the default is 30 seconds.

An interrupted manual or checked nontransactional phase remains stopped until
its recovery evidence proves a safe outcome. Resolve the exact active attempt
with an audited reason:

```sh
dart run rivet_generator:rivet resolve \
  --dir migrations --connection-env APP_DATABASE_URL \
  --migration <id> --phase <id> --checksum <sha256> --attempt <id> \
  --reason 'verified against deployment record 42' \
  --resolution completed
```

`--resolution retry` creates a new attempt only when the current evidence says
the operation has not started, or after an operator explicitly authorizes a
manual retry. These commands require a direct dedicated PostgreSQL session;
transaction-pooling proxies are unsupported unless they preserve that session.
Put TLS and connection settings in the PostgreSQL URL, including `sslmode` when
the deployment differs from Rivet's verified-TLS default. A custom
`SecurityContext` is available through the programmatic `RivetMigrator` API;
the CLI does not load certificate files. Errors redact the selected connection
URL and its credentials.

Format version 1 is described by the checked-in JSON Schemas in `schemas/`.
Migration checksums cover the exact decoded UTF-8 SQL plus canonicalized
snapshot and migration metadata. JSON whitespace and key order therefore do
not change a checksum, while SQL whitespace and comments do.
