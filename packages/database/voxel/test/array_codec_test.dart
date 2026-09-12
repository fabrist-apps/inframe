import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:voxel/voxel.dart';
import 'package:voxel_fixture_schema/authors.dart';

import 'generated_consumer.dart';

void main() {
  final schema = ArrayValues.db.buildSchema();
  final table = schema.definition;

  test('generates independent element and column nullability', () {
    final row = schema.decode(
      [
        '[]',
        '[null,"value"]',
        null,
        null,
        '[]',
        '[]',
        '[]',
        '[]',
        '[]',
        '[]',
        '["draft"]',
        '[]',
        '[]',
        '[]',
        '[]',
        '[]',
      ],
      [
        false,
        false,
        true,
        true,
        false,
        false,
        false,
        false,
        false,
        false,
        false,
        false,
        false,
        false,
        false,
        false,
      ],
    );

    expect(row.texts, <String>[]);
    expect(row.nullableElements, [null, 'value']);
    expect(row.nullableArray, isNull);
    expect(row.nullableElementsAndArray, isNull);
    expect(ArrayValuesCompanion.insert, isA<Function>());
  });

  test('encodes each catalog storage type using version 1 JSON framing', () {
    expect(table.texts.codec.encode(['a']), '["a"]');
    expect(table.integers.codec.encode([-2147483648, 2147483647]), '[-2147483648,2147483647]');
    expect(table.reals.codec.encode([1.5]), '[1.5]');
    expect(table.booleans.codec.encode([true, false]), '[true,false]');
    expect(
      table.timestamps.codec.encode([DateTime.fromMicrosecondsSinceEpoch(-1)]),
      '[-1]',
    );
    expect(table.jsonValues.codec.encode([const JsonNull()]), '[[null]]');
    expect(
      table.nullableJsonValues.codec.encode([
        null,
        const JsonNull(),
        JsonValue.from(const [1, null]),
      ]),
      '[null,[null],[[1,null]]]',
    );
    expect(table.statuses.codec.encode([PostStatus.published]), '["live"]');
    expect(
      table.statuses.codec.encode(table.statuses.defaultFn!()! as List<PostStatus>),
      '["draft"]',
    );
    expect(
      table.vectors.codec.encode([
        Float32List.fromList([0.5, -2, 3.25]),
      ]),
      '[[0.5,-2.0,3.25]]',
    );
    expect(table.codes.codec.encode([const UserCode('ada')]), '["ada"]');
    expect(table.counts.codec.encode([const CountValue(2)]), '[2]');
    expect(
      table.preferencesList.codec.encode([const Preferences(darkMode: true)]),
      '[[{"darkMode":true}]]',
    );
    expect(table.texts.codec.codecVersion, 1);
  });

  test('decodes catalog values through the scalar validation pipelines', () {
    expect(table.booleans.codec.decode('[true,false]', isSqlNull: false), [true, false]);
    expect(
      table.timestamps.codec.decode('[-1]', isSqlNull: false).single.microsecondsSinceEpoch,
      -1000,
    );
    expect(table.statuses.codec.decode('["live"]', isSqlNull: false), [PostStatus.published]);
    expect(
      table.vectors.codec.decode('[[0.5,-2.0,3.25]]', isSqlNull: false).single,
      Float32List.fromList([0.5, -2, 3.25]),
    );
    expect(table.nullableJsonValues.codec.decode('[null,[null]]', isSqlNull: false), [
      null,
      const JsonNull(),
    ]);
    expect(
      table.preferencesList.codec.decode('[[{"darkMode":true}]]', isSqlNull: false).single.darkMode,
      isTrue,
    );
  });

  test('rejects malformed framing and reuses scalar checks without exposing values', () {
    expect(() => VoxelArrayCodec(VoxelTextCodec(), codecVersion: 2), throwsUnsupportedError);
    expect(() => VoxelArrayCodec(VoxelArrayCodec(VoxelTextCodec())), throwsFormatException);
    final VoxelCodec<dynamic> untypedTextArray = table.texts.codec;
    expect(() => untypedTextArray.encode([null]), throwsA(anything));
    expect(() => table.integers.codec.encode([2147483648]), throwsRangeError);
    expect(() => table.counts.codec.encode([const CountValue(2147483648)]), throwsRangeError);
    expect(() => table.vectors.codec.encode([Float32List(2)]), throwsFormatException);
    expect(
      () => table.vectors.codec.encode([
        Float32List.fromList([1, double.infinity, 3]),
      ]),
      throwsFormatException,
    );
    expect(() => table.jsonValues.codec.decode('[null]', isSqlNull: false), throwsFormatException);
    expect(
      () => table.jsonValues.codec.decode('[[null],[]]', isSqlNull: false),
      throwsFormatException,
    );
    expect(() => table.texts.codec.decode('[[]]', isSqlNull: false), throwsFormatException);
    expect(
      () => table.codes.decodeValue('["secret"]', isSqlNull: false),
      throwsA(
        isA<VoxelConversionException>()
            .having((error) => error.table, 'table', 'codec.arrayValues')
            .having((error) => error.column, 'column', 'codes')
            .having((error) => error.toString(), 'message', isNot(contains('secret'))),
      ),
    );
  });
}
