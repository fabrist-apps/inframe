/// HTTP handler tracing for Inlet applications.
library;

import 'package:chronicler/chronicler.dart';
import 'package:context/context.dart';
import 'package:inlet/inlet.dart';

/// Traces downstream HTTP request handling when Chronicler is configured.
///
/// Register before `requestId` so it can attach its ID to the span. Starts a server
/// span at an explicit trace boundary, continuing valid Chronicler propagation
/// headers or creating a new trace. Missing, malformed, or duplicate propagation
/// metadata starts a new trace. W3C Trace Context is not supported by Chronicler.
/// Without a Chronicler binding, forwards the request without tracing.
///
/// Records the method, matched route template, and returned
/// response status. Returned 5xx responses and thrown errors mark the span as
/// failed. Errors propagate unchanged; responses produced later by Inlet's outer
/// error handler are outside this span, so their status cannot be recorded here.
///
/// The span ends when downstream handling completes, before body delivery or a
/// WebSocket session. It does not consume streams or record raw URLs, headers,
/// bodies, or exception messages. Transport finalization can change the status
/// after this middleware returns (for example, a rejected WebSocket handshake).
Future<Response> httpTracing(Context context, Request request, Next next) {
  if (!context.hasChronicler) return next(context, request);

  final route = request.routeTemplate;
  return context.trace(
    route == null ? request.method : '${request.method} $route',
    (spanContext) async {
      final response = await next(spanContext, request);
      spanContext.tracing.setAttribute('http.response.status_code', response.statusCode);
      if (response.statusCode >= 500) spanContext.tracing.setError();
      return response;
    },
    parent: request.headers.remoteParent,
    kind: SpanKind.server,
    attributes: {
      'http.request.method': request.method,
      'http.route': ?route,
    },
  );
}

extension on Headers {
  RemoteTraceParent? get remoteParent {
    final carrier = <String, String>{};
    for (final name in [
      TracePropagation.traceIdHeader,
      TracePropagation.spanIdHeader,
      TracePropagation.sampledHeader,
    ]) {
      final values = all(name);
      if (values.length != 1) return null;
      carrier[name] = values.single;
    }
    return TracePropagation.extract(carrier);
  }
}
