import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:runnel/runnel.dart';
import 'package:test/test.dart';

void main() {
  group('StreamId', () {
    test('should preserve and compare unsigned 64-bit components exactly', () {
      final maximum = BigInt.parse('18446744073709551615');
      final id = StreamId(maximum, maximum);

      expect(id.toString(), '18446744073709551615-18446744073709551615');
      expect(StreamId.parse(id.toString()), id);
      expect(
        StreamId(BigInt.one, BigInt.zero).compareTo(StreamId(BigInt.one, BigInt.one)),
        isNegative,
      );
      expect(
        StreamId(BigInt.one, maximum).compareTo(StreamId(BigInt.two, BigInt.zero)),
        isNegative,
      );
    });

    test('should reject malformed and out-of-range components', () {
      final aboveMaximum = BigInt.parse('18446744073709551616');

      for (final value in [
        '1',
        '-1-0',
        '0--1',
        '1.0-0',
        '0-1x',
        '18446744073709551616-0',
      ]) {
        expect(() => StreamId.parse(value), throwsFormatException, reason: value);
      }
      expect(() => StreamId(BigInt.from(-1), BigInt.zero), throwsRangeError);
      expect(() => StreamId(BigInt.zero, aboveMaximum), throwsRangeError);
    });
  });

  group('RunnelStreamCommands', () {
    late _StreamPeer peer;
    late Runnel client;

    setUp(() async {
      peer = await _StreamPeer.start();
      client = await Runnel.connect('redis://127.0.0.1:${peer.port}');
    });

    tearDown(() async {
      await client.close();
      await peer.close();
    });

    test('should encode every stream command and decode typed replies', () async {
      final sourceField = Uint8List.fromList([0, 255]);
      final sourceValue = Uint8List.fromList([1, 254]);
      final fields = [
        StreamField(sourceField, sourceValue),
        StreamField(sourceField, Uint8List.fromList([2])),
      ];

      final generated = client.xadd(
        'history',
        fields,
        maxLength: 10,
        approximate: true,
      );
      sourceField[0] = 9;
      sourceValue[0] = 9;
      fields.clear();
      expect(await generated, StreamId(BigInt.one, BigInt.zero));
      expect(
        await client.xadd(
          'history',
          [StreamField.text('kind', 'created')],
          id: StreamId(BigInt.two, BigInt.from(3)),
        ),
        StreamId(BigInt.two, BigInt.from(3)),
      );

      final entries = await client.xrange(
        'history',
        start: StreamBound.id(StreamId(BigInt.one, BigInt.zero)),
        count: 2,
      );
      expect(entries, hasLength(1));
      expect(entries.single.id, StreamId.parse('18446744073709551615-7'));
      expect(entries.single.fields, hasLength(2));
      expect(entries.single.fields.map((field) => field.field), [
        [0, 255],
        [0, 255],
      ]);
      expect(entries.single.fields.map((field) => field.value), [
        [1, 254],
        [2],
      ]);

      expect(
        await client.xrevrange(
          'history',
          end: StreamBound.id(StreamId(BigInt.from(9), BigInt.zero)),
          count: 1,
        ),
        isEmpty,
      );
      expect(await client.xtrim('history', StreamTrim.maxLength(2)), 3);
      expect(
        await client.xtrim(
          'history',
          StreamTrim.minId(StreamId(BigInt.one, BigInt.zero), approximate: true),
        ),
        4,
      );
      expect(await client.xlen('history'), 5);

      final reads = await client.xread({
        'history': StreamId(BigInt.one, BigInt.zero),
        'other': StreamId(BigInt.two, BigInt.zero),
      }, count: 3);
      expect(reads, hasLength(1));
      expect(reads.single.key, 'history');
      expect(reads.single.entries.single.id, StreamId(BigInt.two, BigInt.zero));
      final resp2Reads = await client.xread({'history': StreamId(BigInt.two, BigInt.zero)});
      expect(resp2Reads.single.key, 'history');
      expect(resp2Reads.single.entries.single.id, StreamId(BigInt.from(3), BigInt.zero));
      expect(await client.xread({'history': StreamId(BigInt.from(3), BigInt.zero)}), isEmpty);

      expect(peer.commands.skip(1), [
        [
          ascii.encode('XADD'),
          ascii.encode('history'),
          ascii.encode('MAXLEN'),
          ascii.encode('~'),
          ascii.encode('10'),
          ascii.encode('*'),
          [0, 255],
          [1, 254],
          [0, 255],
          [2],
        ],
        [
          ascii.encode('XADD'),
          ascii.encode('history'),
          ascii.encode('2-3'),
          ascii.encode('kind'),
          ascii.encode('created'),
        ],
        [
          ascii.encode('XRANGE'),
          ascii.encode('history'),
          ascii.encode('1-0'),
          ascii.encode('+'),
          ascii.encode('COUNT'),
          ascii.encode('2'),
        ],
        [
          ascii.encode('XREVRANGE'),
          ascii.encode('history'),
          ascii.encode('9-0'),
          ascii.encode('-'),
          ascii.encode('COUNT'),
          ascii.encode('1'),
        ],
        [
          ascii.encode('XTRIM'),
          ascii.encode('history'),
          ascii.encode('MAXLEN'),
          ascii.encode('2'),
        ],
        [
          ascii.encode('XTRIM'),
          ascii.encode('history'),
          ascii.encode('MINID'),
          ascii.encode('~'),
          ascii.encode('1-0'),
        ],
        [ascii.encode('XLEN'), ascii.encode('history')],
        [
          ascii.encode('XREAD'),
          ascii.encode('COUNT'),
          ascii.encode('3'),
          ascii.encode('STREAMS'),
          ascii.encode('history'),
          ascii.encode('other'),
          ascii.encode('1-0'),
          ascii.encode('2-0'),
        ],
        [
          ascii.encode('XREAD'),
          ascii.encode('STREAMS'),
          ascii.encode('history'),
          ascii.encode('2-0'),
        ],
        [
          ascii.encode('XREAD'),
          ascii.encode('STREAMS'),
          ascii.encode('history'),
          ascii.encode('3-0'),
        ],
      ]);
    });

    test('should snapshot returned binary fields', () async {
      final entries = await client.xrange('history');
      final field = entries.single.fields.first;

      final fieldBytes = field.field..[0] = 9;
      final valueBytes = field.value..[0] = 9;

      expect(fieldBytes, [9, 255]);
      expect(valueBytes, [9, 254]);
      expect(field.field, [0, 255]);
      expect(field.value, [1, 254]);
      expect(() => entries.add(entries.single), throwsUnsupportedError);
      expect(() => entries.single.fields.add(field), throwsUnsupportedError);
    });

    test('should treat Stream keys as opaque after the STREAMS marker', () async {
      await client.xread({'BLOCK': StreamId(BigInt.zero, BigInt.zero)});
      await client.xread({'café': StreamId(BigInt.zero, BigInt.zero)});

      expect(peer.commands[1][2], ascii.encode('BLOCK'));
      expect(peer.commands[2][2], utf8.encode('café'));
    });

    test('should reject empty fields, cursors, and nonpositive count hints', () async {
      expect(() => client.xadd('history', []), throwsArgumentError);
      expect(
        () => client.xadd('history', [StreamField.text('field', 'value')], maxLength: -1),
        throwsRangeError,
      );
      expect(() => client.xrange('history', count: 0), throwsArgumentError);
      expect(() => client.xrevrange('history', count: -1), throwsArgumentError);
      expect(() => client.xread({}, count: 1), throwsArgumentError);
      expect(
        () => client.xread({'history': StreamId(BigInt.zero, BigInt.zero)}, count: 0),
        throwsArgumentError,
      );
      expect(() => StreamTrim.maxLength(-1), throwsRangeError);

      expect(peer.commands, hasLength(1));
    });
  });
}

final class _StreamPeer {
  _StreamPeer._(this._server);

  final ServerSocket _server;
  final List<List<Uint8List>> commands = [];
  final List<Socket> _sockets = [];
  var _xreadCount = 0;

  int get port => _server.port;

  static Future<_StreamPeer> start() async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final peer = _StreamPeer._(server);
    server.listen(peer._accept);
    return peer;
  }

  void _accept(Socket socket) {
    _sockets.add(socket);
    var buffer = <int>[];
    socket.listen((bytes) {
      buffer.addAll(bytes);
      while (true) {
        final parsed = _parseCommand(buffer);
        if (parsed == null) return;
        buffer = buffer.sublist(parsed.consumed);
        commands.add(parsed.arguments);
        _reply(socket, parsed.arguments);
      }
    });
  }

  void _reply(Socket socket, List<Uint8List> arguments) {
    switch (ascii.decode(arguments.first)) {
      case 'HELLO':
        socket.add(ascii.encode('%1\r\n+proto\r\n:3\r\n'));
      case 'XADD':
        final id = ascii.decode(arguments[2]) == 'MAXLEN' ? '1-0' : ascii.decode(arguments[2]);
        socket.add(_blob(id));
      case 'XRANGE':
        socket.add(_entriesReply(id: '18446744073709551615-7'));
      case 'XREVRANGE':
        socket.add(ascii.encode('*0\r\n'));
      case 'XTRIM':
        socket.add(ascii.encode(':${ascii.decode(arguments[2]) == 'MAXLEN' ? 3 : 4}\r\n'));
      case 'XLEN':
        socket.add(ascii.encode(':5\r\n'));
      case 'XREAD':
        _xreadCount++;
        if (_xreadCount == 1) {
          socket.add([
            ...ascii.encode('%1\r\n'),
            ..._blob('history'),
            ..._entriesReply(id: '2-0'),
          ]);
        } else if (_xreadCount == 2) {
          socket.add([
            ...ascii.encode('*1\r\n*2\r\n'),
            ..._blob('history'),
            ..._entriesReply(id: '3-0'),
          ]);
        } else {
          socket.add(ascii.encode('_\r\n'));
        }
    }
  }

  Future<void> close() async {
    for (final socket in _sockets) {
      await socket.close();
    }
    await _server.close();
  }
}

List<int> _entriesReply({required String id}) => [
  ...ascii.encode('*1\r\n*2\r\n'),
  ..._blob(id),
  ...ascii.encode('*4\r\n'),
  ..._blobBytes([0, 255]),
  ..._blobBytes([1, 254]),
  ..._blobBytes([0, 255]),
  ..._blobBytes([2]),
];

List<int> _blob(String value) => _blobBytes(utf8.encode(value));

List<int> _blobBytes(List<int> bytes) => [
  ...ascii.encode('\$${bytes.length}\r\n'),
  ...bytes,
  13,
  10,
];

({List<Uint8List> arguments, int consumed})? _parseCommand(List<int> bytes) {
  if (bytes.isEmpty || bytes.first != 42) return null;
  final headerEnd = _findCrlf(bytes, 0);
  if (headerEnd < 0) return null;
  final count = int.parse(ascii.decode(bytes.sublist(1, headerEnd)));
  var offset = headerEnd + 2;
  final arguments = <Uint8List>[];
  for (var index = 0; index < count; index++) {
    if (offset >= bytes.length || bytes[offset] != 36) return null;
    final lengthEnd = _findCrlf(bytes, offset);
    if (lengthEnd < 0) return null;
    final length = int.parse(ascii.decode(bytes.sublist(offset + 1, lengthEnd)));
    final valueStart = lengthEnd + 2;
    final valueEnd = valueStart + length;
    if (valueEnd + 2 > bytes.length) return null;
    arguments.add(Uint8List.fromList(bytes.sublist(valueStart, valueEnd)));
    offset = valueEnd + 2;
  }
  return (arguments: arguments, consumed: offset);
}

int _findCrlf(List<int> bytes, int start) {
  for (var index = start; index + 1 < bytes.length; index++) {
    if (bytes[index] == 13 && bytes[index + 1] == 10) return index;
  }
  return -1;
}
