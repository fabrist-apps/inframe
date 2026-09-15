import 'package:chronicler/chronicler.dart';
import 'package:chronicler/src/record_validation.dart';
import 'package:chronicler/src/runtime/record_processing.dart';
import 'package:chronicler/src/runtime/tracing.dart';
import 'package:conflux/moment.dart';

import 'moments.dart';

/// Supplies deterministic dependencies and collects completed span records.
final class TraceControllerTestBed {
  TraceControllerTestBed({
    ChroniclerOptions options = const ChroniclerOptions(),
    Moment Function()? now,
    Duration Function()? elapsed,
    double Function()? nextRandom,
    String Function(String)? generateId,
  }) : diagnostics = DiagnosticChannel(options.diagnostics) {
    final codec = ChroniclerCodec(
      maxRecordBytes: options.delivery.maxRecordBytes,
    );
    controller = TraceController(
      appId: 'app',
      release: 'release',
      source: ChroniclerSource.server,
      buildId: null,
      options: options,
      validator: RecordValidator(),
      codec: codec,
      diagnostics: diagnostics,
      processor: RecordProcessor(
        codec: codec,
        redaction: options.redaction,
        maxRecordBytes: options.delivery.maxRecordBytes,
      ),
      canStart: () => true,
      collectionEnabled: () => true,
      propagationEnabled: () => true,
      now: now ?? () => utcMoment(2026),
      elapsed: elapsed ?? () => Duration.zero,
      nextRandom: nextRandom ?? () => 0,
      generateId: generateId ?? (prefix) => '${prefix}_${(++_nextId).toString().padLeft(24, '0')}',
      finalize: records.add,
    );
  }

  final DiagnosticChannel diagnostics;
  final records = <SpanRecord>[];
  late final TraceController controller;
  int _nextId = 0;

  ActiveSpan? start(String name, {ActiveSpan? parent}) => controller.start(
    parent,
    name,
    kind: SpanKind.internal,
    userId: null,
    anonymousId: null,
    sessionId: null,
    attributes: const {},
    forceRoot: false,
    remoteParent: null,
  );
}
