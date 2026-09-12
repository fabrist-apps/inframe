import 'package:chronicler/chronicler.dart';
import 'package:test/test.dart';

import 'exporter.dart';

/// Closes a runtime after assertions, resolving exporter backpressure first.
///
/// Lifecycle tests that exercise shutdown directly retain their own cleanup.
Chronicler closeAfterTest(Chronicler chronicler, TestExporter exporter) {
  addTearDown(() async {
    exporter.acceptRemaining();
    await chronicler.close();
  });
  return chronicler;
}
