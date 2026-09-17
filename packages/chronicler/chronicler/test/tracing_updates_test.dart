import 'dart:async';

import 'package:chronicler/chronicler.dart';
import 'package:context/context.dart';
import 'package:test/test.dart';

import 'support/exporter.dart';

import 'support/tracing_support.dart';

void main() {
  setUpAll(Chronicler.initialize);
  group('Chronicler tracing updates', () {
    test('should update active attributes atomically and snapshot values', () async {
      final exporter = TestExporter();
      final chronicler = createTracingChronicler(exporter);
      final nested = <Object?>[1];

      await Context().withChronicler(chronicler.recorder).span(
        'attributes',
        (span) {
          span.tracing
            ..setAttribute('replace', 2)
            ..setAttributes({'nested': nested, 'api_token': 'secret'});
          nested.add(3);
          span.tracing.setAttributes({'valid': true, 'invalid': Object()});
        },
        attributes: {'kept': true, 'replace': 1},
      );
      await Future<void>.delayed(Duration.zero);

      final attributes = (exporter.batches.single.records.single as SpanRecord).payload.attributes;
      expect(attributes, {
        'kept': true,
        'replace': 2,
        'nested': [1],
        'api_token': '[REDACTED]',
      });
      expect(chronicler.diagnosticCounts[DiagnosticReason.invalidSpanUpdate], BigInt.one);
    });

    test('should preserve explicit errors and let cancellation take precedence', () async {
      final exporter = TestExporter();
      final cancellation = StateError('cancelled');
      final chronicler = Chronicler(
        appId: 'app',
        release: 'release',
        source: ChroniclerSource.server,
        exporter: exporter,
        options: ChroniclerOptions(
          delivery: const DeliveryOptions(maxBatchRecords: 2),
          tracing: TracingOptions(isCancellation: (error) => identical(error, cancellation)),
        ),
      );
      final context = Context().withChronicler(chronicler.recorder);

      final value = await context.span(
        'handled',
        (span) {
          span.tracing
            ..setError()
            ..setError();
          return 9;
        },
      );
      expect(value, 9);
      await expectLater(
        context.span<void>(
          'cancelled',
          (span) {
            span.tracing.setError();
            throw cancellation;
          },
        ),
        throwsA(same(cancellation)),
      );
      await Future<void>.delayed(Duration.zero);

      final records = exporter.batches.single.records.cast<SpanRecord>().toList();
      expect(records.first.payload.status, SpanStatus.error);
      expect(records.last.payload.status, SpanStatus.cancelled);
    });

    test('should contain classifier failures and preserve the application error', () async {
      final exporter = TestExporter();
      final failure = StateError('application');
      final chronicler = Chronicler(
        appId: 'app',
        release: 'release',
        source: ChroniclerSource.server,
        exporter: exporter,
        options: ChroniclerOptions(
          delivery: const DeliveryOptions(maxBatchRecords: 1),
          tracing: TracingOptions(isCancellation: (_) => throw StateError('classifier')),
        ),
      );

      await expectLater(
        Context()
            .withChronicler(chronicler.recorder)
            .span<void>(
              'failure',
              (_) => throw failure,
            ),
        throwsA(same(failure)),
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        (exporter.batches.single.records.single as SpanRecord).payload.status,
        SpanStatus.error,
      );
      expect(
        chronicler.diagnosticCounts[DiagnosticReason.cancellationClassifierFailed],
        BigInt.one,
      );
    });

    test('should diagnose updates without an active span or after completion', () async {
      final exporter = TestExporter();
      final chronicler = createTracingChronicler(exporter);
      final base = Context().withChronicler(chronicler.recorder);
      late Context retained;

      base.tracing
        ..setError()
        ..setAttribute('ignored', true);
      await base.span('ended', (span) => retained = span);
      retained.tracing
        ..setError()
        ..setAttributes({'ignored': true});
      await Future<void>.delayed(Duration.zero);

      final span = exporter.batches.single.records.single as SpanRecord;
      expect(span.payload.status, SpanStatus.success);
      expect(span.payload.attributes, isEmpty);
      expect(chronicler.diagnosticCounts[DiagnosticReason.noActiveSpan], BigInt.two);
      expect(chronicler.diagnosticCounts[DiagnosticReason.invalidSpanUpdate], BigInt.two);
    });
  });
}
