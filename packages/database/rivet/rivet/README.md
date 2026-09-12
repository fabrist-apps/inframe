# Rivet

Rivet generates typed Dart reads for existing PostgreSQL schemas. Opening a database creates an owned connection pool; it never creates application tables or applies migrations.

```dart
@RivetTable(schema: 'auth', name: 'users')
final class Users extends RivetTableDefinition<Users> {
  static const db = _$UsersDB();

  late final name = text()();
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

`RivetConnection.url` defaults to certificate and hostname verification and a 30-second query timeout. Use a Dart `SecurityContext` for a private CA. Choose `RivetSslMode.require` only when TLS without certificate verification is intentional, or `RivetSslMode.disable` for an explicitly unencrypted disposable fixture. Set `queryTimeout` when an operation needs a different upper bound.

Query plans do not retain a database connection. Supply either the root database or a transaction at the terminal:

```dart
await db.transaction((tx) async {
  final user = await Users.db.find().getSingle(tx);
  tx.afterCommit(() => publishUserRead(user));
});
```

Transactions reserve one pooled connection. Their executors expire when the transaction callback ends. After-commit callbacks run sequentially after commit and after the reservation is returned; callback failures are reported as `AfterCommitException` with `alreadyCommitted == true`.

The column catalog is `chronoID`, `text`, `integer`, `real`, `boolean`, `dateTime`, `json`, `enumText`, and fixed-dimension `vector`. Add `.map(converter)` for domain values and `.array()` for one-dimensional native PostgreSQL arrays. Nullability before `.array()` applies to elements; nullability after it applies to the array column.

The integration matrix pins `postgres` 3.5.12 and the Inframe image at `sha256:a29d81973c699fdf070b10f77bf5b91b1d94a59fcd7792f67410ba655761f871`: PostgreSQL 18.6, pgvector 0.8.6, pgvectorscale 0.9.1, and pg_textsearch 1.4.0.
