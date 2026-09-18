import 'package:context/context.dart';
import 'package:inlet/inlet.dart';

/// An explicit CORS policy, registered with `app.use(cors.call)`.
///
/// Origins are exact serialized HTTP(S) origins, or `null` for opaque origins.
/// `*` permits any origin only when credentials are disabled. CORS controls
/// browser access to responses; it does not authenticate or authorize requests.
final class Cors {
  /// Copies the policy and rejects invalid origins, HTTP tokens, wildcard
  /// methods or headers, negative cache durations, and credentialed wildcard
  /// origins. Methods are case-sensitive; header names are case-insensitive.
  Cors({
    required Iterable<String> allowedOrigins,
    Iterable<String> allowedMethods = const ['GET', 'HEAD', 'POST'],
    Iterable<String> allowedHeaders = const [],
    Iterable<String> exposedHeaders = const [],
    this.allowCredentials = false,
    this.maxAge,
  }) : allowedOrigins = Set.unmodifiable(allowedOrigins),
       allowedMethods = _tokens(allowedMethods, 'allowedMethods'),
       allowedHeaders = _tokens(allowedHeaders, 'allowedHeaders', lowercase: true),
       exposedHeaders = _tokens(exposedHeaders, 'exposedHeaders', lowercase: true) {
    for (final origin in this.allowedOrigins) {
      if (origin != '*' && !_isOrigin(origin)) {
        throw ArgumentError.value(origin, 'allowedOrigins', 'must be a serialized HTTP(S) origin');
      }
    }
    if (allowCredentials && this.allowedOrigins.contains('*')) {
      throw ArgumentError('Wildcard origins cannot allow credentials');
    }
    if (maxAge != null && maxAge!.isNegative) {
      throw ArgumentError.value(maxAge, 'maxAge', 'must not be negative');
    }
  }

  /// Origins whose responses browsers may read.
  final Set<String> allowedOrigins;

  /// Exact method tokens accepted by preflight requests.
  final Set<String> allowedMethods;

  /// Lowercase request header names accepted by preflight requests.
  final Set<String> allowedHeaders;

  /// Lowercase response header names exposed to browser scripts.
  final Set<String> exposedHeaders;

  /// Whether browsers may expose responses to credentialed requests.
  final bool allowCredentials;

  /// Optional preflight cache lifetime, serialized in whole seconds.
  final Duration? maxAge;

  /// Handles preflights and applies headers to final, including recovered, responses.
  ///
  /// Requests without an origin and requests from disallowed origins continue.
  /// Malformed origins and rejected preflights return 403 without a CORS grant.
  /// Register before middleware that can short-circuit requests.
  Future<Response> call(Context context, Request request, Next next) async {
    final origins = request.headers.all('origin');
    final hasOrigin = request.headers.contains('origin');
    final origin = origins.length == 1 ? origins.single : null;
    final validOrigin = origin != null && _isOrigin(origin);
    final preflight =
        request.method == 'OPTIONS' &&
        hasOrigin &&
        request.headers.contains('access-control-request-method');
    var grant = validOrigin && (allowedOrigins.contains('*') || allowedOrigins.contains(origin));
    if (preflight) {
      final methods = request.headers.all('access-control-request-method');
      final requestedHeaders = request.headers
          .all('access-control-request-headers')
          .expand((value) => value.split(','))
          .map((name) => name.trim().toLowerCase());
      grant =
          grant &&
          methods.length == 1 &&
          _isToken(methods.single) &&
          allowedMethods.contains(methods.single) &&
          requestedHeaders.every((name) => _isToken(name) && allowedHeaders.contains(name));
    }
    request.onResponse((_, _, response) {
      var headers = response.headers;
      // A single policy owns grants, even when a handler supplies permissive headers.
      for (final name in headers.toMap().keys) {
        if (name.startsWith('access-control-')) {
          headers = headers.remove(name);
        }
      }
      headers = _vary(headers, [
        'Origin',
        if (preflight) 'Access-Control-Request-Method',
        if (preflight) 'Access-Control-Request-Headers',
      ]);
      if (grant) {
        headers = headers.set(
          'access-control-allow-origin',
          allowedOrigins.contains('*') ? '*' : origin!,
        );
        if (allowCredentials) {
          headers = headers.set('access-control-allow-credentials', 'true');
        }
        if (preflight) {
          headers = headers.set('access-control-allow-methods', allowedMethods.join(', '));
          if (allowedHeaders.isNotEmpty) {
            headers = headers.set('access-control-allow-headers', allowedHeaders.join(', '));
          }
          if (maxAge != null) {
            headers = headers.set('access-control-max-age', '${maxAge!.inSeconds}');
          }
        } else if (exposedHeaders.isNotEmpty) {
          headers = headers.set('access-control-expose-headers', exposedHeaders.join(', '));
        }
      }
      return response.withHeaders(headers);
    });
    if (hasOrigin && !validOrigin || preflight && !grant) {
      return Response.empty(status: 403);
    }
    if (preflight) {
      return Response.empty();
    }
    return next(context, request);
  }

  static Set<String> _tokens(Iterable<String> values, String parameter, {bool lowercase = false}) {
    final result = <String>{};
    for (final value in values) {
      if (!_isToken(value) || value == '*') {
        throw ArgumentError.value(value, parameter, 'must be an explicit HTTP token');
      }
      result.add(lowercase ? value.toLowerCase() : value);
    }
    return Set.unmodifiable(result);
  }

  static bool _isToken(String value) => RegExp(r"^[!#$%&'*+.^_`|~0-9A-Za-z-]+$").hasMatch(value);

  static bool _isOrigin(String value) {
    if (value == 'null') {
      return true;
    }
    try {
      final uri = Uri.parse(value);
      return (uri.scheme == 'http' || uri.scheme == 'https') &&
          uri.host.isNotEmpty &&
          uri.userInfo.isEmpty &&
          !uri.hasQuery &&
          !uri.hasFragment &&
          uri.path.isEmpty &&
          uri.origin == value;
    } on FormatException {
      return false;
    }
  }

  static Headers _vary(Headers headers, List<String> names) {
    if (names.isEmpty) {
      return headers;
    }
    final values = <String, String>{};
    for (final value in [...headers.all('vary').expand((value) => value.split(',')), ...names]) {
      final token = value.trim();
      if (token == '*') {
        return headers.set('vary', '*');
      }
      if (token.isNotEmpty) {
        values.putIfAbsent(token.toLowerCase(), () => token);
      }
    }
    return headers.set('vary', values.values.join(', '));
  }
}
