import 'dart:async';
import 'dart:collection';

import 'package:conflux/option.dart';
import 'package:runnel/src/errors.dart';
import 'package:runnel/src/pubsub/events.dart';

/// Owns the sole bounded hot event queue; a consumer removes events on demand.
final class PubSubEventQueue {
  /// Creates the session-owned queue with synchronous overflow notification.
  PubSubEventQueue({
    required this.maxBufferedEvents,
    required this.maxBufferedBytes,
    required this.onOverflow,
  });

  /// Maximum count of retained normal events.
  final int maxBufferedEvents;

  /// Maximum byte count of retained normal events.
  final int maxBufferedBytes;

  /// Terminates the owner when admission exceeds a configured bound.
  final void Function(int limit) onOverflow;
  final Queue<PubSubEvent> _events = Queue();
  Completer<void>? _available;
  PubSubInterrupted? _terminal;
  RunnelError? _failure;
  int _bytes = 0;
  bool _done = false;

  /// Admits an event and wakes a pending pull without creating another buffer.
  void add(PubSubEvent event) {
    if (_done) return;
    final bytes = event.bufferedBytes;
    if (_events.length >= maxBufferedEvents) return onOverflow(maxBufferedEvents);
    if (_bytes + bytes > maxBufferedBytes) return onOverflow(maxBufferedBytes);
    _events.add(event);
    _bytes += bytes;
    _wake();
  }

  /// Waits for and removes one event, then exposes terminal failure or completion.
  Future<Option<PubSubEvent>> next() async {
    while (_events.isEmpty && _terminal == null && !_done) {
      await (_available ??= Completer<void>()).future;
    }
    if (_events.isNotEmpty) {
      final event = _events.removeFirst();
      _bytes -= event.bufferedBytes;
      return Some(event);
    }
    final terminal = _terminal;
    if (terminal != null) {
      _terminal = null;
      return Some(terminal);
    }
    final failure = _failure;
    if (failure != null) throw failure;
    return const None();
  }

  /// Suppresses publications for channels removed from desired state.
  void discardMessages(Set<String> channels) {
    _events.removeWhere((event) => event is PubSubMessage && channels.contains(event.channel));
    _bytes = _events.fold(0, (total, event) => total + event.bufferedBytes);
  }

  /// Completes delivery, reserving one terminal event outside the normal limits.
  void finish({bool discard = false, PubSubInterrupted? terminal}) {
    if (discard) {
      _events.clear();
      _bytes = 0;
    }
    if (terminal != null) {
      _terminal = terminal;
      if (terminal.error case Some(:final value)) _failure = value;
    }
    _done = true;
    _wake();
  }

  void _wake() {
    _available?.complete();
    _available = null;
  }
}
