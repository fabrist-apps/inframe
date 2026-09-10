part of '../../effect.dart';

/// Owns root [Effect] executions and their shared [Context].
final class Runtime {
  /// Creates a runtime using an empty context when [context] is omitted.
  Runtime({Context? context}) : context = context ?? Context();

  /// The context supplied to each root execution.
  final Context context;

  var _closed = false;

  /// Runs [effect] in a fresh root scope and returns after scope cleanup.
  Future<Exit<A, E>> run<A, E>(Effect<A, E> effect) async {
    if (_closed) throw StateError('Runtime is closed.');
    final scope = _Scope();
    final execution = _Execution(context: context, scope: scope);
    final exit = await effect._evaluate(execution);
    await scope.close();
    return exit;
  }

  /// Rejects future roots and waits for runtime-owned cleanup.
  Future<void> close() async {
    _closed = true;
  }
}
