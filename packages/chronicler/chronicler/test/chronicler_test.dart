import 'dart:async';

import 'package:chronicler/chronicler.dart';
import 'package:context/context.dart';
import 'package:test/test.dart';

void main() {
  group('Chronicler', () {
    test('should export a log recorded through Context', () async {
      final exporter = _Exporter();
      final chronicler = Chronicler(
        appId: 'app-1',
        release: '1.0.0',
        source: ChroniclerSource.server,
        exporter: exporter,
        options: const ChroniclerOptions(
          delivery: DeliveryOptions(maxBatchRecords: 1),
        ),
      );
      final context = Context().withChronicler(chronicler.recorder);

      context.logs.info('Order created', attributes: {'orderId': 'order-1'});

      final batch = await exporter.firstBatch;
      expect(batch.records, hasLength(1));
      final record = batch.records.single as LogRecord;
      expect(record.envelope.eventId, startsWith('evt_'));
      expect(record.payload.message, 'Order created');
      expect(record.payload.attributes, {'orderId': 'order-1'});
    });
  });
}

final class _Exporter implements ChroniclerExporter {
  final _batch = Completer<ChroniclerBatch>();

  Future<ChroniclerBatch> get firstBatch => _batch.future;

  @override
  ExportAttempt export(ChroniclerBatch batch) {
    _batch.complete(batch);
    return const _Attempt();
  }

  @override
  Future<void> close() async {}
}

final class _Attempt implements ExportAttempt {
  const _Attempt();

  @override
  Future<ExportResult> get result async => const ExportResult.accepted();

  @override
  void cancel() {}
}
