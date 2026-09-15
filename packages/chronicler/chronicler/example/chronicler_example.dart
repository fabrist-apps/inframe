import 'dart:convert';
import 'dart:io';

import 'package:chronicler/chronicler.dart';
import 'package:context/context.dart';

/// Runs entirely locally: no server, credentials, or Conflux application code.
Future<void> main() async {
  final chronicler = Chronicler(
    appId: 'shop_demo',
    release: '1.0.0',
    source: ChroniclerSource.server,
    exporter: _ConsoleExporter(),
    options: ChroniclerOptions(
      redaction: RedactionOptions(
        // Extend rather than accidentally replace the built-in privacy rules.
        fieldTerms: {...Chronicler.defaultSensitiveFieldTerms, 'email'},
        beforeRecord: (record) {
          // Suppress a noisy application event. This runs once, not per retry.
          if (record case ProductEventRecord(:final payload)
              when payload.name == 'checkout_form_viewed') {
            return null;
          }
          return record;
        },
      ),
      diagnostics: DiagnosticOptions(
        // Keep SDK diagnostics outside Chronicler to avoid recursive recording.
        onDiagnostic: (diagnostic) => stderr.writeln(
          'SDK diagnostic: ${diagnostic.reason.name} (${diagnostic.count})',
        ),
      ),
    ),
  );
  final application = Context().withChronicler(chronicler.recorder);

  try {
    for (final orderId in ['order_001', 'order_002']) {
      // Derive a request Context. Never store request identity on a shared one.
      final request = application.withIdentity(userId: 'user_demo', sessionId: 'session_demo');
      try {
        await _checkout(request, orderId: orderId, inStock: orderId == 'order_001');
      } on _OutOfStock {
        // The application would return an out-of-stock response here.
        stderr.writeln('$orderId: out of stock (expected demo failure)');
      }
    }

    // Also seals the partial metric interval. No need to wait for its timer.
    _printReport('flush', await chronicler.flush());
  } finally {
    // The application owns Chronicler; Chronicler closes its exporter.
    // A close report is its own snapshot, not a lifetime accepted-record count.
    _printReport('close', await chronicler.close());
  }
}

Future<void> _checkout(Context request, {required String orderId, required bool inStock}) async {
  final attempts = request.metrics.counter('checkout.attempts', unit: 'requests');
  final duration = request.metrics.histogram(
    'checkout.duration',
    unit: 'ms',
    boundaries: [1, 10, 50, 100, 500],
  );
  final elapsed = Stopwatch()..start();
  var outcome = 'success';

  try {
    await request.trace(
      'checkout',
      run: (trace) async {
        trace.tracing.setAttribute('orderId', orderId);
        trace.events.track('checkout_form_viewed');
        trace.logs.info(
          'Checkout started',
          attributes: {
            'orderId': orderId,
            // Fake values demonstrate field-name redaction. Never put secrets in messages.
            'email': 'demo@example.invalid',
            'password': 'not-a-real-password',
          },
        );

        try {
          await trace.span(
            'inventory.reserve',
            run: (inventory) async {
              inventory.tracing.setAttribute('warehouse', 'east');
              if (!inStock) throw const _OutOfStock();
              inventory.logs.info('Inventory reserved', attributes: {'orderId': orderId});
            },
          );
          trace.events.track(
            'purchase_completed',
            properties: {'orderId': orderId, 'amountMinor': 1200, 'currency': 'USD'},
          );
        } on _OutOfStock catch (error, stackTrace) {
          // Capture once at the handling boundary, while trace correlation is active.
          // A failed span does not automatically create an error occurrence.
          trace.errors.capture(error, stackTrace: stackTrace, attributes: {'orderId': orderId});
          rethrow; // Marks the root span as failed and preserves application behavior.
        }
      },
    );
  } on _OutOfStock {
    outcome = 'out_of_stock';
    rethrow;
  } finally {
    elapsed.stop();
    // Bounded dimensions: order/user IDs belong on records, not metric series.
    final dimensions = {'outcome': outcome};
    attempts.add(1, attributes: dimensions);
    duration.record(elapsed.elapsedMicroseconds / 1000, attributes: dimensions);
  }
}

final class _OutOfStock implements Exception {
  const _OutOfStock();

  @override
  String toString() => 'Requested item is out of stock';
}

/// A local inspection sink, not a durable or remote delivery implementation.
final class _ConsoleExporter implements ChroniclerExporter {
  final _codec = const ChroniclerCodec();

  @override
  ExportAttempt export(ChroniclerBatch batch) {
    final bytes = _codec.encodeBatch(batch);
    // One compact JSON batch per line. Decode only to make the bytes readable.
    // ignore: avoid_print, this example's destination is the console itself.
    print(utf8.decode(bytes));
    return _CompletedAttempt();
  }

  @override
  Future<void> close() async {
    // This exporter owns no resources. Do not close the process-wide stdout.
  }
}

final class _CompletedAttempt implements ExportAttempt {
  @override
  final Future<ExportResult> result = Future.value(const ExportResult.accepted());

  @override
  void cancel() {
    // The synchronous console write already returned; no transport remains.
    // A network exporter must abort its I/O and settle result after it stops.
  }
}

void _printReport(String operation, DeliveryReport report) {
  stderr.writeln(
    '$operation: accepted=${report.accepted}, dropped=${report.dropped}, '
    'pending=${report.pending}, timedOut=${report.timedOut}, '
    'uncertainDropped=${report.uncertainDropped}, cleanupIncomplete=${report.cleanupIncomplete}',
  );
}
