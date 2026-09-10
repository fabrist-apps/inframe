part of '../../effect.dart';

final class _Execution {
  _Execution({
    required this.context,
    required this.scope,
    required this.clock,
    required this.cancellation,
  });

  Context context;
  final _Scope scope;
  final Clock clock;
  final _Cancellation cancellation;
  var _steps = 0;

  Future<void> yieldIfNeeded() async {
    _steps += 1;
    if (_steps % 256 == 0) await Future<void>.delayed(Duration.zero);
  }
}

final class _Cancellation {
  var _nextListener = 0;
  final _listeners = <int, void Function(Object? reason)>{};
  Object? _reason;
  var _cancelled = false;

  bool get isCancelled => _cancelled;
  Object? get reason => _reason;

  void cancel(Object? reason) {
    if (_cancelled) return;
    _cancelled = true;
    _reason = reason;
    final listeners = List.of(_listeners.values);
    _listeners.clear();
    for (final listener in listeners) {
      listener(reason);
    }
  }

  void Function() listen(void Function(Object? reason) listener) {
    if (_cancelled) {
      listener(_reason);
      return () {};
    }
    final id = _nextListener++;
    _listeners[id] = listener;
    return () => _listeners.remove(id);
  }
}

final class _Scope {
  var _closed = false;

  bool get isClosed => _closed;

  Future<Cause<Never>?> close() async {
    _closed = true;
    return null;
  }
}
