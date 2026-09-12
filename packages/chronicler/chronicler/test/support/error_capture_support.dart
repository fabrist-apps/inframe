import 'package:chronicler/chronicler.dart';

import 'exporter.dart';
import 'runtime.dart';

final class ThrowingText {
  @override
  String toString() => throw StateError('sensitive');
}

final class ThrowingStack implements StackTrace {
  @override
  String toString() => throw StateError('sensitive');
}

Chronicler createErrorChronicler(TestExporter exporter, {int maxBatchRecords = 1}) =>
    closeAfterTest(
      Chronicler(
        appId: 'app',
        release: 'release',
        source: ChroniclerSource.server,
        exporter: exporter,
        options: ChroniclerOptions(
          delivery: DeliveryOptions(maxBatchRecords: maxBatchRecords),
        ),
      ),
      exporter,
    );
