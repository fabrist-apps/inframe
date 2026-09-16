import 'dart:convert';
import 'dart:io';

import 'package:artificer_core/artificer_core.dart';
import 'package:artificer_core/protocols.dart';
import 'package:artificer_core/transport.dart';
import 'package:conflux/effect.dart';
import 'package:conflux/result.dart';
import 'package:test/test.dart';

void main() {
  group('GenerationOptions', () {
    test('should resolve defaults, replace collections and clear without null wire fields', () {
      const defaults = GenerationOptions(
        temperature: Setting.set(0.8),
        stop: Setting.set(['old']),
      );
      final replacement = ['new'];
      final options = GenerationOptions(
        temperature: const Setting.clear(),
        stop: Setting.set(replacement),
      );
      final resolved = options.resolve(defaults);
      expect(resolved.toWire(), {
        'max_tokens': 4096,
        'stop': ['new'],
      });
      expect(defaults.stop.resolve(null), ['old']);
      expect(options.resolve(defaults).stop, same(replacement));
      expect(const GenerationOptions(maxOutputTokens: Setting.clear()).resolve().toWire(), isEmpty);
      expect(
        const GenerationOptions(topP: Setting.set(2)).resolve().validate(),
        isA<InvalidRequestError>(),
      );
    });
  });
  group('NativeField', () {
    test('should encode omitted, null and present fields distinctly', () {
      final body = <String, Object?>{};
      NativeField<String>.omitted().writeTo(body, 'absent');
      NativeField<String>.present(null).writeTo(body, 'null');
      NativeField<String>.present('text').writeTo(body, 'present');
      expect(body, {'null': null, 'present': 'text'});
      expect(() => NativeField<String>(isPresent: false, value: 'invalid'), throwsArgumentError);
    });
  });
  group('TextRequestPolicy', () {
    const policy = TextRequestPolicy(
      typedFields: {'model', 'messages', 'tools', 'max_tokens', 'store'},
      hostedToolTypes: {'web_search'},
      unsupportedFields: {'stop'},
      storageField: 'store',
    );
    test('should preserve neutral extras and reject scope bypasses and collisions', () {
      final native = <String, Object?>{'model': 'unknown-model'};
      final result = policy.prepare(native: native, extraBody: {'new_text_hint': 'keep'});
      expect((result as Success<Map<String, Object?>, AiError>).value, {
        'model': 'unknown-model',
        'new_text_hint': 'keep',
        'store': false,
      });
      expect(native, {'model': 'unknown-model'});
      for (final extras in <Map<String, Object?>>[
        {'model': 'replacement'},
        {'file_id': 'file'},
        {'background': true},
        {
          'new_field': {'type': 'input_image', 'url': 'image'},
        },
        {'status': 'done'},
        {
          'stop': ['end'],
        },
      ]) {
        expect(
          policy.prepare(native: native, extraBody: extras),
          isA<Failure<Map<String, Object?>, AiError>>(),
        );
      }
      expect(
        policy.prepare(
          native: {
            'tools': [
              {'type': 'unlisted'},
            ],
          },
        ),
        isA<Failure<Map<String, Object?>, AiError>>(),
      );
      expect(
        policy.prepare(
          native: {
            'tools': [
              {'type': 'web_search'},
            ],
          },
        ),
        isA<Success<Map<String, Object?>, AiError>>(),
      );
      expect(
        policy.prepare(native: {'store': true}),
        isA<Failure<Map<String, Object?>, AiError>>(),
      );
      expect(
        policy.prepare(
          native: {
            'schema': {
              'properties': {
                'file': {'type': 'string'},
              },
            },
          },
        ),
        isA<Success<Map<String, Object?>, AiError>>(),
      );
    });
    test('should perform capability and policy checks before one emitted request', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final runtime = Runtime();
      final client = ProviderHttpClient();
      addTearDown(() async {
        await client.close();
        await runtime.close();
        await server.close(force: true);
      });
      final received = <Object?>[];
      server.listen((request) async {
        received.add(jsonDecode(await utf8.decoder.bind(request).join()));
        request.response.write('{}');
        await request.response.close();
      });
      Effect<ProviderJsonResponse, AiError> invoke(
        ModelCapabilities capabilities,
        Map<String, Object?> extra,
      ) => Effect.build(($) async {
        final error = capabilities.validateRequested([ModelCapability.textGeneration]);
        if (error != null) return $(Effect.fail(error));
        final body = $.sync(policy.prepare(native: {'model': 'future-model'}, extraBody: extra));
        return $(
          client.requestJson(url: Uri.parse('http://127.0.0.1:${server.port}/'), body: body),
        );
      });
      expect(
        await runtime.run(
          invoke(
            const ModelCapabilities({
              ModelCapability.textGeneration: CapabilitySupport.unsupported,
            }),
            {},
          ),
        ),
        isA<Failed<ProviderJsonResponse, AiError>>(),
      );
      expect(
        await runtime.run(invoke(const ModelCapabilities(), {'session_id': 'forbidden'})),
        isA<Failed<ProviderJsonResponse, AiError>>(),
      );
      expect(received, isEmpty);
      expect(
        await runtime.run(invoke(const ModelCapabilities(), {'hint': 'text'})),
        isA<Succeeded<ProviderJsonResponse, AiError>>(),
      );
      expect(received, [
        {'model': 'future-model', 'hint': 'text', 'store': false},
      ]);
    });
  });
}
