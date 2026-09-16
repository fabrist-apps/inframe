import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:conflux/effect.dart';
import 'package:conflux/option.dart';
import 'package:runnel/src/blocking.dart';
import 'package:runnel/src/commands/streams.dart';
import 'package:runnel/src/connection/redis_connection.dart';
import 'package:runnel/src/deadline.dart';
import 'package:runnel/src/errors.dart';
import 'package:runnel/src/limits.dart';
import 'package:test/test.dart';

import 'support/resp_peer.dart';

void main() {
  group('BlockingSession', () {
    test('should encode fractional pop waits and return exact typed values', () async {
      final peer = await _BlockingPeer.start();
      addTearDown(peer.close);
      final session = await _openSession(peer);
      addTearDown(() => session.close().runFuture());

      final result = session.blpop(
        ['first', 'second'],
        wait: const Duration(milliseconds: 1500),
      ).runFuture();
      final command = await peer.nextCommand();
      expect(command.textArguments, ['BLPOP', 'first', 'second', '1.5']);
      command.reply('*2\r\n\$5\r\nfirst\r\n\$5\r\nvalue\r\n');

      expect(
        await result,
        isA<Some<({String key, String value})>>().having((s) => s.value, 'value', (
          key: 'first',
          value: 'value',
        )),
      );
    });

    test('should distinguish normal pop and stream wait expiry', () async {
      final peer = await _BlockingPeer.start();
      addTearDown(peer.close);
      final session = await _openSession(peer);
      addTearDown(() => session.close().runFuture());

      final pop = session.brpop(['queue'], wait: const Duration(milliseconds: 1)).runFuture();
      final popCommand = await peer.nextCommand();
      expect(popCommand.textArguments, ['BRPOP', 'queue', '0.001']);
      popCommand.reply('_\r\n');
      expect(await pop, isA<None>());

      final read = session
          .xread(
            {'events': StreamId.parse('18446744073709551615-9')},
            wait: const Duration(milliseconds: 25),
            count: 2,
          )
          .runFuture();
      final readCommand = await peer.nextCommand();
      expect(readCommand.textArguments, [
        'XREAD',
        'COUNT',
        '2',
        'BLOCK',
        '25',
        'STREAMS',
        'events',
        '18446744073709551615-9',
      ]);
      readCommand.reply('_\r\n');
      expect(await read, isEmpty);
    });

    test('should decode blocking XREAD without losing duplicate binary fields', () async {
      final peer = await _BlockingPeer.start();
      addTearDown(peer.close);
      final session = await _openSession(peer);
      addTearDown(() => session.close().runFuture());

      final read = session.xread(
        {'events': StreamId.parse('0-0')},
        wait: const Duration(milliseconds: 10),
      ).runFuture();
      final command = await peer.nextCommand();
      command.reply(
        '%1\r\n\$6\r\nevents\r\n*1\r\n*2\r\n\$3\r\n1-2\r\n*4\r\n'
        '\$1\r\nf\r\n\$1\r\na\r\n\$1\r\nf\r\n\$2\r\n\u0000\u0001\r\n',
      );

      final values = await read;
      expect(values.single.key, 'events');
      expect(values.single.entries.single.id, StreamId.parse('1-2'));
      expect(
        values.single.entries.single.fields.map((field) => field.field),
        [
          Uint8List.fromList([102]),
          Uint8List.fromList([102]),
        ],
      );
      expect(
        values.single.entries.single.fields.map((field) => field.value),
        [
          Uint8List.fromList([97]),
          Uint8List.fromList([0, 1]),
        ],
      );
    });

    test('should reject invalid waits, keys, cursors, and counts before sending', () async {
      final peer = await _BlockingPeer.start();
      addTearDown(peer.close);
      final session = await _openSession(peer);
      addTearDown(() => session.close().runFuture());

      await expectLater(
        session.blpop([], wait: const Duration(milliseconds: 1)).runFuture(),
        throwsExpected(isA<RunnelInputError>()),
      );
      await expectLater(
        session.blpop(['queue'], wait: Duration.zero).runFuture(),
        throwsExpected(isA<RunnelInputError>()),
      );
      await expectLater(
        session.brpop(
          ['queue'],
          wait: const Duration(microseconds: 1501),
        ).runFuture(),
        throwsExpected(isA<RunnelInputError>()),
      );
      await expectLater(
        session.xread({}, wait: const Duration(milliseconds: 1)).runFuture(),
        throwsExpected(isA<RunnelInputError>()),
      );
      await expectLater(
        session
            .xread(
              {'events': StreamId.parse('0-0')},
              wait: const Duration(milliseconds: 1),
              count: 0,
            )
            .runFuture(),
        throwsExpected(isA<RunnelInputError>()),
      );
      await expectLater(
        session
            .blpop(
              ['queue'],
              wait: const Duration(milliseconds: 1),
              timeout: Duration.zero,
            )
            .runFuture(),
        throwsExpected(isA<RunnelInputError>()),
      );
      expect(peer.commandCount, 0);
    });

    test('should use wait plus the configured command timeout by default', () async {
      final peer = await _BlockingPeer.start();
      addTearDown(peer.close);
      final session = await _openSession(
        peer,
        commandTimeout: const Duration(milliseconds: 30),
      );
      addTearDown(() => session.close().runFuture());
      final stopwatch = Stopwatch()..start();

      final operation = session.blpop(
        ['queue'],
        wait: const Duration(milliseconds: 40),
      ).runFuture();
      await peer.nextCommand();

      await expectLater(operation, throwsExpected(isA<RunnelTimeoutError>()));
      expect(stopwatch.elapsed, greaterThanOrEqualTo(const Duration(milliseconds: 55)));
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 1)));
    });

    test('should allow a shorter explicit timeout and become terminal', () async {
      final peer = await _BlockingPeer.start();
      addTearDown(peer.close);
      final session = await _openSession(peer);
      addTearDown(() => session.close().runFuture());

      final operation = session
          .blpop(
            ['queue'],
            wait: const Duration(seconds: 1),
            timeout: const Duration(milliseconds: 20),
          )
          .runFuture();
      await peer.nextCommand();

      await expectLater(
        operation,
        throwsExpected(
          isA<RunnelTimeoutError>().having(
            (error) => error.deliveryStatus,
            'delivery status',
            isA<Some<RedisDeliveryStatus>>().having(
              (s) => s.value,
              'value',
              RedisDeliveryStatus.outcomeUnknown,
            ),
          ),
        ),
      );
      await expectLater(
        session.brpop(['queue'], wait: const Duration(milliseconds: 1)).runFuture(),
        throwsExpected(isA<RunnelClosedError>()),
      );
      expect(peer.connectionCount, 1);
    });

    test('should reject a second active call before transmission', () async {
      final peer = await _BlockingPeer.start();
      addTearDown(peer.close);
      final session = await _openSession(peer);
      addTearDown(() => session.close().runFuture());

      final first = session.blpop(['one'], wait: const Duration(seconds: 1)).runFuture();
      final command = await peer.nextCommand();
      await expectLater(
        session.brpop(['two'], wait: const Duration(seconds: 1)).runFuture(),
        throwsExpected(isA<RunnelUsageError>()),
      );
      expect(peer.commandCount, 1);

      command.reply('_\r\n');
      expect(await first, isA<None>());
    });

    test('should make connection loss terminal without reopening or replaying', () async {
      final peer = await _BlockingPeer.start();
      addTearDown(peer.close);
      var opens = 0;
      final session = await BlockingSessionAccess.internal(
        openConnection: () {
          opens++;
          return _openConnection(peer);
        },
      );
      addTearDown(() => session.close().runFuture());

      final operation = session.brpop(['queue'], wait: const Duration(seconds: 1)).runFuture();
      final command = await peer.nextCommand();
      command.destroy();

      await expectLater(operation, throwsExpected(isA<RunnelTransportError>()));
      await expectLater(
        session.blpop(['queue'], wait: const Duration(milliseconds: 1)).runFuture(),
        throwsExpected(isA<RunnelClosedError>()),
      );
      expect(opens, 1);
      expect(peer.commandCount, 1);
    });

    test('should close immediately, fail active work, and notify once', () async {
      final peer = await _BlockingPeer.start();
      addTearDown(peer.close);
      var closeNotifications = 0;
      final session = await BlockingSessionAccess.internal(
        openConnection: () => _openConnection(peer),
        onClosed: (_) => closeNotifications++,
      );

      final operation = session.blpop(['queue'], wait: const Duration(seconds: 30)).runFuture();
      await peer.nextCommand();
      await Future.wait([session.close().runFuture(), session.close().runFuture()]);

      await expectLater(
        operation,
        throwsExpected(
          isA<RunnelClosedError>().having(
            (error) => error.deliveryStatus,
            'delivery status',
            isA<Some<RedisDeliveryStatus>>().having(
              (s) => s.value,
              'value',
              RedisDeliveryStatus.outcomeUnknown,
            ),
          ),
        ),
      );
      expect(closeNotifications, 1);
      await peer.waitForLatestDisconnect();
    });
  });
}

Future<BlockingSession> _openSession(
  _BlockingPeer peer, {
  Duration commandTimeout = const Duration(seconds: 5),
}) => BlockingSessionAccess.internal(
  openConnection: () => _openConnection(peer),
  commandTimeout: commandTimeout,
);

Future<RedisConnection> _openConnection(_BlockingPeer peer) => RedisConnection.open(
  host: '127.0.0.1',
  port: peer.port,
  tls: false,
  securityContext: null,
  limits: const RunnelLimits(),
  deadline: Deadline(const Duration(seconds: 1)),
  onTerminated: (_, _) {},
);

final class _BlockingPeer {
  late final RespPeer _peer;

  static Future<_BlockingPeer> start() async {
    final peer = _BlockingPeer();
    peer._peer = await RespPeer.start(
      onConnect: (socket) => peer._connections.add(_PeerConnection(socket)),
      onDisconnect: (socket) => peer._connections
          .firstWhere((connection) => identical(connection.socket, socket))
          .disconnected
          .complete(),
      onCommand: (command) {
        peer.commandCount++;
        peer._addCommand(_PeerCommand(command.socket, command.arguments));
      },
    );
    return peer;
  }

  final List<_PeerCommand> _commands = [];
  final List<Completer<_PeerCommand>> _commandWaiters = [];
  final List<_PeerConnection> _connections = [];
  int commandCount = 0;

  int get port => _peer.port;
  int get connectionCount => _connections.length;

  Future<void> waitForLatestDisconnect() => _connections.last.disconnected.future;

  Future<_PeerCommand> nextCommand() {
    if (_commands.isNotEmpty) return Future.value(_commands.removeAt(0));
    final waiter = Completer<_PeerCommand>();
    _commandWaiters.add(waiter);
    return waiter.future;
  }

  void _addCommand(_PeerCommand command) {
    if (_commandWaiters.isNotEmpty) {
      _commandWaiters.removeAt(0).complete(command);
    } else {
      _commands.add(command);
    }
  }

  Future<void> close() async {
    for (final waiter in _commandWaiters) {
      if (!waiter.isCompleted) {
        waiter.completeError(StateError('The peer closed before receiving the command.'));
      }
    }
    await _peer.close();
  }
}

final class _PeerConnection {
  _PeerConnection(this.socket);

  final Socket socket;
  final Completer<void> disconnected = Completer<void>();
}

final class _PeerCommand {
  const _PeerCommand(this._socket, this.arguments);

  final Socket _socket;
  final List<Uint8List> arguments;

  List<String> get textArguments => arguments.map(utf8.decode).toList(growable: false);

  void reply(String frame) => _socket.add(latin1.encode(frame));
  void destroy() => _socket.destroy();
}

Matcher throwsExpected(Matcher error) => throwsA(
  isA<EffectException<RunnelError>>().having(
    (e) => e.cause,
    'cause',
    isA<Expected<RunnelError>>().having((cause) => cause.error, 'error', error),
  ),
);
