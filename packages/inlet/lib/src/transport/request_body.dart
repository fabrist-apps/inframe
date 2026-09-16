import 'dart:async';
import 'dart:io';

/// Owns the physical upload subscription independently of application body views.
final class HttpRequestBody extends Stream<List<int>> {
  /// Subscribes immediately, pausing uploads until an application reads them.
  HttpRequestBody(HttpRequest request) {
    try {
      _subscription = request.listen(
        _add,
        onError: _addError,
        onDone: _complete,
        cancelOnError: false,
      );
      _pausePhysical();
      final hasNoBody =
          request.contentLength == 0 ||
          (request.contentLength < 0 && !request.headers.chunkedTransferEncoding);

      if (hasNoBody) {
        _resumePhysical();
        _completeCleanly = true;
      }
    } on Object catch (error, stackTrace) {
      _terminalError = error;
      _terminalStackTrace = stackTrace;
    }
  }

  StreamSubscription<List<int>>? _subscription;
  StreamController<List<int>>? _controller;
  Object? _terminalError;
  StackTrace? _terminalStackTrace;
  bool _listened = false;
  bool _completeCleanly = false;
  bool _paused = false;
  Future<void>? _finishFuture;

  /// Whether the upload finished without error or was known to have no body.
  bool get isComplete => _completeCleanly;

  /// Whether physical subscription cleanup has already been requested.
  bool get isFinishStarted => _finishFuture != null;

  /// Stops reading an unfinished upload while its response is sent.
  void pause() {
    if (!_completeCleanly) {
      _pausePhysical();
    }
  }

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    if (_listened) {
      throw StateError('The HTTP request body can be listened to only once.');
    }

    _listened = true;

    final controller = StreamController<List<int>>(sync: true);
    _controller = controller;
    controller
      ..onPause = _pausePhysical
      ..onResume = _resumePhysical
      ..onCancel = pause;
    final downstream = controller.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError ?? false,
    );

    final terminalError = _terminalError;

    if (terminalError != null) {
      controller.addError(terminalError, _terminalStackTrace);
      unawaited(controller.close());
    } else if (_completeCleanly) {
      unawaited(controller.close());
    } else {
      _resumePhysical();
    }

    return downstream;
  }

  void _add(List<int> chunk) {
    _controller?.add(chunk);
  }

  void _addError(Object error, StackTrace stackTrace) {
    if (_terminalError != null || _completeCleanly) {
      return;
    }

    _terminalError = error;
    _terminalStackTrace = stackTrace;
    final controller = _controller;

    if (controller != null) {
      controller.addError(error, stackTrace);
      unawaited(controller.close());
    }
  }

  void _complete() {
    if (_terminalError != null || _completeCleanly) {
      return;
    }

    _completeCleanly = true;
    final close = _controller?.close();

    if (close != null) {
      unawaited(close);
    }
  }

  void _pausePhysical() {
    if (_paused || _completeCleanly) {
      return;
    }

    _paused = true;
    _subscription?.pause();
  }

  void _resumePhysical() {
    if (!_paused || _completeCleanly) {
      return;
    }

    _paused = false;
    _subscription?.resume();
  }

  /// Cancels an unfinished upload once, sharing completion across callers.
  Future<void> finish() {
    final existing = _finishFuture;

    if (existing != null) {
      return existing;
    }

    if (_completeCleanly) {
      return _finishFuture = Future<void>.value();
    }

    final subscription = _subscription;

    return _finishFuture = subscription == null ? Future<void>.value() : subscription.cancel();
  }
}
