// Tests keep sequential invalid calls visible beside their expected counters.
// ignore_for_file: cascade_invocations

import 'package:chronicler/chronicler.dart';
import 'package:context/context.dart';
import 'package:test/test.dart';

import 'support/exporter.dart';

void main() {
  group('Chronicler record validation', () {
    test('should diagnose invalid values without exporting or throwing', () async {
      final exporter = TestExporter();
      final chronicler = Chronicler(
        appId: 'app',
        release: 'release',
        source: ChroniclerSource.server,
        exporter: exporter,
        options: const ChroniclerOptions(
          delivery: DeliveryOptions(maxBatchRecords: 1),
        ),
      );
      final logs = Context().withChronicler(chronicler.recorder).logs;
      final cyclic = <String, Object?>{};
      cyclic['self'] = cyclic;

      logs.info('unsupported', attributes: {'value': Object()});
      logs.info('cycle', attributes: cyclic);
      logs.info('nan', attributes: {'value': double.nan});
      logs.info('large integer', attributes: {'value': 9007199254740992});
      logs.info('large integral double', attributes: {'value': 9007199254740992.0});
      logs.info(String.fromCharCode(0xd800));
      await Future<void>.delayed(Duration.zero);

      expect(exporter.batches, isEmpty);
      expect(chronicler.diagnosticCounts[DiagnosticReason.invalidRecord], BigInt.from(6));
    });

    test('should stop shared-container expansion at the record budget', () {
      final exporter = TestExporter();
      final chronicler = Chronicler(
        appId: 'app',
        release: 'release',
        source: ChroniclerSource.server,
        exporter: exporter,
        options: const ChroniclerOptions(
          delivery: DeliveryOptions(maxBatchRecords: 1),
        ),
      );
      final leaf = List<Object?>.filled(128, 'x' * 8192);
      final shared = List<Object?>.filled(128, leaf);

      Context()
          .withChronicler(chronicler.recorder)
          .logs
          .info('bounded', attributes: {'items': shared});

      expect(exporter.batches, isEmpty);
      expect(chronicler.diagnosticCounts[DiagnosticReason.invalidRecord], BigInt.one);
    });

    test('should count the root map as container depth one', () async {
      final exporter = TestExporter();
      final chronicler = Chronicler(
        appId: 'app',
        release: 'release',
        source: ChroniclerSource.server,
        exporter: exporter,
        options: const ChroniclerOptions(
          delivery: DeliveryOptions(maxBatchRecords: 1),
          limits: ChroniclerLimits(maxDepth: 2),
        ),
      );
      final logs = Context().withChronicler(chronicler.recorder).logs;

      logs.info(
        'valid',
        attributes: {
          'nested': {'value': true},
        },
      );
      logs.info(
        'invalid',
        attributes: {
          'nested': {
            'deeper': <Object?>[true],
          },
        },
      );
      await Future<void>.delayed(Duration.zero);

      expect(exporter.batches, hasLength(1));
      expect(chronicler.diagnosticCounts[DiagnosticReason.invalidRecord], BigInt.one);
    });

    test('should preserve valid Unicode and enforce UTF-8 byte limits', () async {
      final exporter = TestExporter();
      final chronicler = Chronicler(
        appId: 'app',
        release: 'release',
        source: ChroniclerSource.server,
        exporter: exporter,
        options: const ChroniclerOptions(
          delivery: DeliveryOptions(maxBatchRecords: 1),
          limits: ChroniclerLimits(maxStringBytes: 4),
        ),
      );
      final logs = Context().withChronicler(chronicler.recorder).logs;

      logs.info('😀');
      logs.info('😀a');
      await Future<void>.delayed(Duration.zero);

      expect(exporter.batches, hasLength(1));
      expect(chronicler.diagnosticCounts[DiagnosticReason.invalidRecord], BigInt.one);
    });

    test('should retain in-flight records in count capacity', () async {
      final exporter = TestExporter();
      final chronicler = Chronicler(
        appId: 'app',
        release: 'release',
        source: ChroniclerSource.server,
        exporter: exporter,
        options: const ChroniclerOptions(
          delivery: DeliveryOptions(
            maxPendingRecords: 1,
            maxBatchRecords: 1,
          ),
        ),
      );
      final logs = Context().withChronicler(chronicler.recorder).logs;

      logs.info('first');
      await Future<void>.delayed(Duration.zero);
      logs.info('second');

      expect(chronicler.diagnosticCounts[DiagnosticReason.queueFull], BigInt.one);
      exporter.attempts.single.completer.complete(const ExportResult.accepted());
    });

    test('should enforce nested map, list, key, and total record bounds', () async {
      final exporter = TestExporter();
      final chronicler = Chronicler(
        appId: 'app',
        release: 'release',
        source: ChroniclerSource.server,
        exporter: exporter,
        options: const ChroniclerOptions(
          delivery: DeliveryOptions(maxBatchRecords: 1, maxRecordBytes: 400),
          limits: ChroniclerLimits(
            maxMapEntries: 1,
            maxListItems: 1,
            maxKeyBytes: 2,
            maxStringBytes: 300,
          ),
        ),
      );
      final logs = Context().withChronicler(chronicler.recorder).logs;

      logs.info('map', attributes: {'a': 1, 'b': 2});
      logs.info(
        'list',
        attributes: {
          'a': [1, 2],
        },
      );
      logs.info('key', attributes: {'long': 1});
      logs.info('record', attributes: {'a': 'x' * 300});
      await Future<void>.delayed(Duration.zero);

      expect(exporter.batches, isEmpty);
      expect(chronicler.diagnosticCounts[DiagnosticReason.invalidRecord], BigInt.from(3));
      expect(chronicler.diagnosticCounts[DiagnosticReason.recordTooLarge], BigInt.one);
    });

    test('should retain in-flight records in encoded-byte capacity', () async {
      final exporter = TestExporter();
      final chronicler = Chronicler(
        appId: 'app',
        release: 'release',
        source: ChroniclerSource.server,
        exporter: exporter,
        options: const ChroniclerOptions(
          delivery: DeliveryOptions(
            maxPendingRecords: 10,
            maxPendingBytes: 500,
            maxRecordBytes: 400,
            maxBatchRecords: 1,
            maxBatchBytes: 500,
          ),
        ),
      );
      final logs = Context().withChronicler(chronicler.recorder).logs;

      logs.info('x' * 150);
      await Future<void>.delayed(Duration.zero);
      logs.info('x' * 150);

      expect(chronicler.diagnosticCounts[DiagnosticReason.queueFull], BigInt.one);
      exporter.attempts.single.completer.complete(const ExportResult.accepted());
    });

    test('should use payload-free fallbacks when error text conversion fails', () async {
      final exporter = TestExporter();
      final chronicler = Chronicler(
        appId: 'app',
        release: 'release',
        source: ChroniclerSource.server,
        exporter: exporter,
        options: const ChroniclerOptions(
          delivery: DeliveryOptions(maxBatchRecords: 1),
        ),
      );
      final logs = Context().withChronicler(chronicler.recorder).logs;

      logs.error('failed', error: _ThrowingText(), stackTrace: _ThrowingStack());
      await Future<void>.delayed(Duration.zero);

      final record = exporter.batches.single.records.single as LogRecord;
      expect(record.payload.error?.message, '[Error message unavailable]');
      expect(record.payload.error?.stackTrace, '[Stack trace unavailable]');
      expect(chronicler.diagnosticCounts[DiagnosticReason.textConversionFailed], BigInt.two);
    });
  });
}

final class _ThrowingText {
  @override
  String toString() => throw StateError('sensitive');
}

final class _ThrowingStack implements StackTrace {
  @override
  String toString() => throw StateError('sensitive');
}
