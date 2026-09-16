import 'dart:convert';

import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/src/protocols/chat/chat_codec.dart';
import 'package:artificer_core/src/protocols/chat/chat_dialect.dart';
import 'package:artificer_core/src/protocols/chat/chat_stream.dart';
import 'package:artificer_core/transport.dart';
import 'package:conflux/result.dart';
import 'package:test/test.dart';

void main() {
  group('ChatStreamAssembly response byte limit', () {
    final codec = ChatCodec(
      ChatDialect(providerId: 'test', api: 'chat', endpoint: Uri.parse('http://localhost/chat')),
    );

    test(
      'should count escaped fragments, split surrogates and replaced nested metadata exactly',
      () {
        final fragments = ['quote"\n\\', '\ud83d', '\ude00', 'é', '\u0001'];
        final frames = <Map<String, Object?>>[];
        final snapshots = <Map<String, Object?>>[];
        final content = StringBuffer();
        for (var i = 0; i < fragments.length; i++) {
          content.write(fragments[i]);
          final metadata = i.isEven
              ? {
                  'nested': [null, true, 'x' * 80],
                }
              : {'short': 1};
          frames.add({
            'vendor': metadata,
            'choices': [
              {
                'index': 0,
                'delta': {'content': fragments[i]},
              },
            ],
          });
          snapshots.add({
            'model': 'm' * 1000,
            'vendor': metadata,
            'choices': [
              {
                'index': 0,
                'message': {'role': 'assistant', 'content': content.toString()},
                'finish_reason': null,
              },
            ],
          });
        }
        verifyLimits(codec, frames, snapshots);
      },
    );

    test(
      'should count growing function fields, repeated IDs and multiple native tools exactly',
      () {
        final frames = <Map<String, Object?>>[];
        final snapshots = <Map<String, Object?>>[];
        for (var i = 0; i < 3; i++) {
          frames.add({
            'choices': [
              {
                'index': 0,
                'delta': {
                  'tool_calls': [
                    {
                      'index': 3,
                      'id': 'call',
                      'function': {
                        'name': 'f',
                        'arguments': '\n"',
                        'extra': {'n': i},
                      },
                    },
                    {
                      'index': 1,
                      'type': 'native',
                      'payload': [i, 'é'],
                    },
                  ],
                },
              },
            ],
          });
          snapshots.add({
            'model': 'm' * 1000,
            'choices': [
              {
                'index': 0,
                'message': {
                  'role': 'assistant',
                  'tool_calls': [
                    {
                      'type': 'native',
                      'payload': [i, 'é'],
                    },
                    {
                      'type': 'function',
                      'id': 'call',
                      'function': {
                        'name': 'f' * (i + 1),
                        'arguments': '\n"' * (i + 1),
                        'extra': {'n': i},
                      },
                    },
                  ],
                },
                'finish_reason': null,
              },
            ],
          });
        }
        verifyLimits(codec, frames, snapshots);
      },
    );
  });
}

void verifyLimits(
  ChatCodec codec,
  List<Map<String, Object?>> frames,
  List<Map<String, Object?>> snapshots,
) {
  final sizes = snapshots.map((snapshot) => utf8.encode(jsonEncode(snapshot)).length).toList();
  for (final size in sizes) {
    for (final limit in [size - 1, size, size + 1]) {
      final state = ChatStreamAssembly(codec, 'm' * 1000, maxResponseBytes: limit)
        ..start(const ResponseMetadata(statusCode: 200));
      for (var i = 0; i < frames.length; i++) {
        final result = state.accept(SseEvent(data: jsonEncode(frames[i])));
        if (sizes[i] > limit) {
          expect(
            result,
            isA<Failure<List<GenerationEvent>, AiError>>().having(
              (failure) => failure.error,
              'error',
              isA<ResponseLimitError>(),
            ),
            reason: 'frame $i, limit $limit, encoded size ${sizes[i]}',
          );
          break;
        }
        expect(
          result,
          isA<Success<List<GenerationEvent>, AiError>>(),
          reason: 'frame $i, limit $limit, encoded size ${sizes[i]}',
        );
      }
    }
  }
}
