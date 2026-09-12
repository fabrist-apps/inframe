import 'package:chronicler/chronicler.dart';

import 'exporter.dart';
import 'runtime.dart';

Chronicler createTracingChronicler(TestExporter exporter, {int maxBatchRecords = 1}) =>
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
