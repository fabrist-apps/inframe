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
      lifetime.abortTrigger.then((_) {
        if (!_cancelled && !_finishing) {
          return _fail(const ClientClosedError(), StackTrace.current);
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
    lifetime.trackAcquisition(acquisition);
    try {
      final acquired = await lifetime.waitFor(acquisition);
      if (_cancelled || acquired is _WaitClosed<http.StreamedResponse>) return;
      final response = (acquired as _WaitValue<http.StreamedResponse>).value;
      lifetime.trackResponse(response);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await _failHttp(response);
        return;
      }
      final metadata = ResponseMetadata(
        statusCode: response.statusCode,
        requestId: response.headers['x-request-id'] ?? response.headers['request-id'],
        headers: response.headers,
      );
      final emitted = _emitAll(protocol.start(metadata));
      if (emitted) {
        scheduleMicrotask(() => _listen(response, paused: _paused));
      } else {
        _listen(response, paused: _paused);
      }
    } on Object catch (error, stackTrace) {
      if (_cancelled) return;
      await _fail(
        error is AiError
            ? error
            : TransportError(
                _safeForeignMessage(error),
                deliveryState: RequestDeliveryState.mayHaveReachedProvider,
              ),
        stackTrace,
      );
    }
  }

  void _listen(http.StreamedResponse response, {bool paused = false}) {
    _body = response.stream.listen(
      _receive,
      onError: (Object error, StackTrace stackTrace) {
        unawaited(
          _fail(
            error is AiError
                ? error
                : TransportError(
                    _safeForeignMessage(error),
                    deliveryState: RequestDeliveryState.responseStarted,
                    partialOutput: protocol.partialOutput,
                  ),
            stackTrace,
          ),
        );
      },
      onDone: () => unawaited(_completeBody()),
      cancelOnError: false,
    );
    lifetime.trackBody(_body!);
    if (paused) _body!.pause();
  }

  void _receive(List<int> bytes) {
    if (_cancelled || _finishing) return;
    _streamBytes += bytes.length;
    if (_streamBytes > maxStreamBytes) {
      unawaited(
        _fail(
          ResponseLimitError(
            'The streamed response exceeded the configured byte limit.',
            limit: maxStreamBytes,
            actual: _streamBytes,
            partialOutput: protocol.partialOutput,
          ),
          StackTrace.current,
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
    try {
      while (_chunkIndex < chunk.length && !_paused && !_finishing) {
        final event = parser.addByte(chunk[_chunkIndex++]);
        if (event != null) {
          final emitted = _emitAll(protocol.decode(event));
          if (protocol.isTerminal) {
            unawaited(_finishTransport());
          } else if (emitted && _chunkIndex < chunk.length) {
            _pauseParser();
            scheduleMicrotask(() {
              _drainChunk();
              if (_chunk == null || _paused || _finishing) _resumeParser();
            });
            return;
          }
        }
      }
      if (_chunkIndex == chunk.length) {
        _chunk = null;
        _chunkIndex = 0;
      }
    } on Object catch (error, stackTrace) {
      unawaited(_fail(_protocolError(error), stackTrace));
    }
  }

  Future<void> _completeBody() async {
    if (_cancelled || _finishing) return;
    try {
      final event = parser.close();
      if (event != null) _emitAll(protocol.decode(event));
      await _finishTransport();
    } on Object catch (error, stackTrace) {
      await _fail(_protocolError(error), stackTrace);
    }
  }

  Future<void> _finishTransport() async {
    if (_cancelled || _finishing) return;
    _finishing = true;
    try {
      await lifetime.cleanup();
      _emitAll(protocol.finish());
      await controller.close();
    } on Object catch (error, stackTrace) {
      if (!controller.isClosed) controller.addError(_protocolError(error), stackTrace);
      if (!controller.isClosed) await controller.close();
    } finally {
      _release();
    }
  }

  Future<void> _failHttp(http.StreamedResponse response) async {
    try {
      final bytes = await _readBody(response, lifetime, maxStreamBytes);
      final payload = JsonObject.parse(utf8.decode(bytes));
      await _fail(
        _providerError(
          response,
          payload,
          response.headers['x-request-id'] ?? response.headers['request-id'],
        ),
        StackTrace.current,
      );
    } on _ResponseTooLarge catch (error, stackTrace) {
      await _fail(
        ResponseLimitError(
          'The response exceeded the configured byte limit.',
          limit: maxStreamBytes,
          actual: error.actual,
          partialOutput: protocol.partialOutput,
        ),
        stackTrace,
      );
    } on Object catch (error, stackTrace) {
      await _fail(_protocolError(error), stackTrace);
    }
  }

  Future<void> _fail(AiError error, StackTrace stackTrace) async {
    if (_cancelled || _finishing) return;
    _finishing = true;
    if (!controller.isClosed) controller.addError(error, stackTrace);
    if (!controller.isClosed) await controller.close();
  }

  bool _emitAll(Iterable<A> values) {
    var emitted = false;
    for (final value in values) {
      if (_cancelled || controller.isClosed) return emitted;
      emitted = true;
      controller.add(value);
    }
    return emitted;
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
    _paused = false;
    _drainChunk();
    if (!_paused && !_finishing) _body?.resume();
  }

  Future<void> _cancel() async {
    if (_cancelled) return;
    _cancelled = true;
    try {
      await lifetime.cancelAndCleanup('SSE consumer stopped');
    } finally {
      _release();
    }
  }

  AiError _protocolError(Object error) => switch (error) {
    ResponseLimitError() => ResponseLimitError(
      error.message,
      limit: error.limit,
      actual: error.actual,
      partialOutput: error.partialOutput ?? protocol.partialOutput,
      remoteResourceId: error.remoteResourceId,
    ),
    ProtocolError() => ProtocolError(
      error.message,
      partialOutput: error.partialOutput ?? protocol.partialOutput,
      remoteResourceId: error.remoteResourceId,
    ),
    AiError() => error,
    FormatException() => ProtocolError(
      'The streamed response was malformed: ${error.message}',
      partialOutput: protocol.partialOutput,
    ),
    _ => ProtocolError(
      'The streamed response could not be decoded.',
      partialOutput: protocol.partialOutput,
    ),
  };

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
