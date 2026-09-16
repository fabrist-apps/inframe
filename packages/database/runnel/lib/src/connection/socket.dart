// Package-internal connection ownership shared by physical transports.

import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:runnel/src/connection/connection_attempt.dart';
import 'package:runnel/src/connection/legacy_errors.dart';

/// Byte-stream socket operations shared by plain and raw TLS transports.
abstract class ConnectionSocket extends Stream<Uint8List> {
  /// Queues [bytes] for transmission.
  void add(List<int> bytes);

  /// Releases the socket immediately without waiting for queued writes.
  void destroy();

  /// Closes the socket after its queued writes have been handled.
  Future<void> close();
}

/// Opens an owned plain or TLS socket within one absolute [timeout].
Future<ConnectionSocket> openSocket({
  required String host,
  required int port,
  required bool tls,
  required SecurityContext? securityContext,
  required Duration timeout,
  ConnectionAttempt? attempt,
}) {
  final elapsed = Stopwatch()..start();
  return tls
      ? _openSecureSocket(host, port, securityContext, timeout, elapsed, attempt)
      : _openPlainSocket(host, port, timeout, elapsed, attempt);
}

Future<ConnectionSocket> _openPlainSocket(
  String host,
  int port,
  Duration timeout,
  Stopwatch elapsed,
  ConnectionAttempt? attempt,
) async {
  final task = await Socket.startConnect(host, port);
  if (!(attempt?.attachConnect(task.cancel) ?? true)) {
    await _discardTaskResult(task.socket, (socket) => socket.destroy());
    throw const RedisClosedException(message: 'The connection attempt was cancelled.');
  }
  try {
    final socket = await _awaitTask(
      task,
      timeout,
      elapsed,
      (socket) => socket.destroy(),
    );
    final connection = _IoConnectionSocket(socket);
    if (!(attempt?.attachResource(() async => connection.destroy()) ?? true)) {
      connection.destroy();
      throw const RedisClosedException(message: 'The connection attempt was cancelled.');
    }
    return connection;
  } finally {
    attempt?.detachConnect(task.cancel);
  }
}

Future<ConnectionSocket> _openSecureSocket(
  String host,
  int port,
  SecurityContext? securityContext,
  Duration timeout,
  Stopwatch elapsed,
  ConnectionAttempt? attempt,
) async {
  final task = await RawSocket.startConnect(host, port);
  if (!(attempt?.attachConnect(task.cancel) ?? true)) {
    await _discardTaskResult(task.socket, (socket) => unawaited(socket.close()));
    throw const RedisClosedException(message: 'The connection attempt was cancelled.');
  }
  late final RawSocket plainSocket;
  try {
    plainSocket = await _awaitTask(
      task,
      timeout,
      elapsed,
      (socket) => unawaited(socket.close()),
    );
  } finally {
    attempt?.detachConnect(task.cancel);
  }

  var abandoned = false;
  Future<void> closeHandshake() async {
    abandoned = true;
    await plainSocket.close();
  }

  if (!(attempt?.attachResource(closeHandshake) ?? true)) {
    await closeHandshake();
    throw const RedisClosedException(message: 'The connection attempt was cancelled.');
  }
  final securing = RawSecureSocket.secure(
    plainSocket,
    host: host,
    context: securityContext,
  );
  unawaited(
    securing.then<void>(
      (socket) {
        if (abandoned) unawaited(socket.close());
      },
      onError: (_, _) {},
    ),
  );
  try {
    final socket = await securing.timeout(
      _remaining(timeout, elapsed),
      onTimeout: () {
        unawaited(closeHandshake());
        throw TimeoutException('The socket connection deadline expired.');
      },
    );
    final connection = _RawSecureConnectionSocket(socket);
    if (abandoned || !(attempt?.attachResource(() async => connection.destroy()) ?? true)) {
      connection.destroy();
      throw const RedisClosedException(message: 'The connection attempt was cancelled.');
    }
    return connection;
  } on Object {
    await closeHandshake();
    rethrow;
  }
}

Duration _remaining(Duration timeout, Stopwatch elapsed) {
  final remaining = timeout - elapsed.elapsed;
  if (remaining <= Duration.zero) {
    throw TimeoutException('The socket connection deadline expired.');
  }
  return remaining;
}

Future<T> _awaitTask<T>(
  ConnectionTask<T> task,
  Duration timeout,
  Stopwatch elapsed,
  void Function(T resource) dispose,
) async {
  var abandoned = false;
  unawaited(
    task.socket.then<void>(
      (resource) {
        if (abandoned) dispose(resource);
      },
      onError: (_, _) {},
    ),
  );
  try {
    return await task.socket.timeout(
      _remaining(timeout, elapsed),
      onTimeout: () {
        abandoned = true;
        task.cancel();
        throw TimeoutException('The socket connection deadline expired.');
      },
    );
  } on TimeoutException {
    abandoned = true;
    task.cancel();
    rethrow;
  }
}

Future<void> _discardTaskResult<T>(
  Future<T> result,
  void Function(T resource) dispose,
) async {
  try {
    dispose(await result);
  } on Object {
    // Cancellation is represented to the caller by RedisClosedException.
  }
}

final class _IoConnectionSocket extends ConnectionSocket {
  _IoConnectionSocket(this._socket);

  final Socket _socket;

  @override
  void add(List<int> bytes) => _socket.add(bytes);

  @override
  Future<void> close() => _socket.close();

  @override
  void destroy() => _socket.destroy();

  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _socket.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
}

final class _RawSecureConnectionSocket extends ConnectionSocket {
  _RawSecureConnectionSocket(this._socket) {
    _subscription = _socket.listen(
      _onEvent,
      onError: _reportError,
      onDone: _closeController,
      cancelOnError: true,
    );
  }

  final RawSecureSocket _socket;
  final StreamController<Uint8List> _controller = StreamController(sync: true);
  final Queue<Uint8List> _writes = Queue();
  late final StreamSubscription<RawSocketEvent> _subscription;
  var _writeOffset = 0;
  var _closed = false;

  @override
  void add(List<int> bytes) {
    if (_closed) throw StateError('The socket is closed.');
    _writes.add(Uint8List.fromList(bytes));
    _drainWrites();
  }

  void _onEvent(RawSocketEvent event) {
    if (_closed) return;
    if (event == RawSocketEvent.read) {
      while (!_closed) {
        try {
          final bytes = _socket.read();
          if (bytes == null) return;
          _controller.add(bytes);
        } on Object catch (error, stackTrace) {
          _reportError(error, stackTrace);
          return;
        }
      }
    } else if (event == RawSocketEvent.write) {
      _drainWrites();
    } else if (event == RawSocketEvent.readClosed || event == RawSocketEvent.closed) {
      _closeController();
    }
  }

  void _drainWrites() {
    try {
      while (!_closed && _writes.isNotEmpty) {
        final bytes = _writes.first;
        _writeOffset += _socket.write(bytes, _writeOffset);
        if (_writeOffset != bytes.length) {
          _socket.writeEventsEnabled = true;
          return;
        }
        _writes.removeFirst();
        _writeOffset = 0;
      }
    } on Object catch (error, stackTrace) {
      _reportError(error, stackTrace);
    }
  }

  void _reportError(Object error, StackTrace stackTrace) {
    if (!_closed && !_controller.isClosed) _controller.addError(error, stackTrace);
  }

  void _closeController() {
    if (!_controller.isClosed) unawaited(_controller.close());
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _socket.close();
    await _subscription.cancel();
    await _controller.close();
  }

  @override
  void destroy() {
    if (_closed) return;
    _closed = true;
    _socket.shutdown(SocketDirection.both);
    unawaited(_socket.close());
    unawaited(_subscription.cancel());
    _closeController();
  }

  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _controller.stream.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
}
