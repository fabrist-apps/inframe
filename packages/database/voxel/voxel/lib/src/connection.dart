import 'dart:typed_data';

import 'package:turso/turso.dart';

import 'package:voxel/src/migration.dart';
import 'package:voxel/src/platform.dart';
import 'package:voxel/src/schema.dart';

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

/// An initialized Voxel database and the Turso connection it owns.
///
/// Obtain this through the generated `VoxelApp().open(...)` extension. The
/// returned handle has all memory schemas attached, bundled migrations applied,
/// and foreign-key enforcement enabled. Call [close] when the application no
/// longer needs it.
final class VoxelDb {
  VoxelDb._(this._database, this.name, this.tables);

  final TursoDatabase _database;

  /// The database name declared by `@VoxelDatabase`.
  final String name;

  /// Connection-free schemas registered by the generated application database.
  final List<VoxelTableSchema<Object?, Object?>> tables;

  /// Drains accepted driver work and releases the owned connection.
  Future<void> close() => _database.close();
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
    final selectedStorage =
        storage ??
        (throw UnsupportedError(
          'Voxel memory bootstrap requires storage: VoxelStorage.memory().',
        ));
    if (selectedStorage is! VoxelMemoryStorage) {
      throw UnsupportedError(
        'FBR-201 supports VoxelStorage.memory(); persistent storage is not available yet.',
      );
    }
    if (schemaStorage.isNotEmpty || encryption != null || schemaEncryption.isNotEmpty) {
      throw UnsupportedError(
        'Memory bootstrap does not yet support storage or encryption overrides.',
      );
    }

    final checked = VoxelMigrationPlan.validate(schema: schema, bundle: bundle);
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
  /// Executes trusted fixture SQL against [database].
  static Future<void> execute(VoxelDb database, String sql) async {
    await database._database.execute(sql);
  }

  /// Reads one integer column named `value` from trusted fixture SQL.
  static Future<int> scalarInt(VoxelDb database, String sql) async {
    final row = (await database._database.query(sql)).rows.single;
    return row.getInt('value');
  }
}
