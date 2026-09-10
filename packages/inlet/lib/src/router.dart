part of 'inlet.dart';

/// An editable collection of route and middleware registrations.
class Router {
  final List<_Route> _routes = [];
  final List<Middleware> _middleware = [];
  bool _frozen = false;

  /// Registers [handler] for the case-sensitive HTTP [method] and [path].
  void on(
    String method,
    String path,
    Handler handler, {
    List<Middleware> middleware = const [],
  }) {
    _ensureEditable();
    final validatedMethod = _validateMethod(method);
    final validatedPath = _validatePattern(path);
    if (_routes.any((route) => route.method == validatedMethod && route.path == validatedPath)) {
      throw StateError('A route is already registered for $validatedMethod $validatedPath.');
    }
    _routes.add(_Route(validatedMethod, validatedPath, handler, List.unmodifiable(middleware)));
  }

  /// Registers a GET route.
  void get(String path, Handler handler, {List<Middleware> middleware = const []}) =>
      on('GET', path, handler, middleware: middleware);

  /// Registers a POST route.
  void post(String path, Handler handler, {List<Middleware> middleware = const []}) =>
      on('POST', path, handler, middleware: middleware);

  /// Registers a PUT route.
  void put(String path, Handler handler, {List<Middleware> middleware = const []}) =>
      on('PUT', path, handler, middleware: middleware);

  /// Registers a PATCH route.
  void patch(String path, Handler handler, {List<Middleware> middleware = const []}) =>
      on('PATCH', path, handler, middleware: middleware);

  /// Registers a DELETE route.
  void delete(String path, Handler handler, {List<Middleware> middleware = const []}) =>
      on('DELETE', path, handler, middleware: middleware);

  /// Registers a HEAD route.
  void head(String path, Handler handler, {List<Middleware> middleware = const []}) =>
      on('HEAD', path, handler, middleware: middleware);

  /// Registers an OPTIONS route.
  void options(String path, Handler handler, {List<Middleware> middleware = const []}) =>
      on('OPTIONS', path, handler, middleware: middleware);

  /// Registers middleware for every route in this router scope.
  void use(Middleware middleware) {
    _ensureEditable();
    _middleware.add(middleware);
  }

  /// Copies [router]'s current registrations below [prefix].
  void route(String prefix, Router router) {
    _ensureEditable();
    final validatedPrefix = _validatePattern(prefix);
    for (final child in router._routes) {
      final joined = validatedPrefix == '/'
          ? child.path
          : child.path == '/'
          ? '$validatedPrefix/'
          : '$validatedPrefix${child.path}';
      on(child.method, joined, child.handler, middleware: child.middleware);
    }
  }

  void _freeze() => _frozen = true;

  void _ensureEditable() {
    if (_frozen) {
      throw StateError('Routes cannot be changed after first use.');
    }
  }
}

final class _Route {
  const _Route(this.method, this.path, this.handler, this.middleware);

  final String method;
  final String path;
  final Handler handler;
  final List<Middleware> middleware;
}

String _validatePattern(String path) {
  if (!path.startsWith('/') || path.contains('?') || path.contains('#')) {
    throw ArgumentError.value(path, 'path', 'must be an absolute path pattern');
  }
  return path;
}
