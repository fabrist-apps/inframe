import 'dart:async';

import 'package:chronicler/chronicler.dart';
import 'package:context/context.dart';
import 'package:test/test.dart';

import 'support/exporter.dart';

void main() {
  setUpAll(Chronicler.initialize);
  group('Chronicler diagnostics', () {
    test('should coalesce callbacks without suppressing exact counters', () async {
      final notifications = <ChroniclerDiagnostic>[];
      late Context context;
      final chronicler = Chronicler(
        appId: 'app',
        release: 'release',
        source: ChroniclerSource.server,
        exporter: TestExporter(),
        options: ChroniclerOptions(
          delivery: const DeliveryOptions(maxBatchRecords: 1),
          diagnostics: DiagnosticOptions(
            notificationInterval: const Duration(milliseconds: 20),
            onDiagnostic: (diagnostic) {
              notifications.add(diagnostic);
              context.logs.info('reentrant');
              throw StateError('contained');
            },
          ),
        ),
      );
      context = Context().withChronicler(chronicler.recorder);

      context.logs.info('bad', attributes: {'bad': Object()});
      context.logs.info('also bad', attributes: {'bad': Object()});
      await Future<void>.delayed(const Duration(milliseconds: 5));

      expect(notifications, hasLength(1));
      expect(notifications.single.reason, DiagnosticReason.invalidRecord);
      expect(notifications.single.count, BigInt.two);
      expect(chronicler.diagnosticCounts[DiagnosticReason.invalidRecord], BigInt.two);
      expect(chronicler.diagnosticCounts[DiagnosticReason.reentrantRecording], BigInt.one);
      expect(notifications, everyElement(isA<ChroniclerDiagnostic>()));
    });

    test('should return an immutable counter snapshot', () {
      final chronicler = Chronicler(
        appId: 'app',
        release: 'release',
        source: ChroniclerSource.server,
        exporter: TestExporter(),
      );
      final context = Context().withChronicler(chronicler.recorder);
      context.logs.info('bad', attributes: {'bad': Object()});
      final snapshot = chronicler.diagnosticCounts;
      context.logs.info('bad again', attributes: {'bad': Object()});

      expect(snapshot[DiagnosticReason.invalidRecord], BigInt.one);
      expect(snapshot.clear, throwsUnsupportedError);
    });

    test('should reject lifecycle and configuration calls from a callback', () async {
      late Chronicler chronicler;
      final errors = <Object>[];
      chronicler = Chronicler(
        appId: 'app',
        release: 'release',
        source: ChroniclerSource.server,
        exporter: TestExporter(),
        options: ChroniclerOptions(
          diagnostics: DiagnosticOptions(
            onDiagnostic: (_) {
              for (final operation in <void Function()>[
                () => chronicler.flush(),
                () => chronicler.close(),
                () => chronicler.setCollectionEnabled(ChroniclerSignal.logs, enabled: false),
              ]) {
                try {
                  operation();
                } on Object catch (error) {
                  errors.add(error);
                }
              }
            },
          ),
        ),
      );

      Context().withChronicler(chronicler.recorder).logs.info('bad', attributes: {'bad': Object()});
      await Future<void>.delayed(Duration.zero);

      expect(errors, hasLength(3));
      expect(errors, everyElement(isA<ChroniclerConfigurationException>()));
      chronicler
        ..setCollectionEnabled(ChroniclerSignal.logs, enabled: false)
        ..setPropagationEnabled(enabled: false);
      await chronicler.close();
    });
  });
}
