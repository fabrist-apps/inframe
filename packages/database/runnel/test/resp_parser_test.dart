import 'dart:convert';

import 'package:runnel/runnel.dart';
import 'package:test/test.dart';

void main() {
  group('RespParser', () {
    test('should decode fragmented and coalesced RESP3 values', () {
      final parser = RespParser(maxFrameBytes: 1024, maxNestingDepth: 4);

      expect(
        parser.add(
          ascii.encode(
            r'$5'
            '\r\nhe',
          ),
        ),
        isEmpty,
      );
      final values = parser.add(
        ascii.encode('llo\r\n:42\r\n#t\r\n,1.5\r\n(18446744073709551615\r\n'),
      );

      expect((values[0] as RespBlobString).value, ascii.encode('hello'));
      expect((values[1] as RespInteger).value, 42);
      expect((values[2] as RespBoolean).value, isTrue);
      expect((values[3] as RespDouble).value, 1.5);
      expect((values[4] as RespBigNumber).value, BigInt.parse('18446744073709551615'));
    });

    test('should preserve maps, sets, pushes, attributes, nulls, and nested errors', () {
      final parser = RespParser(maxFrameBytes: 1024, maxNestingDepth: 4);
      final values = parser.add(
        ascii.encode(
          '%1\r\n+a\r\n~2\r\n:1\r\n:2\r\n'
          '|1\r\n+ttl\r\n:5\r\n>2\r\n+message\r\n!8\r\nERR nope\r\n'
          '_\r\n*2\r\n+ok\r\n-ERR bad\r\n=9\r\ntxt:hello\r\n',
        ),
      );

      expect(values[0], isA<RespMap>());
      expect(((values[0] as RespMap).entries.single.value as RespSet).values, hasLength(2));
      final attributed = values[1] as RespAttributed;
      expect(attributed.attributes, hasLength(1));
      final push = attributed.value as RespPush;
      expect(push.values[1], isA<RespError>());
      expect((push.values[1] as RespError).blob, isTrue);
      expect(values[2], isA<RespNull>());
      final array = values[3] as RespArray;
      expect(array.values[1], isA<RespError>());
      final verbatim = values[4] as RespVerbatimString;
      expect(verbatim.format, 'txt');
      expect(utf8.decode(verbatim.value), 'hello');
    });

    test('should accept exact frame and depth limits and reject excess', () {
      final exactFrame = ascii.encode('+OK\r\n');
      expect(
        RespParser(maxFrameBytes: exactFrame.length, maxNestingDepth: 1).add(exactFrame),
        hasLength(1),
      );
      expect(
        () => RespParser(maxFrameBytes: exactFrame.length - 1, maxNestingDepth: 1).add(exactFrame),
        throwsA(isA<RunnelLimitError>()),
      );

      expect(
        RespParser(maxFrameBytes: 32, maxNestingDepth: 2).add(ascii.encode('*1\r\n*1\r\n:1\r\n')),
        hasLength(1),
      );
      expect(
        () => RespParser(
          maxFrameBytes: 32,
          maxNestingDepth: 1,
        ).add(ascii.encode('*1\r\n*1\r\n:1\r\n')),
        throwsA(isA<RunnelLimitError>()),
      );
      expect(
        () => RespParser(maxFrameBytes: 8, maxNestingDepth: 1).add(
          ascii.encode(
            r'$9'
            '\r\n',
          ),
        ),
        throwsA(isA<RunnelLimitError>()),
      );
      expect(
        () => RespParser(maxFrameBytes: 15, maxNestingDepth: 1).add(
          ascii.encode(
            r'$10'
            '\r\n',
          ),
        ),
        throwsA(isA<RunnelLimitError>()),
      );

      final attributed = ascii.encode('|1\r\n+meta\r\n+x\r\n+OK\r\n');
      expect(
        RespParser(maxFrameBytes: attributed.length, maxNestingDepth: 1).add(attributed),
        hasLength(1),
      );
      expect(
        () => RespParser(
          maxFrameBytes: attributed.length - 1,
          maxNestingDepth: 1,
        ).add(attributed),
        throwsA(isA<RunnelLimitError>()),
      );
    });

    test('should reject malformed framing before returning a value', () {
      for (final frame in [
        '\$3\r\nabcXX',
        '#x\r\n',
        '_x\r\n',
        '?unknown\r\n',
        '%-1\r\n',
        '\$-1\r\n',
        '*-1\r\n',
      ]) {
        expect(
          () => RespParser(maxFrameBytes: 64, maxNestingDepth: 4).add(ascii.encode(frame)),
          throwsA(isA<RunnelProtocolError>()),
        );
      }
    });
  });
}
