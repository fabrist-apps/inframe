# Rivet

Rivet generates typed Dart reads for existing PostgreSQL schemas. Opening a database creates an owned connection pool; it never creates application tables or applies migrations.

```dart
final class Email {
  const Email(this.value);

  final String value;
}

final class EmailConverter implements RivetTypeConverter<Email, String> {
  const EmailConverter();

  @override
  Email fromSql(String value) => Email(value);

  @override
  String toSql(Email value) => value.value;
}

@RivetTable(schema: 'auth', name: 'users')
final class Users extends RivetTableDefinition<Users> {
  static const db = _$UsersDB();

  late final name = text()();
  late final email = text().map(const EmailConverter())();
  late final age = integer()();
}

@RivetDatabase(name: 'app', tables: [Users])
final class AppDatabase extends _$AppDatabase {}

final db = await AppDatabase().open(
  connection: RivetConnection.url(databaseUrl),
  pool: const RivetPoolOptions(maxConnections: 10),
);
final users = await Users.db.find(where: (users) => users.name.equals('Ada')).get(db);
await db.close();
```

Consumers add `rivet_generator` and `build_runner` as development dependencies, add a `part '<library>.rivet.dart';` directive, then run `dart run build_runner build`.

Migration execution is explicit and separate from application open. A
deployment process can apply a checked artifact directory through one owned
PostgreSQL session:

```dart
await RivetMigrator(
  connection: RivetConnection.url(databaseUrl),
  directory: Directory('migrations'),
).migrate();
```

The migrator holds a database-wide advisory lock across history validation,
transactional phase commits, and nontransactional recovery. `status()` reads
the same checked history without bootstrapping it. `resolve(...)` records an
audited decision for the exact checksum and active interrupted attempt.

`RivetConnection.url` defaults to certificate and hostname verification. Use a Dart `SecurityContext` for a private CA. Choose `RivetSslMode.require` only when TLS without certificate verification is intentional, or `RivetSslMode.disable` for an explicitly unencrypted disposable fixture.

Query plans do not retain a database connection. Supply either the root database or a transaction at the terminal:

```dart
await db.transaction((tx) async {
  final user = await Users.db.find().getSingle(tx);
  tx.afterCommit(() => publishUserRead(user));
});
```

Transactions reserve one pooled connection. Their executors expire when the transaction callback ends. After-commit callbacks run sequentially after commit and after the reservation is returned; callback failures are reported as `AfterCommitException` with `alreadyCommitted == true`.

Generated companions keep insert values typed and defer runtime defaults until execution:

```dart
final insert = Users.db.insert(
  UsersCompanion.insert(
    name: const RivetValue.present('Ada'),
    email: const RivetValue.present(Email('ada@example.com')),
    age: const RivetValue.present(30),
  ),
);
final affected = await insert.execute(db);
final rows = await insert.returning().get(db);
```

Non-nullable fields without a SQL or runtime default are required named arguments. Nullable and defaulted fields begin as `RivetValue.absent()`. At execution, an omitted insert field uses `defaultValue`, then `onUpdate`, then the PostgreSQL `DEFAULT`, and finally SQL NULL when the column is nullable. Explicit values, nulls, and typed SQL expressions suppress those fallbacks. Each terminal executes one statement; `returning()` decodes complete rows without another SELECT.

For mapped columns, `present` takes the domain type. Expression assignments take the storage type through the column's `storage` view, so the expression bypasses the Dart converter and the returned row still decodes through it:

```dart
UsersCompanion.insert(
  name: const RivetValue.present('Ada'),
  email: RivetValue.expression(
    (users) => users.email.storage.value('ada@example.com'),
  ),
  age: const RivetValue.present(30),
);
```

Update companions make every field optional. Absent fields run `onUpdate` when configured and otherwise remain untouched. Supply a root-table predicate to restrict the statement, or omit `where` to update every row:

```dart
final changed = await Users.db
    .update(
      UsersCompanion.update(
        age: RivetValue.expression((users) => users.age + 1),
      ),
      where: (users) => users.name.equals('Ada'),
    )
    .execute(db);
```

Deletes use the same optional root predicate and terminal shape. Omitting `where` deletes every row in the target table; PostgreSQL performs declared foreign-key cascades inside that statement.

`insertMany` submits every supplied companion in one statement and evaluates omitted runtime defaults independently for each row. Empty batches return zero or an empty returned-row list without executing SQL. Callers can submit their own chunks as separate mutations inside an explicit transaction.

Both insert builders accept typed conflict handling. `conflict.doNothing()` handles any eligible uniqueness conflict; select target columns to restrict it and add `targetWhere` when PostgreSQL must infer a partial unique index:

```dart
onConflict: (conflict) => conflict.doNothing(
  target: (users) => [users.name],
  targetWhere: (users) => ~users.name.equals(''),
),
```

Use `conflict.update` with an explicit target to upsert. The `set` callback receives typed SQL scopes for the existing row and PostgreSQL's excluded row. `targetWhere` selects a partial unique index; `where` decides whether the conflicting row is updated:

```dart
onConflict: (conflict) => conflict.update(
  target: (user) => [user.name],
  targetWhere: (user) => ~user.name.equals(''),
  set: (old, excluded) => UsersCompanion.update(
    age: RivetValue.expression((_) => excluded.age),
  ),
  where: (old, excluded) => old.age.lessThanExpression(excluded.age),
),
```

Absent fields in the conflict update run their `onUpdate` callbacks once when the statement is prepared for execution. Empty batches run no conflict, default, or update callbacks.

The column catalog is `chronoID`, `text`, `integer`, `real`, `boolean`, `dateTime`, `json`, `enumText`, and fixed-dimension `vector`. Add `.map(converter)` for domain values and `.array()` for one-dimensional native PostgreSQL arrays. Nullability before `.array()` applies to elements; nullability after it applies to the array column.

The integration matrix pins `postgres` 3.5.12 and the Inframe image at `sha256:a29d81973c699fdf070b10f77bf5b91b1d94a59fcd7792f67410ba655761f871`: PostgreSQL 18.6, pgvector 0.8.6, pgvectorscale 0.9.1, and pg_textsearch 1.4.0.
