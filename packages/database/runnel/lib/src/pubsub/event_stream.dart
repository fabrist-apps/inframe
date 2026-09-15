import 'dart:async';
import 'dart:collection';

import 'package:runnel/src/pubsub/events.dart';

/// Owns the only event queue, including events retained while paused.
final class PubSubEventStream extends Stream<PubSubEvent> {
  /// Creates a bounded queue with session-owned overflow and cancellation policy.
  PubSubEventStream({
    required this.maxBufferedEvents,
    required this.maxBufferedBytes,
    required this.onOverflow,
    required this.onCancel,
  });

  /// Maximum queued events before terminating the session.
  final int maxBufferedEvents;

  /// Maximum retained event bytes.
  final int maxBufferedBytes;

  /// Terminates the session when a queue limit is exceeded.
  final void Function(int limit) onOverflow;

  /// Releases the session after its listener cancels.
  final Future<void> Function() onCancel;
  final Queue<_BufferedEvent> _eventQueue = Queue();
  _PubSubEventSubscription? _listener;
  PubSubEvent? _terminalEvent;
  int _bufferedBytes = 0;
  bool _streamDone = false;

  /// Delivers immediately when possible, otherwise admits into the bounded queue.
  void add(PubSubEvent event) {
    final bytes = event.bufferedBytes;
    if (bytes > maxBufferedBytes) {
      onOverflow(maxBufferedBytes);
      return;
    }
    final listener = _listener;
    if (listener != null && !listener.isPaused && _eventQueue.isEmpty) {
      listener._add(event);
      return;
    }
    if (_eventQueue.length == maxBufferedEvents) {
      onOverflow(maxBufferedEvents);
      return;
    }
    if (_bufferedBytes + bytes > maxBufferedBytes) {
      onOverflow(maxBufferedBytes);
      return;
    }
    _eventQueue.add(_BufferedEvent(event, bytes));
    _bufferedBytes += bytes;
  }

  /// Suppresses undelivered messages for locally unsubscribed channels.
  void discardMessages(Set<String> channels) {
    if (_eventQueue.isEmpty) return;
    final retained = Queue<_BufferedEvent>();
    var retainedBytes = 0;
    for (final buffered in _eventQueue) {
      if (buffered.event case PubSubMessage(:final channel) when channels.contains(channel)) {
        continue;
      }
      retained.add(buffered);
      retainedBytes += buffered.bytes;
    }
    _eventQueue
      ..clear()
      ..addAll(retained);
    _bufferedBytes = retainedBytes;
  }

  @override
  StreamSubscription<PubSubEvent> listen(
    void Function(PubSubEvent)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    if (_listener != null) throw StateError('Pub/Sub events support exactly one listener.');
    final listener = _PubSubEventSubscription(
      this,
      onData: onData,
      onDone: onDone,
    );
    _listener = listener;
    scheduleMicrotask(_drainEvents);
    return listener;
  }

  void _drainEvents() {
    final listener = _listener;
    if (listener == null || listener.isPaused || listener._cancelled) return;
    while (_eventQueue.isNotEmpty && !listener.isPaused && !listener._cancelled) {
      final buffered = _eventQueue.removeFirst();
      _bufferedBytes -= buffered.bytes;
      listener._add(buffered.event);
    }
    if (listener.isPaused || listener._cancelled) return;
    final terminal = _terminalEvent;
    if (terminal != null) {
      _terminalEvent = null;
      listener._add(terminal);
    }
    if (_streamDone) listener._done();
  }

  Future<void> _cancelListener() {
    _eventQueue.clear();
    _bufferedBytes = 0;
    _terminalEvent = null;
    _streamDone = true;
    return onCancel();
  }

  /// Ends delivery after queued events and an optional terminal event.
  void finish({bool discard = false, PubSubEvent? terminal}) {
    if (discard) {
      _eventQueue.clear();
      _bufferedBytes = 0;
    }
    _terminalEvent = terminal;
    _streamDone = true;
    _drainEvents();
  }
}

final class _BufferedEvent {
  const _BufferedEvent(this.event, this.bytes);

  final PubSubEvent event;
  final int bytes;
}

final class _PubSubEventSubscription implements StreamSubscription<PubSubEvent> {
  _PubSubEventSubscription(
    this._stream, {
    required this._onData,
    required this._onDone,
  }) : _zone = Zone.current;

  final PubSubEventStream _stream;
  final Zone _zone;
  final Completer<void> _doneCompleter = Completer<void>();
  void Function(PubSubEvent)? _onData;
  void Function()? _onDone;
  int _pauseCount = 0;
  bool _cancelled = false;
  bool _doneSent = false;

  @override
  bool get isPaused => _pauseCount > 0;

  void _add(PubSubEvent event) {
    if (_cancelled || _doneSent) return;
    final onData = _onData;
    if (onData != null) _zone.runUnaryGuarded(onData, event);
  }

  void _done() {
    if (_cancelled || _doneSent) return;
    _doneSent = true;
    final onDone = _onDone;
    if (onDone != null) _zone.runGuarded(onDone);
    if (!_doneCompleter.isCompleted) _doneCompleter.complete();
  }

  @override
  Future<void> cancel() {
    if (_cancelled) return Future.value();
    _cancelled = true;
    if (!_doneCompleter.isCompleted) _doneCompleter.complete();
    return _stream._cancelListener();
  }

  @override
  void onData(void Function(PubSubEvent data)? handleData) => _onData = handleData;

  @override
  void onDone(void Function()? handleDone) => _onDone = handleDone;

  @override
  void onError(Function? handleError) {}

  @override
  void pause([Future<void>? resumeSignal]) {
    if (_cancelled || _doneSent) return;
    _pauseCount++;
    if (resumeSignal != null) unawaited(resumeSignal.whenComplete(resume));
  }

  @override
  void resume() {
    if (_pauseCount == 0) return;
    _pauseCount--;
    if (_pauseCount == 0) _stream._drainEvents();
  }

  @override
  Future<E> asFuture<E>([E? futureValue]) async {
    await _doneCompleter.future;
    return futureValue as E;
  }
}
