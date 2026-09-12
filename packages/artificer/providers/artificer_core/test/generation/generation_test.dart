import 'package:artificer_core/artificer_core.dart';
import 'package:test/test.dart';

void main() {
  group('GenerationRequest', () {
    test('should snapshot messages and use documented defaults', () {
      final messages = <Message>[UserMessage.text('hello')];

      final request = GenerationRequest(messages: messages);
      messages.add(UserMessage.text('later'));

      expect(request.messages, hasLength(1));
      expect(request.options.maxOutputTokens, 4096);
      expect(request.options.temperature, isNull);
      expect(request.options.topP, isNull);
      expect(request.options.stopSequences, isEmpty);
    });

    test('should reject empty messages and invalid options', () {
      expect(() => GenerationRequest(messages: const []), throwsArgumentError);
      expect(() => GenerationOptions(maxOutputTokens: 0), throwsArgumentError);
      expect(() => GenerationOptions(temperature: double.nan), throwsArgumentError);
    });
  });

  group('ModelCapabilities', () {
    test('should leave unfamiliar capabilities unknown', () {
      final capabilities = ModelCapabilities({
        ModelCapability.textGeneration: CapabilitySupport.supported,
      });

      expect(capabilities[ModelCapability.textGeneration], CapabilitySupport.supported);
      expect(capabilities[ModelCapability.tools], CapabilitySupport.unknown);
    });

    test('should reject known unsupported features but allow unknown ones', () {
      final capabilities = ModelCapabilities({
        ModelCapability.tools: CapabilitySupport.unsupported,
      });

      expect(
        capabilities.validateRequested([ModelCapability.tools]),
        isA<UnsupportedFeatureError>(),
      );
      expect(capabilities.validateRequested([ModelCapability.imageInput]), isNull);
    });
  });
}
