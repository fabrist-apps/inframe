// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// **************************************************************************
// RivetDatabaseGenerator
// **************************************************************************

abstract class _$FixtureAppDatabase {
  Future<RivetDb> open({
    required RivetConnection connection,
    RivetPoolOptions pool = const RivetPoolOptions(),
  }) => RivetDb.open(
    connection: connection,
    pool: pool,
    tables: [
      PackageUsers.db.buildSchema() as RivetTableSchema<Object?, Object?>,
    ],
  );
}
