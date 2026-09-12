import 'package:test/test.dart';
import 'package:voxel/voxel.dart';

import 'generated_consumer.dart';

void main() {
  group('generated text table', () {
    final schema = Users.db.buildSchema();
    final table = schema.definition;

    test('retains declaration and generated type contracts', () {
      expect(schema.schemaName, 'main');
      expect(schema.tableName, 'users');
      expect(schema.renamedFrom, 'people');
      expect(table.displayName.physicalName, 'displayName');
      expect(table.displayName.renamedFrom, 'name');
      expect(
        UsersCompanion.insert(displayName: const VoxelValue.present('Ada')),
        isA<UsersCompanion>(),
      );
      expect(
        const User(id: 'usr_00000000000000000000', displayName: 'Ada', nickname: null),
        isA<User>(),
      );
    });

    test('encodes and decodes text without conflating SQL null', () {
      expect(table.displayName.codec.encode('Ada'), 'Ada');
      expect(table.displayName.codec.decode('Ada', isSqlNull: false), 'Ada');
      expect(() => table.displayName.codec.decode(null, isSqlNull: true), throwsFormatException);
      expect(table.nickname.codec.decode(null, isSqlNull: true), isNull);
      expect(
        () => table.displayName.codec.decode(BigInt.one, isSqlNull: false),
        throwsFormatException,
      );
    });

    test('does not invoke runtime defaults while building metadata', () {
      final generatedId = table.id.defaultFn;
      expect(generatedId, isNotNull);
      expect(generatedId!(), startsWith('usr_'));
    });
  });
}
