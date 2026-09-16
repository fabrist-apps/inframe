import 'dart:convert';
import 'dart:typed_data';

import 'package:runnel/runnel.dart';
import 'package:test/test.dart';

void main() {
  group('RedisCommand encoding', () {
    test('should preserve UTF-8 and binary bytes across public copies', () {
      final source = Uint8List.fromList([0, 255, 13, 10]);
      final command = setBytesCommand('café', source);
      source[0] = 99;
      command.arguments.last.bytes[1] = 99;

      final expected = [
        ...utf8.encode('*3\r\n\$3\r\nSET\r\n\$5\r\ncafé\r\n\$4\r\n'),
        0,
        255,
        13,
        10,
        13,
        10,
      ];
      final encoded = encodeCommand(command);
      expect(encoded, expected);
      expect(command.encodedLength, 34);
      encoded.fillRange(0, encoded.length, 0);
      expect(encodeCommand(command), expected);
    });

    test('should admit exact byte limits across bulk length digit boundaries', () {
      for (final (payloadLength, wireLength) in [(9, 34), (10, 36), (99, 125), (100, 127)]) {
        final command = setBytesCommand('', Uint8List(payloadLength));
        expect(command.encodedLength, wireLength);
        expect(encodeCommand(command), hasLength(wireLength));
        expect(() => _batch(wireLength).add(command), returnsNormally);
        expect(() => _batch(wireLength - 1).add(command), throwsStateError);
      }
    });

    test('should account for a two-digit argument count and empty arguments', () {
      final command = mgetCommand(List.filled(9, ''));
      final expected = '*10\r\n\$4\r\nMGET\r\n${List.filled(9, '\$0\r\n\r\n').join()}';
      expect(encodeCommand(command), ascii.encode(expected));
      expect(command.encodedLength, 69);
      expect(() => _batch(69).add(command), returnsNormally);
      expect(() => _batch(68).add(command), throwsStateError);
    });
  });
}

RedisBatch _batch(int maxBytes) => RedisBatch.internal(
  maxCommands: 1,
  maxBytes: maxBytes,
  reservedCommands: 0,
  reservedBytes: 0,
  defaultTimeout: const Duration(seconds: 1),
  executor: (_, _, _) async => const [],
);
