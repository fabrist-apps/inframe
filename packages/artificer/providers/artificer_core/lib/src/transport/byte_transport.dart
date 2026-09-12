part of 'provider_http_client.dart';

final class _BytePump {
  _BytePump({
    required this.client,
    required this.url,
    required this.request,
    required this.headers,
    required this.lifetime,
    required this.maxResponseBytes,
    required this.release,
  }) {
    controller = StreamController<List<int>>(
      sync: true,
      onListen: _start,
      onPause: () => _body?.pause(),
      onResume: () => _body?.resume(),
      onCancel: _cancel,
    );
  }

  final http.Client client;
  final Uri url;
  final ProviderHttpRequest request;
  final Map<String, String> headers;
  final _RequestLifetime lifetime;
  final int maxResponseBytes;
  final void Function() release;
  late final StreamController<List<int>> controller;
  StreamSubscription<List<int>>? _body;
  var _receivedBytes = 0;
  var _cancelled = false;
  var _finishing = false;
  var _released = false;

  Stream<List<int>> get stream => controller.stream;

  Future<void> _start() async {
    unawaited(
      lifetime.cancellation.then((reason) {
        if (!_cancelled && !_finishing) return _terminate(Interrupted(reason));
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
      _listen(response);
    } on Object catch (error) {
      if (_cancelled) return;
      await _terminate(
        switch (error) {
          AiError() => Expected(_SseExpected(error)),
          _ => Expected(
            _SseExpected(
              TransportError(
                _safeForeignMessage(error),
                deliveryState: RequestDeliveryState.mayHaveReachedProvider,
              ),
            ),
          ),
        },
      );
    }
  }

  void _listen(http.StreamedResponse response) {
    _body = response.stream.listen(
      _receive,
      onError: (Object error, StackTrace stackTrace) => unawaited(
        _terminate(
          Expected(
            _SseExpected(
              error is AiError
                  ? error
                  : TransportError(
                      _safeForeignMessage(error),
                      deliveryState: RequestDeliveryState.responseStarted,
                    ),
            ),
          ),
        ),
      ),
      onDone: () => unawaited(_finish()),
      cancelOnError: false,
    );
    lifetime._bodySubscription = _body;
  }

  void _receive(List<int> bytes) {
    if (_cancelled || _finishing) return;
    _receivedBytes += bytes.length;
    if (_receivedBytes > maxResponseBytes) {
      unawaited(
        _terminate(
          Expected(
            _SseExpected(
              ResponseLimitError(
                'The streamed response exceeded the configured byte limit.',
                limit: maxResponseBytes,
                actual: _receivedBytes,
              ),
            ),
          ),
        ),
      );
      return;
    }
    controller.add(Uint8List.fromList(bytes).asUnmodifiableView());
  }

  Future<void> _finish() async {
    if (_cancelled || _finishing) return;
    _finishing = true;
    try {
      await lifetime.cleanup();
      _release();
      if (!controller.isClosed) await controller.close();
    } on Object catch (error, stackTrace) {
      _release();
      if (!controller.isClosed) {
        controller.addError(_SseTerminal(Defect(error, stackTrace)));
        await controller.close();
      }
    }
  }

  Future<void> _failHttp(http.StreamedResponse response) async {
    try {
      final bytes = await _readBody(response, lifetime, maxResponseBytes);
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
              limit: maxResponseBytes,
              actual: error.actual,
            ),
          ),
        ),
      );
    } on FormatException {
      await _terminate(
        const Expected(
          _SseExpected(ProtocolError('The error response was not a JSON object.')),
        ),
      );
    } on Object catch (error) {
      await _terminate(
        Expected(
          _SseExpected(
            error is AiError
                ? error
                : TransportError(
                    _safeForeignMessage(error),
                    deliveryState: RequestDeliveryState.responseStarted,
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
    if (!controller.isClosed) {
      controller.addError(
        _SseTerminal(
          cleanupFailure == null ? original : Sequential([original, cleanupFailure]),
        ),
      );
      await controller.close();
    }
  }

  Future<void> _cancel() async {
    if (_cancelled) return;
    _cancelled = true;
    try {
      await lifetime.cancelAndCleanup('byte-stream consumer stopped');
    } finally {
      _release();
    }
  }

  void _release() {
    if (_released) return;
    _released = true;
    release();
  }
}
