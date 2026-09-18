import 'package:chronicler/chronicler.dart';
import 'package:context/context.dart';
import 'package:test/test.dart';

import 'support/events_support.dart';
import 'support/exporter.dart';

void main() {
  setUpAll(Chronicler.initialize);

  group('ChroniclerContextBinding', () {
    test('should detect a recorder only in the bound context and its descendants', () {
      final chronicler = createEventChronicler(TestExporter());
      final base = Context();
      final otherKey = ContextKey<String>('other');
      final bound = base.withChronicler(chronicler.recorder);

      expect(base.hasChronicler, isFalse);
      expect(base.withBinding(otherKey.bind('sibling')).hasChronicler, isFalse);
      expect(bound.hasChronicler, isTrue);
      expect(bound.withBinding(otherKey.bind('child')).hasChronicler, isTrue);
      expect(bound.withIdentity(userId: 'user').hasChronicler, isTrue);
    });

    test('should support optional logging while preserving required lookup failures', () async {
      final exporter = TestExporter(acceptImmediately: true);
      final chronicler = createEventChronicler(exporter);
      final base = Context();
      final bound = base.withChronicler(chronicler.recorder);

      for (final context in [base, bound]) {
        if (context.hasChronicler) {
          context.logs.info('Request received', attributes: {'requestId': 'req_test'});
        }
      }
      await chronicler.flush();

      final records = exporter.batches.expand((batch) => batch.records).toList();
      expect(records, hasLength(1));
      expect((records.single as LogRecord).payload.attributes['requestId'], 'req_test');
      expect(() => base.logs, throwsA(isA<MissingContextValue>()));
    });

    test('should report the binding even after its runtime closes', () async {
      final chronicler = createEventChronicler(TestExporter(acceptImmediately: true));
      final context = Context().withChronicler(chronicler.recorder);

      await chronicler.close();

      expect(context.hasChronicler, isTrue);
    });
  });
}
