import 'dart:convert';

import 'package:chronicler/chronicler.dart';
import 'package:conflux/effect.dart';
import 'package:context/context.dart';
import 'package:test/test.dart';

import 'support/memory_exporter.dart';

void main() {
  setUpAll(Chronicler.initialize);
  group('Conflux Cause conversion', () {
    test('should preserve the ordered tree and the first genuine defect stack', () {
      final repeated = StateError('repeated');
      final stack = StackTrace.fromString('defect stack');
      final cause = Parallel<Object?>([
        const Expected(null),
        Sequential([
          Expected(repeated),
          Defect(repeated, stack),
          const Interrupted('stop'),
        ]),
      ]);

      final input = cause.toChroniclerError();
      final metadata = input.attributes['conflux.cause']! as Map<String, Object?>;
      final nodes = (metadata['nodes']! as List<Object?>).cast<Map<String, Object?>>();

      expect(input.error, isA<ConfluxFailure>());
      expect(input.stackTrace, same(stack));
      expect(metadata['version'], 1);
      expect(nodes.map((node) => node['kind']), [
        'parallel',
        'expected',
        'sequential',
        'expected',
        'defect',
        'interrupted',
      ]);
      expect(nodes.map((node) => node['parent']), [null, 0, 0, 2, 2, 2]);
      expect(nodes[1]['isNull'], isTrue);
      expect(nodes[3]['message'], 'Bad state: repeated');
      expect(nodes[4]['stackTrace'], 'defect stack');
      expect(nodes[5]['message'], 'stop');
      expect(metadata['nodesOmitted'], isFalse);
    });

    test('should keep expected-only failures stackless, including null', () {
      final input = const Expected<Object?>(null).toChroniclerError();

      expect(input.error, isA<ConfluxFailure>());
      expect(input.stackTrace, isNull);
      final metadata = input.attributes['conflux.cause']! as Map<String, Object?>;
      final node = (metadata['nodes']! as List<Object?>).single! as Map<String, Object?>;
      expect(node['kind'], 'expected');
      expect(node['isNull'], isTrue);
      expect(
        () => (metadata['nodes']! as List<Object?>).clear(),
        throwsUnsupportedError,
      );
    });

    test('should bound nodes and encoded metadata with visible markers', () {
      final cause = Sequential<String>([
        for (var index = 0; index < 80; index++)
          Expected('$index-${List.filled(10000, 'x').join()}'),
      ]);

      final input = cause.toChroniclerError();
      final metadata = input.attributes['conflux.cause']! as Map<String, Object?>;
      final encodedBytes = utf8.encode(jsonEncode(input.attributes)).length;

      expect((metadata['nodes']! as List<Object?>).length, lessThanOrEqualTo(64));
      expect(encodedBytes, lessThanOrEqualTo(32 * 1024));
      expect(metadata['nodesOmitted'], isTrue);
      expect(metadata['textTruncated'], isTrue);
    });

    test('should retain the first defect stack beyond the node prefix', () {
      final stack = StackTrace.fromString('late defect stack');
      final cause = Sequential<Object>([
        for (var index = 0; index < 70; index++) Expected(index),
        Defect(StateError('late defect'), stack),
      ]);

      final input = cause.toChroniclerError();
      final metadata = input.attributes['conflux.cause']! as Map<String, Object?>;

      expect(metadata['nodes']! as List<Object?>, hasLength(64));
      expect(metadata['nodesOmitted'], isTrue);
      expect(input.stackTrace, same(stack));
    });

    test('should contain throwing text conversion with explicit markers', () {
      final cause = Defect<Never>(_ThrowingText(), _ThrowingStack());

      final input = cause.toChroniclerError();
      final metadata = input.attributes['conflux.cause']! as Map<String, Object?>;
      final node = (metadata['nodes']! as List<Object?>).single! as Map<String, Object?>;

      expect(node['message'], '[Error message unavailable]');
      expect(node['stackTrace'], '[Stack trace unavailable]');
      expect(metadata['textUnavailable'], isTrue);
    });

    test('should remain pure until its input is captured explicitly', () async {
      final exporter = MemoryExporter();
      final chronicler = Chronicler(
        appId: 'app',
        release: 'test',
        source: ChroniclerSource.server,
        exporter: exporter,
      );
      addTearDown(chronicler.close);
      final context = Context().withChronicler(chronicler.recorder);

      final input = const Expected<String>('declined').toChroniclerError();
      expect(exporter.records, isEmpty);
      expect(chronicler.diagnosticCounts, isEmpty);

      context.errors.capture(
        input.error,
        stackTrace: input.stackTrace,
        attributes: input.attributes,
      );
      await chronicler.flush();

      final record = exporter.records.single as ErrorRecord;
      expect(record.payload.error.type, 'ConfluxFailure');
      expect(record.payload.attributes['conflux.cause'], isNotNull);
      expect(record.payload.causes, isEmpty);
    });
  });
}

final class _ThrowingText {
  @override
  String toString() => throw StateError('text failed');
}

final class _ThrowingStack implements StackTrace {
  @override
  String toString() => throw StateError('stack failed');
}
