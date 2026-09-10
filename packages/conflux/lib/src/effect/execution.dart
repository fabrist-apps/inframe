part of '../../effect.dart';

final class _Execution {
  _Execution({required this.context, required this.scope});

  Context context;
  final _Scope scope;
  var _steps = 0;

  Future<void> yieldIfNeeded() async {
    _steps += 1;
    if (_steps % 256 == 0) await Future<void>.delayed(Duration.zero);
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
