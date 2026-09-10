part of 'inlet.dart';

const int _defaultBodyLimit = 1024 * 1024;

final class _BodyLimitFailure implements Exception {
  const _BodyLimitFailure(this.maxBytes);

  final int maxBytes;
}

/// Owns the one permitted consumption mode and cleanup of a byte stream.
///
/// Reading [stream] does not choose a mode. The first buffer call or stream
/// subscription synchronously chooses buffering or raw delivery. That choice
/// remains exclusive even after delivery finishes. Closing is terminal and
/// releases the buffer or cancels the active source without subscribing to an
/// untouched source.
final class _Body {
  _Body(Stream<List<int>> source) : _source = source;

  factory _Body.bytes(List<int> bytes) {
    final copied = _copyAndValidateBytes(bytes);
    return _Body(Stream.value(copied)).._knownLength = copied.length;
  }

  final Stream<List<int>> _source;
  late final Stream<List<int>> _stream = _BodyStream(this);

  _BodyState _state = const _UntouchedBody();
  int? _knownLength;
  Future<void>? _closeFuture;

  int? get knownLength => _knownLength;

  Stream<List<int>> get stream => _stream;

  Future<List<int>> bytes({int maxBytes = _defaultBodyLimit}) async {
    _validateMaxBytes(maxBytes);
    final buffering = _claimBuffering(maxBytes);
    await buffering.settled.future;

    if (_state is _ClosedBody) {
      throw StateError('The body was closed while it was being read.');
    }
    final failure = buffering.failure;
    if (failure != null) {
      Error.throwWithStackTrace(failure, buffering.failureStackTrace!);
    }
    final cached = buffering.cache;
    if (cached == null) {
      throw StateError('The body was closed while it was being read.');
    }
    _checkLimit(cached.length, maxBytes);
    return Uint8List.fromList(cached);
  }

  _BufferingBody _claimBuffering(int maxBytes) {
    switch (_state) {
      case _UntouchedBody():
        final buffering = _BufferingBody(maxBytes);
        _state = buffering;
        _startBuffering(buffering);
        return buffering;
      case final _BufferingBody buffering:
        return buffering;
      case _RawBody():
        throw StateError('The body is already being streamed.');
      case _ClosedBody():
        throw StateError('The body is closed.');
    }
  }

  void _startBuffering(_BufferingBody buffering) {
    try {
      final subscription = _source.listen(
        (chunk) => _bufferChunk(buffering, chunk),
        onError: (Object error, StackTrace stackTrace) {
          _failBuffering(buffering, error, stackTrace);
        },
        onDone: () => _finishBuffering(buffering),
        cancelOnError: false,
      );
      buffering.source.attach(subscription);
    } on Object catch (error, stackTrace) {
      buffering.source.cannotAttach();
      _failBuffering(buffering, error, stackTrace);
    }
  }

  void _bufferChunk(_BufferingBody buffering, List<int> chunk) {
    if (!identical(_state, buffering) || buffering.isSettled) {
      return;
    }
    if (chunk.length > buffering.maxBytes - buffering.builder.length) {
      _failBuffering(
        buffering,
        _BodyLimitFailure(buffering.maxBytes),
        StackTrace.current,
      );
      return;
    }

    try {
      buffering.builder.add(_copyAndValidateBytes(chunk));
    } on Object catch (error, stackTrace) {
      _failBuffering(buffering, error, stackTrace);
    }
  }

  void _finishBuffering(_BufferingBody buffering) {
    buffering.source.finish();
    if (!identical(_state, buffering) || buffering.isSettled) {
      return;
    }
    final cache = buffering.builder.takeBytes();
    buffering
      ..cache = cache
      ..isSettled = true
      ..settled.complete();
    _knownLength = cache.length;
  }

  void _failBuffering(
    _BufferingBody buffering,
    Object error,
    StackTrace stackTrace,
  ) {
    if (!identical(_state, buffering) || buffering.isSettled) {
      return;
    }
    buffering
      ..builder.clear()
      ..failure = error
      ..failureStackTrace = stackTrace
      ..isSettled = true
      ..settled.complete();
    buffering.source.cancel().ignore();
  }

  StreamSubscription<List<int>> _listenRaw(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool cancelOnError = false,
  }) {
    if (_state is! _UntouchedBody) {
      throw StateError(switch (_state) {
        _ClosedBody() => 'The body is closed.',
        _BufferingBody() => 'The body is already being buffered.',
        _RawBody() => 'The body is already being streamed.',
        _UntouchedBody() => throw StateError('Unreachable body state.'),
      });
    }

    final controller = StreamController<List<int>>(sync: true);
    final raw = _RawBody(controller);
    _state = raw;

    controller
      ..onPause = raw.source.pause
      ..onResume = raw.source.resume
      ..onCancel = raw.source.cancel;

    final downstream = controller.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
    raw.downstream = downstream;

    try {
      final upstream = _source.listen(
        (chunk) => _forwardChunk(raw, chunk),
        onError: (Object error, StackTrace stackTrace) {
          _failRaw(raw, error, stackTrace);
        },
        onDone: () => _finishRaw(raw),
        cancelOnError: false,
      );
      raw.source.attach(upstream);
    } on Object catch (error, stackTrace) {
      raw.source.cannotAttach();
      _failRaw(raw, error, stackTrace);
    }

    return downstream;
  }

  void _forwardChunk(_RawBody raw, List<int> chunk) {
    if (!identical(_state, raw) || raw.isSettled) {
      return;
    }
    try {
      raw.controller.add(_copyAndValidateBytes(chunk));
    } on Object catch (error, stackTrace) {
      _failRaw(raw, error, stackTrace);
    }
  }

  void _finishRaw(_RawBody raw) {
    raw.source.finish();
    if (!identical(_state, raw) || raw.isSettled) {
      return;
    }
    raw.isSettled = true;
    raw.controller.close().ignore();
  }

  void _failRaw(_RawBody raw, Object error, StackTrace stackTrace) {
    if (!identical(_state, raw) || raw.isSettled) {
      return;
    }
    raw.isSettled = true;
    raw.controller
      ..addError(error, stackTrace)
      ..close().ignore();
    raw.source.cancel().ignore();
  }

  Future<void> close() {
    final existing = _closeFuture;
    if (existing != null) {
      return existing;
    }

    final closed = Completer<void>();
    _closeFuture = closed.future;
    final previous = _state;
    _state = const _ClosedBody();

    final Future<void> cleanup;
    switch (previous) {
      case _UntouchedBody():
        cleanup = Future<void>.value();
      case final _BufferingBody buffering:
        buffering
          ..builder.clear()
          ..cache = null;
        if (!buffering.isSettled) {
          buffering
            ..failure = StateError('The body was closed while it was being read.')
            ..failureStackTrace = StackTrace.current
            ..isSettled = true
            ..settled.complete();
        }
        cleanup = buffering.source.cancel();
      case final _RawBody raw:
        final downstream = raw.downstream;
        cleanup = downstream == null ? raw.source.cancel() : downstream.cancel();
      case _ClosedBody():
        cleanup = Future<void>.value();
    }

    unawaited(cleanup.then(closed.complete, onError: closed.completeError));
    return closed.future;
  }
}

sealed class _BodyState {
  const _BodyState();
}

final class _UntouchedBody extends _BodyState {
  const _UntouchedBody();
}

final class _BufferingBody extends _BodyState {
  _BufferingBody(this.maxBytes);

  final int maxBytes;
  final BytesBuilder builder = BytesBuilder();
  final Completer<void> settled = Completer<void>.sync();
  final _TrackedSubscription<List<int>> source = _TrackedSubscription<List<int>>();

  bool isSettled = false;
  Uint8List? cache;
  Object? failure;
  StackTrace? failureStackTrace;
}

final class _RawBody extends _BodyState {
  _RawBody(this.controller);

  final StreamController<List<int>> controller;
  final _TrackedSubscription<List<int>> source = _TrackedSubscription<List<int>>();

  StreamSubscription<List<int>>? downstream;
  bool isSettled = false;
}

final class _ClosedBody extends _BodyState {
  const _ClosedBody();
}

final class _BodyStream extends Stream<List<int>> {
  const _BodyStream(this._body);

  final _Body _body;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _body._listenRaw(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError ?? false,
  );
}

/// Makes cancellation safe before a synchronously-callbacking stream's
/// [Stream.listen] invocation has returned its subscription.
final class _TrackedSubscription<T> {
  StreamSubscription<T>? _subscription;
  Completer<void>? _cancellation;
  bool _cannotAttach = false;
  bool _finished = false;
  bool _paused = false;

  void attach(StreamSubscription<T> subscription) {
    if (_finished || _cannotAttach) {
      subscription.cancel().ignore();
      _completeCancellation();
      return;
    }
    _subscription = subscription;
    if (_paused) {
      subscription.pause();
    }
    if (_cancellation != null) {
      _startCancellation(subscription);
    }
  }

  void cannotAttach() {
    _cannotAttach = true;
    _completeCancellation();
  }

  void finish() {
    _finished = true;
    _subscription = null;
    _completeCancellation();
  }

  void pause() {
    if (_paused || _finished) {
      return;
    }
    _paused = true;
    _subscription?.pause();
  }

  void resume() {
    if (!_paused || _finished) {
      return;
    }
    _paused = false;
    _subscription?.resume();
  }

  Future<void> cancel() {
    final existing = _cancellation;
    if (existing != null) {
      return existing.future;
    }
    final cancellation = Completer<void>();
    _cancellation = cancellation;
    final subscription = _subscription;
    if (subscription != null) {
      _startCancellation(subscription);
    } else if (_finished || _cannotAttach) {
      cancellation.complete();
    }
    return cancellation.future;
  }

  void _startCancellation(StreamSubscription<T> subscription) {
    _subscription = null;
    _finished = true;
    Future<void> cancellation;
    try {
      cancellation = subscription.cancel();
    } on Object catch (error, stackTrace) {
      _cancellation!.completeError(error, stackTrace);
      return;
    }
    unawaited(
      cancellation.then(_cancellation!.complete, onError: _cancellation!.completeError),
    );
  }

  void _completeCancellation() {
    final cancellation = _cancellation;
    if (cancellation != null && !cancellation.isCompleted) {
      cancellation.complete();
    }
  }
}

Uint8List _copyAndValidateBytes(List<int> bytes) {
  for (final byte in bytes) {
    if (byte < 0 || byte > 255) {
      throw ArgumentError('Body chunks must contain values from 0 through 255.');
    }
  }
  return Uint8List.fromList(bytes);
}

void _validateMaxBytes(int maxBytes) {
  if (maxBytes < 0) {
    throw ArgumentError.value(maxBytes, 'maxBytes', 'must not be negative');
  }
}

void _checkLimit(int byteCount, int maxBytes) {
  if (byteCount > maxBytes) {
    throw _BodyLimitFailure(maxBytes);
  }
}
