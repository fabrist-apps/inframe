import 'package:artificer_core/src/errors.dart';
import 'package:artificer_core/src/native.dart';
import 'package:artificer_core/src/protocols/text_request_policy.dart';

/// Endpoint-specific recognition of complete Chat streams.
enum ChatTerminalPolicy {
  /// Requires the configured sentinel, normally `[DONE]`.
  sentinel,

  /// Requires selected-candidate finish metadata followed by normal EOF.
  finishThenEof,
}

/// Provider-owned routing, authentication, request inventory, and wire dialect.
/// Runtime callbacks and credentials intentionally have no persistence mapper.
final class ChatDialect {
  /// Configures one compatible endpoint without I/O or model discovery.
  ChatDialect({
    required this.providerId,
    required this.api,
    required this.endpoint,
    this.headers = const {},
    this.instructionRole = 'system',
    this.maxTokensField = 'max_tokens',
    this.reasoningField = 'reasoning_content',
    this.policy,
    this.decodeError,
    this.terminalPolicy = ChatTerminalPolicy.sentinel,
    this.sentinel = '[DONE]',
  }) {
    if (providerId.isEmpty || api.isEmpty) {
      throw ArgumentError('Provider and API identities must not be empty.');
    }
    if (!endpoint.hasScheme || !endpoint.hasAuthority) {
      throw ArgumentError.value(endpoint, 'endpoint');
    }
    if (instructionRole.isEmpty ||
        maxTokensField.isEmpty ||
        reasoningField.isEmpty ||
        sentinel.isEmpty) {
      throw ArgumentError('Dialect field names must not be empty.');
    }
  }

  /// Provider identity attached to raw and normalized results.
  final String providerId;

  /// API/replay dialect identity.
  final String api;

  /// Absolute endpoint configured by the provider.
  final Uri endpoint;

  /// Explicit authentication and routing headers.
  final Map<String, Object?> headers;

  /// Native instruction role, for example system or developer.
  final String instructionRole;

  /// Native name of the common maximum-output-token field.
  final String maxTokensField;

  /// Native public reasoning-summary field.
  final String reasoningField;

  /// Additional provider inventory and scope constraints.
  final TextRequestPolicy? policy;

  /// Optional endpoint error-envelope classifier, shared by unary and streams.
  final AiError? Function(Map<String, Object?> data, ResponseMetadata metadata)? decodeError;

  /// Endpoint-specific terminal contract.
  final ChatTerminalPolicy terminalPolicy;

  /// Exact terminal SSE data marker for sentinel-based endpoints.
  final String sentinel;
}
