import 'package:build/build.dart';
import 'package:rivet_generator/src/database_generator.dart';
import 'package:rivet_generator/src/enum_generator.dart';
import 'package:rivet_generator/src/table_generator.dart';
import 'package:source_gen/source_gen.dart';

/// Builds generated Rivet table and database parts.
Builder rivetBuilder(BuilderOptions options) => SharedPartBuilder(
  const [RivetTableGenerator(), RivetDatabaseGenerator(), RivetEnumGenerator()],
  'rivet',
);
