import 'package:chronicler/chronicler.dart';

import 'async.dart';
import 'exporter.dart';
import 'runtime.dart';

Chronicler createEventChronicler(
  TestExporter exporter, {
  int maxBatchRecords = 1,
  ChroniclerLimits limits = const ChroniclerLimits(),
  SamplingOptions sampling = const SamplingOptions(),
}) => closeAfterTest(
  Chronicler(
    appId: 'app',
    release: 'release',
    source: ChroniclerSource.server,
    exporter: exporter,
    options: ChroniclerOptions(
      delivery: DeliveryOptions(maxBatchRecords: maxBatchRecords),
      limits: limits,
      sampling: sampling,
    ),
  ),
  exporter,
);

Future<void> waitForEventAttempts(TestExporter exporter, int count) =>
    waitForCondition(() => exporter.attempts.length >= count);

ChroniclerRecord? dropEventRecord(ChroniclerRecord record) => null;
