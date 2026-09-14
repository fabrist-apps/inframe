import 'package:test/test.dart';
import 'package:voxel/src/migration_recovery.dart';
import 'package:voxel/src/migration_status.dart';

void main() {
  group('VoxelRecoveryCheckPlan', () {
    test('should parse typed parameters for one structural catalog check', () {
      final plan = VoxelRecoveryCheckPlan.parse(
        [
          _absenceCheck(),
          {
            'sql': '''
              SELECT EXISTS (
                SELECT 1 FROM "auth".sqlite_schema
                WHERE type = ? AND name = ? AND tbl_name = ? AND sql = ?
                  AND ? IS NULL AND ? = 1 AND ? = 1.25
              )
            ''',
            'parameters': [
              {'type': 'string', 'value': 'index'},
              {'type': 'string', 'value': 'users_email_idx'},
              {'type': 'string', 'value': 'users'},
              {'type': 'string', 'value': 'CREATE INDEX users_email_idx ON users(email)'},
              {'type': 'null', 'value': null},
              {'type': 'boolean', 'value': true},
              {'type': 'decimal', 'value': '1.25'},
            ],
            'expected': true,
          },
        ],
        scopeName: 'auth',
      );

      expect(
        plan.checks.last.parameters,
        [
          'index',
          'users_email_idx',
          'users',
          'CREATE INDEX users_email_idx ON users(email)',
          null,
          BigInt.one,
          1.25,
        ],
      );
      expect(
        () => plan.checks.last.parameters.add('mutable'),
        throwsUnsupportedError,
      );
    });

    test('should reject side-effecting SQL', () {
      expect(
        () => _parse('SELECT load_extension(?)'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => _parse('DELETE FROM "auth".sqlite_schema RETURNING 1'),
        throwsA(isA<FormatException>()),
      );
    });

    test('should reject a check that reads another file scope', () {
      expect(
        () => _parse(_structuralSql(scope: 'content')),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => _parse('${_structuralSql()} JOIN "content".secrets'),
        throwsA(isA<FormatException>()),
      );
    });

    test('should reject multiple statements', () {
      expect(
        () => _parse('${_structuralSql()}; SELECT 1'),
        throwsA(isA<FormatException>()),
      );
    });

    test('should reject object-existence-only evidence', () {
      expect(
        () => VoxelRecoveryCheckPlan.parse(
          [
            {
              'sql': '''
                SELECT EXISTS (
                  SELECT 1 FROM "auth".sqlite_schema
                  WHERE type = ? AND name = ?
                )
              ''',
              'parameters': [
                {'type': 'string', 'value': 'table'},
                {'type': 'string', 'value': 'users'},
              ],
              'expected': true,
            },
          ],
          scopeName: 'auth',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('should reject declarations without the exact before and after pair', () {
      expect(
        () => VoxelRecoveryCheckPlan.parse(
          [_structureCheck()],
          scopeName: 'auth',
        ),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => VoxelRecoveryCheckPlan.parse(
          [
            _absenceCheck()..['expected'] = true,
            _structureCheck(),
          ],
          scopeName: 'auth',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('should reject malformed typed parameters and placeholder counts', () {
      expect(
        () => VoxelRecoveryCheckPlan.parse(
          [
            _absenceCheck(),
            _structureCheck()
              ..['parameters'] = [
                {'type': 'decimal', 'value': 'NaN'},
              ],
          ],
          scopeName: 'auth',
        ),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => VoxelRecoveryCheckPlan.parse(
          [
            _absenceCheck(),
            _structureCheck()..['parameters'] = const <Object?>[],
          ],
          scopeName: 'auth',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('should classify only the exact postcondition and its complement', () {
      final plan = VoxelRecoveryCheckPlan.parse(
        [
          _absenceCheck(),
          _structureCheck(),
        ],
        scopeName: 'auth',
      );

      expect(
        plan.classify([BigInt.zero, BigInt.one]),
        VoxelRecoveryClassification.completed,
      );
      expect(
        plan.classify([BigInt.one, BigInt.zero]),
        VoxelRecoveryClassification.notStarted,
      );
      expect(
        plan.classify([BigInt.zero, BigInt.zero]),
        VoxelRecoveryClassification.uncertain,
      );
    });

    test('should classify malformed scalar results as uncertain', () {
      final plan = VoxelRecoveryCheckPlan.parse(
        [_absenceCheck(), _structureCheck()],
        scopeName: 'auth',
      );

      expect(plan.classify(const ['true', true]), VoxelRecoveryClassification.uncertain);
      expect(plan.classify(const [2, true]), VoxelRecoveryClassification.uncertain);
      expect(plan.classify(const []), VoxelRecoveryClassification.uncertain);
    });
  });

  group('VoxelMigrationStatus', () {
    test('should defensively freeze status collections and evidence', () {
      final evidence = <String, Object?>{
        'observations': <Object?>[true],
      };
      final phases = <VoxelMigrationPhaseStatus>[
        VoxelMigrationPhaseStatus(
          id: '0',
          scopeId: 'scope-id',
          state: VoxelMigrationPhaseState.started,
          attemptId: 'attempt-id',
          completionRecorded: false,
          evidence: evidence,
        ),
      ];
      final migrations = <VoxelMigrationStatusEntry>[
        VoxelMigrationStatusEntry(
          id: 'migration-id',
          checksum: 'checksum',
          ordinal: 0,
          phases: phases,
        ),
      ];
      final status = VoxelMigrationStatus(
        databaseId: 'database-id',
        migrations: migrations,
      );

      phases.clear();
      migrations.clear();
      (evidence['observations']! as List<Object?>).clear();

      expect(status.migrations.single.phases, hasLength(1));
      expect(status.migrations.single.phases.single.evidence, {
        'observations': [true],
      });
      expect(status.migrations.clear, throwsUnsupportedError);
      expect(
        () => (status.migrations.single.phases.single.evidence!['observations']! as List<Object?>)
            .clear(),
        throwsUnsupportedError,
      );
    });
  });
}

VoxelRecoveryCheckPlan _parse(String sql) => VoxelRecoveryCheckPlan.parse(
  [
    _absenceCheck(),
    {
      'sql': sql,
      'parameters': const <Object?>[],
      'expected': true,
    },
  ],
  scopeName: 'auth',
);

Map<String, Object?> _absenceCheck() => {
  'sql': '''
    SELECT NOT EXISTS (
      SELECT 1 FROM "auth".sqlite_schema
      WHERE type = ? AND name = ? AND tbl_name = ?
    )
  ''',
  'parameters': [
    {'type': 'string', 'value': 'index'},
    {'type': 'string', 'value': 'users_email_idx'},
    {'type': 'string', 'value': 'users'},
  ],
  'expected': false,
};

Map<String, Object?> _structureCheck() => {
  'sql': _structuralSql(),
  'parameters': [
    {'type': 'string', 'value': 'index'},
    {'type': 'string', 'value': 'users_email_idx'},
    {'type': 'string', 'value': 'users'},
    {'type': 'string', 'value': 'CREATE INDEX users_email_idx ON users(email)'},
  ],
  'expected': true,
};

String _structuralSql({String scope = 'auth'}) =>
    '''
  SELECT EXISTS (
    SELECT 1 FROM "$scope".sqlite_schema
    WHERE type = ? AND name = ? AND tbl_name = ? AND sql = ?
  )
''';
