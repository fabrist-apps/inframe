/// Terminal and structured Chronicler request logs for Inlet applications.
library;

import 'dart:convert';
import 'dart:io';

import 'package:chronicler/chronicler.dart';
import 'package:inlet/inlet.dart';
import 'package:inlet_logger/src/duration_format.dart';
import 'package:inlet_request_id/inlet_request_id.dart';

/// Logs completed HTTP dispatches to the terminal and optional Chronicler recorder.
///
/// Register early with `app.use(logger())` to include short circuits and error recovery.
/// Emits one informational `HTTP request completed` record through the latest
/// forwarded context, with method, route template, status, optional request ID,
/// and monotonic `durationMicros` measured from middleware entry.
///
/// Terminal output works without Chronicler. Chronicler's log
/// collection, filtering, and export policies still apply to its output. Raw URLs, headers,
/// bodies, and exception messages are not recorded.
///
/// Uses [Request.onResponse] after dispatch error recovery and HEAD handling.
/// Duration and status exclude body delivery, WebSocket negotiation/sessions,
/// and any later transport recovery. Register once per middleware chain.
///
/// [console] controls output to stdout. ANSI colors are enabled only when stdout
/// supports them and `NO_COLOR` is absent. Chronicler logging depends only on
/// whether the forwarded context has a recorder. Neither destination is closed.
/// A synchronous terminal failure still allows Chronicler logging; Inlet reports
/// callback failures without changing the response.
Middleware logger({bool console = true}) => (context, request, next) {
  final timer = Stopwatch()..start();
  request.onResponse((context, request, response) {
    timer.stop();
    final id = context.requestIdOrNull;
    try {
      if (console) stdout.writeln(response.formatLog(request, id, timer.elapsedMicroseconds));
    } finally {
      if (context.hasChronicler) {
        context.logs.info(
          'HTTP request completed',
          attributes: {
            'http.request.method': request.method,
            'http.route': ?request.routeTemplate,
            'http.response.status_code': response.statusCode,
            'requestId': ?id,
            'durationMicros': timer.elapsedMicroseconds,
          },
        );
      }
    }
    return response;
  });
  return next(context, request);
};

extension on Response {
  String formatLog(Request request, String? id, int durationMicros) {
    final time = DateTime.now().toUtc().toIso8601String();
    final duration = Duration(microseconds: durationMicros).logText;
    final route = _escape(request.routeTemplate ?? '<unmatched>');
    final message = [
      '┌─ HTTP $statusCode ${_escape(request.method)} $route',
      '│ $time · $duration',
      if (id != null) '│ requestId: ${_escape(id)}',
      '└─',
    ].join('\n');
    if (!stdout.supportsAnsiEscapes || Platform.environment.containsKey('NO_COLOR')) return message;
    final color = switch (statusCode) {
      >= 500 => 31,
      >= 400 => 33,
      >= 300 => 36,
      _ => 32,
    };
    return '\x1b[${color}m$message\x1b[0m';
  }

  // Escape control characters so metadata cannot inject terminal commands/lines.
  static String _escape(String value) {
    final encoded = jsonEncode(value);
    return encoded.substring(1, encoded.length - 1);
  }
}
