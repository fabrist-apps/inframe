import 'dart:async';
import 'dart:typed_data';

import 'package:turso/turso.dart';

import 'package:voxel/src/errors.dart';
import 'package:voxel/src/migration.dart';
import 'package:voxel/src/platform.dart';
import 'package:voxel/src/schema.dart';

/// A validated SQL statement prepared by a generated Voxel operation.
///
/// Application code ordinarily receives statements through generated query and
/// mutation builders. The executor boundary keeps those plans independent from
/// whether they run on a database or its active transaction.
final class VoxelCompiledQuery {
  /// Creates a statement with positional [parameters].
  VoxelCompiledQuery(this.sql, List<Object?> parameters)
    : parameters = List.unmodifiable(parameters);

  /// SQL sent to the embedded database.
  final String sql;

  /// Positional values bound to [sql].
  final List<Object?> parameters;
}

/// Execution boundary accepted by generated query and mutation terminals.
abstract interface class VoxelExecutor {
  /// Executes [statement] and decodes every result row.
  Future<List<Row>> execute<Row>(
    VoxelCompiledQuery statement,
    VoxelRowDecoder<Row> decode,
  );

  /// Executes [statement] and returns the number of changed rows.
  Future<int> executeAffected(VoxelCompiledQuery statement);
}

/// Selects how a generated Voxel database stores its files.
sealed class VoxelStorage {
  const VoxelStorage();

  /// Opens an isolated database that is discarded when it closes.
  const factory VoxelStorage.memory() = VoxelMemoryStorage;

  /// Selects a native directory. Persistent opening is implemented separately.
  const factory VoxelStorage.directory(String path) = VoxelDirectoryStorage;

  /// Selects an origin-private browser directory.
  const factory VoxelStorage.opfs({required String directory}) = VoxelOpfsStorage;
}

/// An isolated in-memory database selection.
final class VoxelMemoryStorage extends VoxelStorage {
  /// Creates isolated in-memory storage.
  const VoxelMemoryStorage();
}

/// A caller-owned native storage directory selection.
final class VoxelDirectoryStorage extends VoxelStorage {
  /// Creates a native directory selection.
  const VoxelDirectoryStorage(this.path);

  /// The caller-owned parent directory.
  final String path;
}

/// An origin-private browser storage directory selection.
final class VoxelOpfsStorage extends VoxelStorage {
  /// Creates a browser OPFS directory selection.
  const VoxelOpfsStorage({required this.directory});

  /// The directory beneath the application's origin-private storage root.
  final String directory;
}

/// Supported database page-encryption algorithms.
enum VoxelCipher {
  /// AEGIS-256 with a 32-byte key.
  aegis256,

  /// AES-256-GCM with a 32-byte key.
  aes256gcm,
}

/// Application-owned database encryption material.
final class VoxelEncryption {
  /// Creates encryption settings from application-owned key material.
  VoxelEncryption({required this.cipher, required Uint8List key}) : _key = Uint8List.fromList(key) {
    if (key.length != 32) {
      throw ArgumentError.value(key.length, 'key', 'must contain exactly 32 bytes');
    }
  }

  /// The requested page-encryption algorithm.
  final VoxelCipher cipher;
  final Uint8List _key;

  /// Returns a defensive copy of the key.
  Uint8List get key => Uint8List.fromList(_key);
}

/// Migration execution options shared by generated open entry points.
final class VoxelMigrationOptions {
  /// Creates migration coordination options.
  const VoxelMigrationOptions({this.lockTimeout = const Duration(seconds: 30)});

  /// Total time allowed for acquiring migration ownership.
  final Duration lockTimeout;
}

/// Configures the application-support directory used by native default opens.
///
/// Flutter applications should register a resolver during startup. Plain Dart
/// callers can instead pass [VoxelStorage.directory] to each open call.
abstract final class VoxelNativeStorageDefaults {
  /// Registers the asynchronous application-support directory resolver.
  static void register(Future<String> Function() resolver) {
    registerVoxelNativeDefaultStorage(resolver);
  }
}

/// An initialized Voxel database and the Turso connection it owns.
///
/// Obtain this through the generated `VoxelApp().open(...)` extension. The
/// returned handle has all memory schemas attached, bundled migrations applied,
/// and foreign-key enforcement enabled. Call [close] when the application no
/// longer needs it.
final class VoxelDb implements VoxelExecutor {
  VoxelDb._(this._database, this.name, this.tables);

  final TursoDatabase _database;
  bool _closing = false;
  int _acceptedWork = 0;
  Completer<void>? _drained;
  Future<void>? _closeFuture;

  /// The database name declared by `@VoxelDatabase`.
  final String name;

  /// Connection-free schemas registered by the generated application database.
  final List<VoxelTableSchema<Object?, Object?>> tables;

  @override
  Future<List<Row>> execute<Row>(
    VoxelCompiledQuery statement,
    VoxelRowDecoder<Row> decode,
  ) async {
    _rejectUseInsideOwnTransaction();
    _acceptWork();
    try {
      return await _executeQuery(
        (sql, parameters) => _database.query(sql, parameters: parameters),
        statement,
        decode,
      );
    } finally {
      _finishWork();
    }
  }

  @override
  Future<int> executeAffected(VoxelCompiledQuery statement) async {
    _rejectUseInsideOwnTransaction();
    _acceptWork();
    try {
      return await _executeAffected(
        (sql, parameters) => _database.execute(sql, parameters: parameters),
        statement,
      );
    } finally {
      _finishWork();
    }
  }

  /// Runs [callback] in one transaction on this database's connection.
  ///
  /// Use only the supplied executor during [callback]. It expires when the
  /// callback finishes. A callback failure rolls back and preserves its error;
  /// callbacks registered with [VoxelTransaction.afterCommit] run only after a
  /// successful commit and after the connection reservation is released.
  Future<T> transaction<T>(
    Future<T> Function(VoxelTransaction transaction) callback,
  ) async {
    _rejectUseInsideOwnTransaction();
    _acceptWork();
    Object? callbackFailure;
    late VoxelTransaction transaction;
    try {
      final result = await _database.transaction((driverTransaction) async {
        transaction = VoxelTransaction._(driverTransaction);
        try {
          return await runZoned(
            () async {
              try {
                return await callback(transaction);
              } catch (error) {
                callbackFailure = error;
                rethrow;
              }
            },
            zoneValues: {_transactionDatabaseZoneKey: this},
          );
        } finally {
          transaction._expire();
        }
      });
      await _runAfterCommitCallbacks(this, transaction._callbacks);
      return result;
    } on VoxelException {
      rethrow;
    } on Object catch (error) {
      if (identical(error, callbackFailure)) rethrow;
      throw VoxelDatabaseException('Turso transaction failed.', error);
    } finally {
      _finishWork();
    }
  }

  /// Runs process-local work immediately when no transaction is associated.
  ///
  /// Inside this database's transaction callback, register through
  /// [VoxelTransaction.afterCommit]. The callback is not persisted or replayed
  /// after a crash.
  Future<void> afterCommit(FutureOr<void> Function() callback) async {
    if (Zone.current[_transactionDatabaseZoneKey] == this) {
      throw const VoxelExecutorClosedException(
        'Use transaction.afterCommit inside this database transaction.',
      );
    }
    _acceptWork();
    try {
      await runZoned(
        () => Future<void>.sync(callback),
        zoneValues: {_afterCommitDatabaseZoneKey: this},
      );
    } finally {
      _finishWork();
    }
  }

  void _rejectUseInsideOwnTransaction() {
    if (Zone.current[_transactionDatabaseZoneKey] == this) {
      throw const VoxelExecutorClosedException(
        'Use the transaction executor inside this database transaction.',
      );
    }
  }

  void _acceptWork() {
    if (_closing) {
      throw const VoxelExecutorClosedException(
        'The database is closing or closed.',
      );
    }
    _acceptedWork++;
  }

  void _finishWork() {
    _acceptedWork--;
    if (_closing && _acceptedWork == 0) _drained?.complete();
  }

  /// Drains accepted SQL, transactions, and callbacks, then closes the owned
  /// connection. New work is rejected once shutdown begins.
  Future<void> close() {
    if (Zone.current[_transactionDatabaseZoneKey] == this ||
        Zone.current[_afterCommitDatabaseZoneKey] == this) {
      throw const VoxelExecutorClosedException(
        'Cannot close a database from its own transaction or after-commit callback.',
      );
    }
    return _closeFuture ??= _drainAndClose();
  }

  Future<void> _drainAndClose() async {
    _closing = true;
    if (_acceptedWork > 0) {
      _drained = Completer<void>();
      await _drained!.future;
    }
    await _database.close();
  }
}

/// A database-bound executor valid only during its transaction callback.
///
/// Register process-local post-commit work synchronously with [afterCommit].
/// The callbacks run in order after commit and are discarded on rollback.
final class VoxelTransaction implements VoxelExecutor {
  VoxelTransaction._(this._transaction);

  final TursoTransaction _transaction;
  bool _active = true;
  final List<FutureOr<void> Function()> _callbacks = [];

  /// Registers [callback] to run after this transaction commits.
  void afterCommit(FutureOr<void> Function() callback) {
    _ensureActive();
    _callbacks.add(callback);
  }

  @override
  Future<List<Row>> execute<Row>(
    VoxelCompiledQuery statement,
    VoxelRowDecoder<Row> decode,
  ) async {
    _ensureActive();
    return _executeQuery(
      (sql, parameters) => _transaction.query(sql, parameters: parameters),
      statement,
      decode,
    );
  }

  @override
  Future<int> executeAffected(VoxelCompiledQuery statement) async {
    _ensureActive();
    return _executeAffected(
      (sql, parameters) => _transaction.execute(sql, parameters: parameters),
      statement,
    );
  }

  void _ensureActive() {
    if (!_active) {
      throw const VoxelExecutorClosedException(
        'The transaction executor has expired.',
      );
    }
  }

  void _expire() => _active = false;
}

final _transactionDatabaseZoneKey = Object();
final _afterCommitDatabaseZoneKey = Object();

Future<void> _runAfterCommitCallbacks(
  VoxelDb database,
  List<FutureOr<void> Function()> callbacks,
) async {
  final failures = <AfterCommitFailure>[];
  for (final callback in callbacks) {
    try {
      await runZoned(
        () => Future<void>.sync(callback),
        zoneValues: {_afterCommitDatabaseZoneKey: database},
      );
    } on Object catch (error, stackTrace) {
      failures.add(AfterCommitFailure(error, stackTrace));
    }
  }
  if (failures.isNotEmpty) {
    throw AfterCommitException(
      List.unmodifiable(failures),
      alreadyCommitted: true,
    );
  }
}

Future<List<Row>> _executeQuery<Row>(
  Future<TursoQueryResult> Function(String sql, List<Object?> parameters) query,
  VoxelCompiledQuery statement,
  VoxelRowDecoder<Row> decode,
) async {
  try {
    final result = await query(statement.sql, statement.parameters);
    return [
      for (final row in result.rows)
        decode(
          [
            for (var index = 0; index < result.columns.length; index++) row.valueAt(index),
          ],
          [
            for (var index = 0; index < result.columns.length; index++) row.valueAt(index) == null,
          ],
        ),
    ];
  } on VoxelException {
    rethrow;
  } on Object catch (error) {
    throw VoxelDatabaseException('Turso query failed.', error);
  }
}

Future<int> _executeAffected(
  Future<TursoExecuteResult> Function(String sql, List<Object?> parameters) execute,
  VoxelCompiledQuery statement,
) async {
  try {
    final result = await execute(statement.sql, statement.parameters);
    return result.rowsAffected.toInt();
  } on VoxelException {
    rethrow;
  } on Object catch (error) {
    throw VoxelDatabaseException('Turso mutation failed.', error);
  }
}

/// Runtime entry point used only by generated database extensions.
abstract final class VoxelDatabaseRuntime {
  /// Validates and opens the generated [schema] with its checked [bundle].
  static Future<VoxelDb> open({
    required VoxelDatabaseSchema schema,
    required VoxelMigrationBundle bundle,
    VoxelStorage? storage,
    Map<String, VoxelStorage> schemaStorage = const {},
    VoxelEncryption? encryption,
    Map<String, VoxelEncryption?> schemaEncryption = const {},
    VoxelMigrationOptions migrations = const VoxelMigrationOptions(),
  }) async {
    if (migrations.lockTimeout.isNegative) {
      throw ArgumentError.value(
        migrations.lockTimeout,
        'migrations.lockTimeout',
        'must not be negative',
      );
    }
    final checked = VoxelMigrationPlan.validate(schema: schema, bundle: bundle);
    final namedSchemas = <String>{...checked.schemaNames.where((name) => name != 'main')};
    final unknownStorage = schemaStorage.keys.where((name) => !namedSchemas.contains(name));
    final unknownEncryption = schemaEncryption.keys.where((name) => !namedSchemas.contains(name));
    if (unknownStorage.isNotEmpty || unknownEncryption.isNotEmpty) {
      final unknownSchemas = <String>{...unknownStorage, ...unknownEncryption};
      throw ArgumentError(
        'Unknown Voxel schema configuration: '
        '${unknownSchemas.join(', ')}.',
      );
    }
    final selectedStorage = storage;
    if (selectedStorage is VoxelMemoryStorage) {
      if (encryption != null || schemaEncryption.values.any((value) => value != null)) {
        throw UnsupportedError('Memory storage does not support encryption.');
      }
      if (schemaStorage.values.any((value) => value is! VoxelMemoryStorage)) {
        throw UnsupportedError(
          'A memory main database supports only memory schema storage.',
        );
      }
      return _openMemory(schema, checked);
    }
    if (selectedStorage is VoxelOpfsStorage) {
      throw UnsupportedError('Browser OPFS storage is not available yet.');
    }
    final directory = switch (selectedStorage) {
      VoxelDirectoryStorage(:final path) => path,
      null => null,
      _ => throw UnsupportedError('Unsupported Voxel storage selection.'),
    };
    final schemaDirectories = <String, String?>{};
    final schemaEncryptionCiphers = <String, String?>{};
    final schemaEncryptionKeys = <String, Uint8List?>{};
    for (final schemaName in namedSchemas) {
      final override = schemaStorage[schemaName];
      schemaDirectories[schemaName] = switch (override) {
        VoxelDirectoryStorage(:final path) => path,
        null => null,
        _ => throw UnsupportedError(
          'Native persistent databases require directory storage for schema `$schemaName`.',
        ),
      };
      final selectedEncryption = schemaEncryption.containsKey(schemaName)
          ? schemaEncryption[schemaName]
          : encryption;
      schemaEncryptionCiphers[schemaName] = selectedEncryption?.cipher.name;
      schemaEncryptionKeys[schemaName] = selectedEncryption?.key;
    }
    final database = await openVoxelPersistentDatabase(
      databaseName: schema.name,
      directory: directory,
      migrations: checked,
      lockTimeout: migrations.lockTimeout,
      encryptionCipher: encryption?.cipher.name,
      encryptionKey: encryption?.key,
      schemaDirectories: schemaDirectories,
      schemaEncryptionCiphers: schemaEncryptionCiphers,
      schemaEncryptionKeys: schemaEncryptionKeys,
    );
    return VoxelDb._(database, schema.name, schema.tables);
  }

  static Future<VoxelDb> _openMemory(
    VoxelDatabaseSchema schema,
    VoxelMigrationPlan checked,
  ) async {
    TursoDatabase? database;
    try {
      database = await TursoDatabase.open(
        TursoLocation.memory(),
        web: voxelWebOptions(),
      );
      for (final schemaName in checked.schemaNames) {
        if (schemaName == 'main') continue;
        await database.execute("ATTACH DATABASE ':memory:' AS ${_quote(schemaName)}");
      }
      await database.execute('PRAGMA foreign_keys=ON');
      await _verifyForeignKeys(database);
      await checked.apply(database);
      await _verifyForeignKeys(database);
      return VoxelDb._(database, schema.name, schema.tables);
    } on Object catch (error, stackTrace) {
      if (database != null) {
        try {
          await database.close();
        } on Object {
          // Preserve the initialization failure as the primary error.
        }
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }
}

Future<void> _verifyForeignKeys(TursoDatabase database) async {
  final enabled = (await database.query('PRAGMA foreign_keys')).rows.single.getInt(
    'foreign_keys',
  );
  if (enabled != 1) {
    throw StateError('Voxel could not enable foreign-key enforcement.');
  }
}

String _quote(String identifier) => '"${identifier.replaceAll('"', '""')}"';

/// Internal driver inspection used by Voxel integration fixtures.
abstract final class VoxelTesting {
  /// Executes trusted fixture SQL through [executor].
  static Future<void> execute(VoxelExecutor executor, String sql) async {
    await executor.executeAffected(VoxelCompiledQuery(sql, const []));
  }

  /// Reads one integer column named `value` from trusted fixture SQL.
  static Future<int> scalarInt(VoxelExecutor executor, String sql) async {
    return (await executor.execute<int>(
      VoxelCompiledQuery(sql, const []),
      (values, sqlNulls) => (values.single! as BigInt).toInt(),
    )).single;
  }

  /// Reads one text column named `value` from trusted fixture SQL.
  static Future<String> scalarText(VoxelExecutor executor, String sql) async {
    return (await executor.execute<String>(
      VoxelCompiledQuery(sql, const []),
      (values, sqlNulls) => values.single! as String,
    )).single;
  }
}
