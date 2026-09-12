import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';

import 'src/database_generator.dart';
import 'src/table_generator.dart';

/// Builds generated Rivet table and database parts.
Builder rivetBuilder(BuilderOptions options) => SharedPartBuilder(
  const [RivetTableGenerator(), RivetDatabaseGenerator()],
  'rivet',
);
