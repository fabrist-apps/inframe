import 'dart:async';

import 'package:inlet/src/handler.dart';
import 'package:inlet/src/http_token.dart';
import 'package:inlet/src/request.dart';

/// An editable collection of route and middleware registrations.
class Router {
  /// Creates an editable router.
  Router({this._strict = true});

  final bool _strict;
  final List<RouteRegistration> _registrations = [];
  final List<Middleware> _middleware = [];
  CompiledRouter? _compiled;
  Future<void>? _starting;

  /// Registers [handler] for the case-sensitive HTTP [method] and [path].
  void on(
    String method,
    String path,
    Handler handler, {
    List<Middleware> middleware = const [],
  }) {
    _ensureEditable();

    final registration = RouteRegistration._(
      method: validateMethod(method),
      rawPath: path,
      pattern: _RoutePattern.parse(path, strict: _strict),
      handler: handler,
      middleware: List.unmodifiable(middleware),
    ).._ensureNoConflict(_registrations);

    _registrations.add(registration);
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
    _validateMountPrefix(prefix);

    final childScope = List<Middleware>.unmodifiable(router._middleware);
    final mounted = <RouteRegistration>[];

    for (final child in router._registrations) {
      final rawPath = _joinPaths(prefix, child.rawPath);
      final registration = RouteRegistration._(
        method: child.method,
        rawPath: rawPath,
        pattern: _RoutePattern.parse(rawPath, strict: _strict),
        handler: child.handler,
        middleware: List.unmodifiable([...childScope, ...child.middleware]),
      ).._ensureNoConflict(_registrations.followedBy(mounted));

      mounted.add(registration);
    }

    // Publish only after every mounted registration has passed validation.
    _registrations.addAll(mounted);
  }

  CompiledRouter _compile() => CompiledRouter._compile(
    _registrations,
    rootMiddleware: _middleware,
    strict: _strict,
  );

  void _validateMountPrefix(String prefix) {
    if (prefix != '/' && prefix.endsWith('/')) {
      throw ArgumentError.value(prefix, 'prefix', 'must not end with a slash');
    }

    final pattern = _RoutePattern.parse(prefix, strict: true);
    if (pattern.segments.any((segment) => segment is _WildcardSegment)) {
      throw ArgumentError.value(prefix, 'prefix', 'must not contain a wildcard');
    }
  }

  String _joinPaths(String prefix, String childPath) {
    if (prefix == '/') {
      return childPath;
    }

    return '$prefix$childPath';
  }

  void _ensureEditable() {
    if (_compiled != null || _starting != null) {
      throw StateError('Routes cannot be changed after first use.');
    }
  }
}

/// Internal admission boundary, excluded from the package entrypoint.
extension RouterRuntime on Router {
  /// Freezes registration and claims the request for one dispatch.
  Future<CompiledRouter> admit(Request request) async {
    while (true) {
      final frozen = _compiled;
      if (frozen != null) {
        request.admit();

        return frozen;
      }

      final starting = _starting;
      if (starting != null) {
        await starting;
        continue;
      }

      final candidate = _compile();
      request.admit();
      _compiled = candidate;

      return candidate;
    }
  }

  /// Freezes after a successful bind; admissions wait for binding to settle.
  /// A failed bind leaves the router editable.
  Future<T> freezeAfter<T>(Future<T> Function() start) async {
    while (true) {
      if (_compiled != null) {
        return start();
      }

      final starting = _starting;
      if (starting != null) {
        await starting;
        continue;
      }

      final candidate = _compile();
      final settled = Completer<void>();
      _starting = settled.future;

      try {
        final value = await start();
        _compiled = candidate;

        return value;
      } finally {
        _starting = null;
        settled.complete();
      }
    }
  }
}

/// A validated route and its mounted middleware snapshot.
final class RouteRegistration {
  const RouteRegistration._({
    required this.method,
    required this.rawPath,
    required this._pattern,
    required this.handler,
    required this.middleware,
  });

  /// Case-sensitive HTTP method.
  final String method;

  /// Original mounted path, used when copying registrations.
  final String rawPath;
  final _RoutePattern _pattern;

  /// Handler selected by route matching.
  final Handler handler;

  /// Middleware belonging to this route and its mounted scopes.
  final List<Middleware> middleware;

  void _ensureNoConflict(Iterable<RouteRegistration> existing) {
    for (final registration in existing) {
      if (method == registration.method && _pattern.hasSameShape(registration._pattern)) {
        throw StateError('An equivalent route is already registered for $method.');
      }
    }
  }
}

final class _RoutePattern {
  const _RoutePattern(this.segments, this.captureNames);

  factory _RoutePattern.parse(String path, {required bool strict}) {
    if (!path.startsWith('/') || path.contains('?') || path.contains('#')) {
      throw ArgumentError.value(path, 'path', 'must be an absolute path pattern');
    }

    final rawSegments = path == '/' ? <String>[] : path.substring(1).split('/');

    final segments = <_PatternSegment>[];
    final captureNames = <String>[];

    for (var index = 0; index < rawSegments.length; index++) {
      final rawSegment = rawSegments[index];
      final isWildcard = rawSegment.startsWith('*');
      if (rawSegment.startsWith(':') || isWildcard) {
        if (isWildcard && index != rawSegments.length - 1) {
          throw ArgumentError.value(path, 'path', 'a wildcard must be the final segment');
        }

        final name = rawSegment.substring(1);
        if (!_captureName.hasMatch(name) || captureNames.contains(name)) {
          throw ArgumentError.value(path, 'path', 'contains an invalid or repeated capture name');
        }

        captureNames.add(name);
        segments.add(isWildcard ? const _WildcardSegment() : const _ParameterSegment());
        continue;
      }

      if (rawSegment.contains(':') || rawSegment.contains('*')) {
        throw ArgumentError.value(path, 'path', 'captures must occupy a whole segment');
      }

      segments.add(_LiteralSegment(_decodePatternLiteral(rawSegment, path)));
    }

    if (segments.lastOrNull case _LiteralSegment(value: '') when !strict) {
      segments.removeLast();
    }

    return _RoutePattern(List.unmodifiable(segments), List.unmodifiable(captureNames));
  }

  static final _captureName = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

  final List<_PatternSegment> segments;
  final List<String> captureNames;

  static String _decodePatternLiteral(String rawSegment, String path) {
    if (rawSegment.isEmpty) {
      return '';
    }

    try {
      return Uri.parse('/$rawSegment').pathSegments.single;
    } on Object {
      throw ArgumentError.value(path, 'path', 'contains invalid percent-encoded UTF-8');
    }
  }

  bool hasSameShape(_RoutePattern other) {
    if (segments.length != other.segments.length) {
      return false;
    }

    for (var index = 0; index < segments.length; index++) {
      final left = segments[index];
      final right = other.segments[index];
      if (left.runtimeType != right.runtimeType) {
        return false;
      }

      if (left case _LiteralSegment(:final value)) {
        if ((right as _LiteralSegment).value != value) {
          return false;
        }
      }
    }

    return true;
  }
}

sealed class _PatternSegment {
  const _PatternSegment();
}

final class _LiteralSegment extends _PatternSegment {
  const _LiteralSegment(this.value);

  final String value;
}

final class _ParameterSegment extends _PatternSegment {
  const _ParameterSegment();
}

final class _WildcardSegment extends _PatternSegment {
  const _WildcardSegment();
}

/// A routing snapshot whose trie is private and never mutated after creation.
final class CompiledRouter {
  const CompiledRouter._(
    this._root, {
    required this.rootMiddleware,
    required this.strict,
  });

  factory CompiledRouter._compile(
    List<RouteRegistration> registrations, {
    required List<Middleware> rootMiddleware,
    required bool strict,
  }) {
    final root = _RouteNode();

    for (final registration in registrations) {
      var node = root;
      for (final segment in registration._pattern.segments) {
        node = switch (segment) {
          _LiteralSegment(:final value) => node.literals.putIfAbsent(value, _RouteNode.new),
          _ParameterSegment() => node.parameter ??= _RouteNode(),
          _WildcardSegment() => node.wildcard ??= _RouteNode(),
        };
      }

      node.endpoints[registration.method] = registration;
    }

    return CompiledRouter._(
      root,
      rootMiddleware: List.unmodifiable(rootMiddleware),
      strict: strict,
    );
  }

  final _RouteNode _root;

  /// Middleware shared by every matched route in this router.
  final List<Middleware> rootMiddleware;

  /// Whether a trailing slash is significant.
  final bool strict;

  /// Matches paths in precedence order, then selects the requested method.
  RouteResolution resolve(Request request) {
    late final List<String> segments;
    try {
      segments = [...request.uri.pathSegments];
    } on FormatException {
      return const BadRoutePath();
    }

    if (!strict && segments.isNotEmpty && segments.last.isEmpty) {
      segments.removeLast();
    }

    final candidates = <_PathCandidate>[];
    _collectCandidates(_root, segments, 0, const [], candidates);
    if (candidates.isEmpty) {
      return const RouteNotFound();
    }

    if (request.method == 'HEAD') {
      final explicit = _matchForMethod(candidates, 'HEAD');
      if (explicit != null) {
        return explicit;
      }

      final fallback = _matchForMethod(candidates, 'GET');
      if (fallback != null) {
        return fallback._asHeadFallback();
      }
    } else {
      final match = _matchForMethod(candidates, request.method);
      if (match != null) {
        return match;
      }
    }

    final allowed = <String>{};
    for (final candidate in candidates) {
      allowed.addAll(candidate.node.endpoints.keys);
      if (candidate.node.endpoints.containsKey('GET')) {
        allowed.add('HEAD');
      }
    }

    final sorted = allowed.toList()..sort();
    return MethodNotAllowed(List.unmodifiable(sorted));
  }

  MatchedRoute? _matchForMethod(
    List<_PathCandidate> candidates,
    String method,
  ) {
    for (final candidate in candidates) {
      final match = candidate.matchForMethod(method);
      if (match != null) {
        return match;
      }
    }

    return null;
  }

  // Collect in precedence order; method selection may backtrack to a later path.
  void _collectCandidates(
    _RouteNode node,
    List<String> segments,
    int index,
    List<String> captures,
    List<_PathCandidate> candidates,
  ) {
    if (index == segments.length) {
      if (node.endpoints.isNotEmpty) {
        candidates.add(_PathCandidate(node, captures));
      }

      final wildcard = node.wildcard;
      if (wildcard != null && (!strict || index == 0) && wildcard.endpoints.isNotEmpty) {
        candidates.add(_PathCandidate(wildcard, [...captures, '']));
      }

      return;
    }

    final segment = segments[index];
    final literal = node.literals[segment];
    if (literal != null) {
      _collectCandidates(literal, segments, index + 1, captures, candidates);
    }

    final parameter = node.parameter;
    if (parameter != null && segment.isNotEmpty) {
      _collectCandidates(parameter, segments, index + 1, [...captures, segment], candidates);
    }

    final wildcard = node.wildcard;
    if (wildcard != null && wildcard.endpoints.isNotEmpty) {
      candidates.add(_PathCandidate(wildcard, [...captures, segments.sublist(index).join('/')]));
    }
  }
}

// Built once by CompiledRouter._compile; no node escapes the routing library or
// changes after publication.
final class _RouteNode {
  final Map<String, _RouteNode> literals = {};
  _RouteNode? parameter;
  _RouteNode? wildcard;
  final Map<String, RouteRegistration> endpoints = {};
}

final class _PathCandidate {
  const _PathCandidate(this.node, this.captures);

  final _RouteNode node;
  final List<String> captures;

  MatchedRoute? matchForMethod(String method) {
    final registration = node.endpoints[method];
    if (registration == null) {
      return null;
    }

    final parameters = <String, String>{};

    for (var index = 0; index < captures.length; index++) {
      parameters[registration._pattern.captureNames[index]] = captures[index];
    }

    return MatchedRoute(registration, Map.unmodifiable(parameters));
  }
}

/// Exhaustive result of matching a request against the route snapshot.
sealed class RouteResolution {
  /// Creates a route resolution.
  const RouteResolution();
}

/// A selected endpoint and decoded captures.
final class MatchedRoute extends RouteResolution {
  /// Creates a match for an endpoint.
  const MatchedRoute(
    this.registration,
    this.pathParameters, {
    this.isHeadFallback = false,
  });

  /// Selected handler and middleware registration.
  final RouteRegistration registration;

  /// Captures decoded once after separating path segments.
  final Map<String, String> pathParameters;

  /// Whether HEAD selected a GET endpoint.
  final bool isHeadFallback;

  MatchedRoute _asHeadFallback() => MatchedRoute(
    registration,
    pathParameters,
    isHeadFallback: true,
  );
}

/// The request path contains invalid percent-encoded UTF-8.
final class BadRoutePath extends RouteResolution {
  /// Creates an invalid-path result.
  const BadRoutePath();
}

/// No registered path matches the request.
final class RouteNotFound extends RouteResolution {
  /// Creates a missing-route result.
  const RouteNotFound();
}

/// Paths matched, but none accepts the requested method.
final class MethodNotAllowed extends RouteResolution {
  /// Creates a method mismatch with sorted allowed methods.
  const MethodNotAllowed(this.allowedMethods);

  /// Sorted methods, including HEAD where GET is registered.
  final List<String> allowedMethods;
}
