/// Request IDs for Inlet applications.
library;

import 'package:chronicler/chronicler.dart';
import 'package:chrono_id/chrono_id.dart';
import 'package:context/context.dart';
import 'package:inlet/inlet.dart';

final _requestIdKey = ContextKey<String>('request ID');

/// Access to the ID assigned by [requestId].
extension RequestIdContext on Context {
  /// The current request ID; throws if the middleware has not run.
  String get requestId => require(_requestIdKey);

  /// The assigned request ID, or null when the middleware has not run.
  String? get requestIdOrNull => read(_requestIdKey);
}

/// Generates a fresh ChronoID for each request and forwards it downstream.
///
/// Register with `app.use(requestId)`. Handlers read `context.requestId` or
/// the `x-request-id` request header. Incoming IDs are always replaced.
/// Returned responses receive the same header, replacing any downstream value.
/// Request and response views retain their original body ownership.
/// When Chronicler is bound, adds `requestId` to the active span. Register
/// `httpTracing` before this middleware to establish that span. Without an
/// active span, Chronicler records a `noActiveSpan` diagnostic without throwing.
///
/// Errors propagate normally. Responses created by Inlet's outer error handler
/// do not pass back through this middleware; that handler can read
/// `context.requestId` and attach the header itself.
Future<Response> requestId(Context context, Request request, Next next) async {
  final id = ChronoID.generate(prefix: 'req');
  if (context.hasChronicler) {
    context.tracing.setAttribute('requestId', id);
  }
  final response = await next(
    context.withBinding(_requestIdKey.bind(id)),
    request.withHeaders(request.headers.set('x-request-id', id)),
  );
  return response.withHeaders(response.headers.set('x-request-id', id));
}
