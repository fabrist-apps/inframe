part of 'provider_http_client.dart';

final class _SsePump<A> {
  _SsePump({
    required this.client,
    required this.url,
    required this.request,
    required this.headers,
    required this.lifetime,
    required this.protocol,
    required this.maxEventBytes,
    required this.maxStreamBytes,
    required this.release,
  }) : parser = _SseParser(maxEventBytes) {
    controller = StreamController<A>(
      sync: true,
      onListen: _start,
      onPause: _pause,
      onResume: _resume,
      onCancel: _cancel,
    );
  }

  final http.Client client;
  final Uri url;
  final ProviderHttpRequest request;
  final Map<String, String> headers;
  final _RequestLifetime lifetime;
  final SseProtocol<A> protocol;
  final int maxEventBytes;
  final int maxStreamBytes;
  final void Function() release;
  final _SseParser parser;
  late final StreamController<A> controller;
  StreamSubscription<List<int>>? _body;
  Iterator<A>? _pendingOutput;
  void Function()? _onOutputDone;
  void Function(Object error, StackTrace stackTrace)? _onOutputFailure;
  var _outputDrainScheduled = false;
  List<int>? _chunk;
  var _chunkIndex = 0;
  var _streamBytes = 0;
  var _paused = false;
  var _parserPaused = false;
  var _cancelled = false;
  var _finishing = false;
  var _released = false;

  Stream<A> get stream => controller.stream;

  Future<void> _start() async {
    unawaited(
      lifetime.cancellation.then((reason) {
        if (!_cancelled && !_finishing) {
          return _terminate(Interrupted(reason));
        }
      }),
    );
    final nativeRequest =
        http.AbortableRequest(request.method, url, abortTrigger: lifetime.abortTrigger)
          ..followRedirects = false
          ..headers.addAll(headers)
          ..headers.addAll(request.headers);
    if (request.body case final body?) {
      nativeRequest
        ..headers.putIfAbsent('content-type', () => 'application/json')
        ..body = body.encode();
    }
    final acquisition = client.send(nativeRequest);
    lifetime._acquisition = acquisition;
    try {
      final acquired = await lifetime.waitFor(acquisition);
      if (_cancelled || acquired is _WaitClosed<http.StreamedResponse>) return;
      final response = (acquired as _WaitValue<http.StreamedResponse>).value;
      lifetime._response = response;
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await _failHttp(response);
        return;
      }
      final metadata = ResponseMetadata(
        statusCode: response.statusCode,
        requestId: response.headers['x-request-id'] ?? response.headers['request-id'],
        headers: response.headers,
      );
      try {
        _queueProtocolOutput(
          protocol.start(metadata),
          onDone: () => _listen(response, paused: _paused),
        );
      } on Object catch (error, stackTrace) {
        await _terminate(_protocolCause(error, stackTrace));
      }
    } on Object catch (error, stackTrace) {
      if (_cancelled) return;
      final cause = switch (error) {
        AiError() || FormatException() => _protocolCause(error, stackTrace),
        _ => Expected<_SseSignal>(
          _SseExpected(
            TransportError(
              _safeForeignMessage(error),
              deliveryState: RequestDeliveryState.mayHaveReachedProvider,
            ),
          ),
        ),
      };
      await _terminate(cause);
    }
  }

  void _listen(http.StreamedResponse response, {bool paused = false}) {
    _body = response.stream.listen(
      _receive,
      onError: (Object error, StackTrace stackTrace) {
        unawaited(
          _terminate(
            Expected(
              _SseExpected(
                error is AiError
                    ? error
                    : TransportError(
                        _safeForeignMessage(error),
                        deliveryState: RequestDeliveryState.responseStarted,
                        partialOutput: protocol.partialOutput,
                      ),
              ),
            ),
          ),
        );
      },
      onDone: () => unawaited(_completeBody()),
      cancelOnError: false,
    );
    lifetime._bodySubscription = _body;
    if (paused) _body!.pause();
  }

  void _receive(List<int> bytes) {
    if (_cancelled || _finishing) return;
    _streamBytes += bytes.length;
    if (_streamBytes > maxStreamBytes) {
      unawaited(
        _terminate(
          Expected(
            _SseExpected(
              ResponseLimitError(
                'The streamed response exceeded the configured byte limit.',
                limit: maxStreamBytes,
                actual: _streamBytes,
                partialOutput: protocol.partialOutput,
              ),
            ),
          ),
        ),
      );
      return;
    }
    _chunk = List<int>.unmodifiable(bytes);
    _chunkIndex = 0;
    _drainChunk();
  }

  void _drainChunk() {
    final chunk = _chunk;
    if (chunk == null || _paused || _cancelled || _finishing) return;
    while (_chunkIndex < chunk.length && !_paused && !_finishing) {
      final SseEvent? event;
      try {
        event = parser.addByte(chunk[_chunkIndex++]);
      } on Object catch (error, stackTrace) {
        unawaited(_terminate(_protocolCause(error, stackTrace)));
        return;
      }
      if (event != null) {
        _pauseParser();
        try {
          _queueProtocolOutput(
            protocol.decode(event),
            onDone: _continueAfterEvent,
          );
        } on Object catch (error, stackTrace) {
          unawaited(_terminate(_protocolCause(error, stackTrace)));
        }
        return;
      }
    }
    if (_chunkIndex == chunk.length) {
      _chunk = null;
      _chunkIndex = 0;
      _resumeParser();
    }
  }

  void _continueAfterEvent() {
    if (protocol.isTerminal) {
      unawaited(_finishTransport());
      return;
    }
    scheduleMicrotask(_drainChunk);
  }

  Future<void> _completeBody() async {
    if (_cancelled || _finishing) return;
    try {
      final event = parser.close();
      if (event == null) {
        await _finishTransport();
      } else {
        _queueProtocolOutput(
          protocol.decode(event),
          onDone: () => unawaited(_finishTransport()),
        );
      }
    } on Object catch (error, stackTrace) {
      await _terminate(_protocolCause(error, stackTrace));
    }
  }

  Future<void> _finishTransport() async {
    if (_cancelled || _finishing) return;
    _finishing = true;
    try {
      await lifetime.cleanup();
    } on Object catch (error, stackTrace) {
      _release();
      _emitTerminal(Defect(error, stackTrace));
      return;
    }
    _release();
    try {
      _queueOutput(
        protocol.finish(),
        onDone: _closeOutput,
        onFailure: (error, stackTrace) {
          _emitTerminal(_protocolCause(error, stackTrace));
        },
      );
    } on Object catch (error, stackTrace) {
      _emitTerminal(_protocolCause(error, stackTrace));
    }
  }

  Future<void> _failHttp(http.StreamedResponse response) async {
    try {
      final bytes = await _readBody(response, lifetime, maxStreamBytes);
      final payload = JsonObject.parse(utf8.decode(bytes));
      await _terminate(
        Expected(
          _SseExpected(
            _providerError(
              response,
              payload,
              response.headers['x-request-id'] ?? response.headers['request-id'],
            ),
          ),
        ),
      );
    } on _ResponseTooLarge catch (error) {
      await _terminate(
        Expected(
          _SseExpected(
            ResponseLimitError(
              'The response exceeded the configured byte limit.',
              limit: maxStreamBytes,
              actual: error.actual,
              partialOutput: protocol.partialOutput,
            ),
          ),
        ),
      );
    } on FormatException catch (error, stackTrace) {
      await _terminate(_protocolCause(error, stackTrace));
    } on Object catch (error) {
      await _terminate(
        Expected(
          _SseExpected(
            error is AiError
                ? error
                : TransportError(
                    _safeForeignMessage(error),
                    deliveryState: RequestDeliveryState.responseStarted,
                    partialOutput: protocol.partialOutput,
                  ),
          ),
        ),
      );
    }
  }

  Future<void> _terminate(Cause<_SseSignal> original) async {
    if (_cancelled || _finishing) return;
    _finishing = true;
    Cause<_SseSignal>? cleanupFailure;
    try {
      await lifetime.cleanup();
    } on Object catch (error, stackTrace) {
      cleanupFailure = Defect(error, stackTrace);
    }
    _release();
    _emitTerminal(
      cleanupFailure == null ? original : Sequential([original, cleanupFailure]),
    );
  }

  void _queueProtocolOutput(Iterable<A> values, {required void Function() onDone}) {
    _queueOutput(
      values,
      onDone: onDone,
      onFailure: (error, stackTrace) {
        unawaited(_terminate(_protocolCause(error, stackTrace)));
      },
    );
  }

  void _queueOutput(
    Iterable<A> values, {
    required void Function() onDone,
    required void Function(Object error, StackTrace stackTrace) onFailure,
  }) {
    if (_pendingOutput != null) throw StateError('SSE protocol outputs overlapped.');
    _pendingOutput = values.iterator;
    _onOutputDone = onDone;
    _onOutputFailure = onFailure;
    _drainOutput();
  }

  void _drainOutput() {
    _outputDrainScheduled = false;
    final output = _pendingOutput;
    if (output == null || _paused || _cancelled || controller.isClosed) return;
    try {
      if (!output.moveNext()) {
        _pendingOutput = null;
        final done = _onOutputDone;
        final fail = _onOutputFailure;
        _onOutputDone = null;
        _onOutputFailure = null;
        try {
          done?.call();
        } on Object catch (error, stackTrace) {
          fail?.call(error, stackTrace);
        }
        return;
      }
      controller.add(output.current);
      _scheduleOutputDrain();
    } on Object catch (error, stackTrace) {
      _pendingOutput = null;
      final fail = _onOutputFailure;
      _onOutputDone = null;
      _onOutputFailure = null;
      fail?.call(error, stackTrace);
    }
  }

  void _scheduleOutputDrain() {
    if (_outputDrainScheduled) return;
    _outputDrainScheduled = true;
    scheduleMicrotask(_drainOutput);
  }

  void _pause() {
    _paused = true;
    _body?.pause();
  }

  void _pauseParser() {
    if (_parserPaused) return;
    _parserPaused = true;
    _body?.pause();
  }

  void _resumeParser() {
    if (!_parserPaused) return;
    _parserPaused = false;
    _body?.resume();
  }

  void _resume() {
    if (!_paused) return;
    final body = _body;
    _paused = false;
    body?.resume();
    _drainOutput();
  }

  Future<void> _cancel() async {
    if (_cancelled) return;
    _cancelled = true;
    _pendingOutput = null;
    _onOutputDone = null;
    _onOutputFailure = null;
    try {
      await lifetime.cancelAndCleanup('SSE consumer stopped');
    } finally {
      _release();
    }
  }

  Cause<_SseSignal> _protocolCause(Object error, StackTrace stackTrace) => switch (error) {
    ResponseLimitError() => Expected(
      _SseExpected(
        ResponseLimitError(
          error.message,
          limit: error.limit,
          actual: error.actual,
          partialOutput: error.partialOutput ?? protocol.partialOutput,
          remoteResourceId: error.remoteResourceId,
        ),
      ),
    ),
    ProtocolError() => Expected(
      _SseExpected(
        ProtocolError(
          error.message,
          partialOutput: error.partialOutput ?? protocol.partialOutput,
          remoteResourceId: error.remoteResourceId,
        ),
      ),
    ),
    AiError() => Expected(_SseExpected(error)),
    FormatException() => Expected(
      _SseExpected(
        ProtocolError(
          'The streamed response was malformed.',
          partialOutput: protocol.partialOutput,
        ),
      ),
    ),
    _ => Defect(error, stackTrace),
  };

  void _emitTerminal(Cause<_SseSignal> cause) {
    if (!controller.isClosed) controller.addError(_SseTerminal(cause));
    _closeOutput();
  }

  void _closeOutput() {
    if (!controller.isClosed) unawaited(controller.close());
  }

  void _release() {
    if (_released) return;
    _released = true;
    release();
  }
}

final class _SseParser {
  _SseParser(this.maxEventBytes);

  final int maxEventBytes;
  final List<int> _line = [];
  final List<String> _data = [];
  String? _event;
  String? _id;
  Duration? _retry;
  var _eventBytes = 0;
  var _sawData = false;

  SseEvent? addByte(int byte) {
    _eventBytes++;
    if (_eventBytes > maxEventBytes) {
      throw ResponseLimitError(
        'An SSE event exceeded the configured byte limit.',
        limit: maxEventBytes,
        actual: _eventBytes,
      );
    }
    if (byte != 0x0a) {
      _line.add(byte);
      return null;
    }
    return _finishLine();
  }

  SseEvent? close() {
    if (_line.isNotEmpty) _finishLine();
    return _dispatch();
  }

  SseEvent? _finishLine() {
    if (_line.isNotEmpty && _line.last == 0x0d) _line.removeLast();
    final line = utf8.decode(_line);
    _line.clear();
    if (line.isEmpty) return _dispatch();
    if (line.startsWith(':')) return null;
    final colon = line.indexOf(':');
    final field = colon < 0 ? line : line.substring(0, colon);
    var value = colon < 0 ? '' : line.substring(colon + 1);
    if (value.startsWith(' ')) value = value.substring(1);
    switch (field) {
      case 'data':
        _sawData = true;
        _data.add(value);
      case 'event':
        _event = value;
      case 'id':
        if (!value.contains('\u0000')) _id = value;
      case 'retry':
        final milliseconds = int.tryParse(value);
        if (milliseconds != null && milliseconds >= 0) {
          _retry = Duration(milliseconds: milliseconds);
        }
    }
    return null;
  }

  SseEvent? _dispatch() {
    final result = _sawData
        ? SseEvent(data: _data.join('\n'), event: _event, id: _id, retry: _retry)
        : null;
    _data.clear();
    _event = null;
    _retry = null;
    _sawData = false;
    _eventBytes = 0;
    return result;
  }
}
