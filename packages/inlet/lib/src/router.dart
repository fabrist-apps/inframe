part of 'inlet.dart';

/// An editable collection of route and middleware registrations.
class Router {
  /// Creates an editable router.
  Router() : this._(true);

  Router._(this._strict);

  final bool _strict;
  final List<_RouteRegistration> _registrations = [];
  final List<Middleware> _middleware = [];
  _CompiledRouter? _compiled;
  Future<void>? _starting;

  /// Registers [handler] for the case-sensitive HTTP [method] and [path].
  void on(
    String method,
    String path,
    Handler handler, {
    List<Middleware> middleware = const [],
  }) {
    _ensureEditable();

    final registration = _RouteRegistration(
      method: _validateMethod(method),
      rawPath: path,
      pattern: _RoutePattern.parse(path, strict: _strict),
      handler: handler,
      middleware: List.unmodifiable(middleware),
    )..ensureNoConflict(_registrations);

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
    final mounted = <_RouteRegistration>[];

    for (final child in router._registrations) {
      final rawPath = _joinPaths(prefix, child.rawPath);
      final registration = _RouteRegistration(
        method: child.method,
        rawPath: rawPath,
        pattern: _RoutePattern.parse(rawPath, strict: _strict),
        handler: child.handler,
        middleware: List.unmodifiable([...childScope, ...child.middleware]),
      )..ensureNoConflict(_registrations.followedBy(mounted));

      mounted.add(registration);
    }

    // Publish only after every mounted registration has passed validation.
    _registrations.addAll(mounted);
  }

  Future<_CompiledRouter> _admit(Request request) async {
    while (true) {
      final frozen = _compiled;
      if (frozen != null) {
        request._admit();

        return frozen;
      }

      final starting = _starting;
      if (starting != null) {
        await starting;
        continue;
      }

      final candidate = _compile();
      request._admit();
      _compiled = candidate;

      return candidate;
    }
  }

  // A failed bind leaves the router editable; admissions wait for it to settle.
  Future<T> _freezeAfter<T>(Future<T> Function() start) async {
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

  _CompiledRouter _compile() => _CompiledRouter.compile(
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

final class _RouteRegistration {
  const _RouteRegistration({
    required this.method,
    required this.rawPath,
    required this.pattern,
    required this.handler,
    required this.middleware,
  });

  final String method;
  final String rawPath;
  final _RoutePattern pattern;
  final Handler handler;
  final List<Middleware> middleware;

  void ensureNoConflict(Iterable<_RouteRegistration> existing) {
    for (final registration in existing) {
      if (method == registration.method && pattern.hasSameShape(registration.pattern)) {
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

final class _CompiledRouter {
  const _CompiledRouter(
    this.root, {
    required this.rootMiddleware,
    required this.strict,
  });

  factory _CompiledRouter.compile(
    List<_RouteRegistration> registrations, {
    required List<Middleware> rootMiddleware,
    required bool strict,
  }) {
    final root = _BuildRouteNode();

    for (final registration in registrations) {
      var node = root;
      for (final segment in registration.pattern.segments) {
        node = switch (segment) {
          _LiteralSegment(:final value) => node.literals.putIfAbsent(value, _BuildRouteNode.new),
          _ParameterSegment() => node.parameter ??= _BuildRouteNode(),
          _WildcardSegment() => node.wildcard ??= _BuildRouteNode(),
        };
      }

      node.endpoints[registration.method] = registration;
    }

    return _CompiledRouter(
      root.freeze(),
      rootMiddleware: List.unmodifiable(rootMiddleware),
      strict: strict,
    );
  }

  final _CompiledRouteNode root;
  final List<Middleware> rootMiddleware;
  final bool strict;

  _RouteResolution resolve(Request request) {
    late final List<String> segments;
    try {
      segments = [...request.uri.pathSegments];
    } on FormatException {
      return const _BadRoutePath();
    }

    if (!strict && segments.isNotEmpty && segments.last.isEmpty) {
      segments.removeLast();
    }

    final candidates = <_PathCandidate>[];
    _collectCandidates(root, segments, 0, const [], candidates);
    if (candidates.isEmpty) {
      return const _RouteNotFound();
    }

    if (request.method == 'HEAD') {
      final explicit = _matchForMethod(candidates, 'HEAD');
      if (explicit != null) {
        return explicit;
      }

      final fallback = _matchForMethod(candidates, 'GET');
      if (fallback != null) {
        return fallback.asHeadFallback();
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
    return _MethodNotAllowed(List.unmodifiable(sorted));
  }

  _MatchedRoute? _matchForMethod(
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
    _CompiledRouteNode node,
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

final class _BuildRouteNode {
  final Map<String, _BuildRouteNode> literals = {};
  _BuildRouteNode? parameter;
  _BuildRouteNode? wildcard;
  final Map<String, _RouteRegistration> endpoints = {};

  _CompiledRouteNode freeze() => _CompiledRouteNode(
    literals: Map.unmodifiable(literals.map((key, value) => MapEntry(key, value.freeze()))),
    parameter: parameter?.freeze(),
    wildcard: wildcard?.freeze(),
    endpoints: Map.unmodifiable(endpoints),
  );
}

final class _CompiledRouteNode {
  const _CompiledRouteNode({
    required this.literals,
    required this.parameter,
    required this.wildcard,
    required this.endpoints,
  });

  final Map<String, _CompiledRouteNode> literals;
  final _CompiledRouteNode? parameter;
  final _CompiledRouteNode? wildcard;
  final Map<String, _RouteRegistration> endpoints;
}

final class _PathCandidate {
  const _PathCandidate(this.node, this.captures);

  final _CompiledRouteNode node;
  final List<String> captures;

  _MatchedRoute? matchForMethod(String method) {
    final registration = node.endpoints[method];
    if (registration == null) {
      return null;
    }

    final parameters = <String, String>{};

    for (var index = 0; index < captures.length; index++) {
      parameters[registration.pattern.captureNames[index]] = captures[index];
    }

    return _MatchedRoute(registration, Map.unmodifiable(parameters));
  }
}

sealed class _RouteResolution {
  const _RouteResolution();
}

final class _MatchedRoute extends _RouteResolution {
  const _MatchedRoute(
    this.registration,
    this.pathParameters, {
    this.isHeadFallback = false,
  });

  final _RouteRegistration registration;
  final Map<String, String> pathParameters;
  final bool isHeadFallback;

  _MatchedRoute asHeadFallback() => _MatchedRoute(
    registration,
    pathParameters,
    isHeadFallback: true,
  );
}

final class _BadRoutePath extends _RouteResolution {
  const _BadRoutePath();
}

final class _RouteNotFound extends _RouteResolution {
  const _RouteNotFound();
}

final class _MethodNotAllowed extends _RouteResolution {
  const _MethodNotAllowed(this.allowedMethods);

  final List<String> allowedMethods;
}
