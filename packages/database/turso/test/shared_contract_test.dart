@TestOn('vm')
library;

import 'package:test/test.dart';
import 'package:turso/turso.dart';

import '../integration_test/support/sql_contract.dart';

void main() {
  group('TursoDatabase shared native/browser contract', () {
    test('should preserve bound values and SQL validation', () async {
      final database = await TursoDatabase.open(TursoLocation.memory());
      addTearDown(database.close);
      await verifyValues(database);
    });
    test('should isolate transactions, expire handles, and drain close', () async {
      final database = await TursoDatabase.open(TursoLocation.memory());
      addTearDown(database.close);
      await verifyTransactions(database);
    });
  });
}
