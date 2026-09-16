import 'dart:convert';

import 'package:artificer_core/src/errors.dart';
import 'package:artificer_core/src/generation/generation.dart';
import 'package:artificer_core/src/json/json_value.dart';
import 'package:artificer_core/src/messages/messages.dart';
import 'package:artificer_core/src/native.dart';
import 'package:artificer_core/src/protocols/responses/responses_models.dart';
import 'package:artificer_core/src/protocols/text_request_policy.dart';
import 'package:artificer_core/src/tools/tools.dart';
import 'package:conflux/result.dart';
import 'package:dart_mappable/dart_mappable.dart';

/// Explicit compatible-provider policy, separate from model IDs and credentials.
final class ResponsesDialect {
  /// Creates routing and finite dialect hooks owned by the provider package.
  const ResponsesDialect({
    required this.providerId,
    required this.route,
    required this.authentication,
    this.api = 'responses',
    this.instructionRole,
    this.eventAliases = const {},
    this.hostedToolTypes = const {},
    this.unsupportedSchemaKeywords = const {},
    this.validateSchema,
    this.nativeError,
    this.toolItem,
  });

  /// Provider identity used for native tagging and replay checks.
  final String providerId;

  /// API/dialect identity, independent of any vendor name.
  final String api;

  /// Computes the absolute text endpoint without discovery.
  final Uri Function(String modelId) route;

  /// Reads explicitly supplied credentials/routing headers per execution.
  final Map<String, Object?> Function() authentication;

  /// Null uses the instructions field; otherwise inserts this native input role.
  final String? instructionRole;

  /// Maps provider event names to the standard Responses event vocabulary.
  final Map<String, String> eventAliases;

  /// Pinned hosted/custom tool discriminators admitted by this provider.
  final Set<String> hostedToolTypes;

  /// Known unsupported JSON Schema keywords; never silently removed.
  final Set<String> unsupportedSchemaKeywords;

  /// Optional endpoint-specific schema validation without rewriting the schema.
  final AiError? Function(Map<String, Object?> schema)? validateSchema;

  /// Decodes a native error envelope, for non-2xx and successful HTTP responses.
  final ProviderError? Function(Map<String, Object?> envelope, ResponseMetadata? metadata)?
  nativeError;

  /// Normalizes provider-specific application/native actions or hosted records.
  final Result<OutputPart, AiError>? Function(Map<String, Object?> item)? toolItem;
}

/// Pure common/native conversion; model execution calls this same normalizer.
final class ResponsesCodec {
  /// Creates a codec with explicit provider hooks.
  const ResponsesCodec(this.dialect);

  /// Provider-owned dialect and scope policy.
  final ResponsesDialect dialect;

  static const _typedFields = {
    'model',
    'input',
    'instructions',
    'tools',
    'tool_choice',
    'text',
    'max_output_tokens',
    'temperature',
    'top_p',
    'stream',
    'store',
  };

  /// Converts explicit common history without continuation state or tool execution.
  Result<ResponsesRequest, AiError> encode(
    GenerationRequest request,
    String modelId, {
    GenerationOptions defaults = const GenerationOptions(),
    ResponsesOptions options = const ResponsesOptions(),
    ResponsesOptions nativeDefaults = const ResponsesOptions(),
  }) {
    final invalid = request.validate(
      providerId: dialect.providerId,
      api: dialect.api,
      modelId: modelId,
    );
    if (invalid != null) return Failure(invalid);
    final resolved = request.options.resolve(defaults);
    final invalidOptions = resolved.validate();
    if (invalidOptions != null) return Failure(invalidOptions);
    if (resolved.stop?.isNotEmpty ?? false) {
      return const Failure(
        UnsupportedFeatureError('Responses does not support stop sequences.', feature: 'stop'),
      );
    }
    try {
      final input = <Map<String, Object?>>[];
      final calls = <String, ToolCallPart>{};
      for (final message in request.messages) {
        switch (message) {
          case UserMessage(:final parts):
            input.add({
              'role': 'user',
              'content': [
                for (final part in parts)
                  {'type': 'input_text', 'text': (part as TextInputPart).text},
              ],
            });
          case AssistantMessage(:final parts, :final replay):
            for (final part in parts.whereType<ToolCallPart>()) {
              calls[part.callId] = part;
            }
            if (replay != null) {
              for (final item in replay.items) {
                input.add(_object(item));
              }
            } else {
              for (final part in parts) {
                input.add(_portable(part));
              }
            }
          case ToolMessage(:final results):
            for (final result in results) {
              final content = result.content;
              if (content is NativeToolResultContent) {
                final nativeResult = _object(content.value);
                if (nativeResult['call_id'] != result.callId) {
                  return const Failure(
                    InvalidRequestError('Native result call identity is incompatible.'),
                  );
                }
                input.add(nativeResult);
              } else {
                final call = calls[result.callId]!;
                input.add({
                  'type': call.arguments is FreeFormToolArguments
                      ? 'custom_tool_call_output'
                      : 'function_call_output',
                  'call_id': result.callId,
                  'output': switch (content) {
                    JsonToolResultContent(:final value) => jsonEncode(value),
                    TextToolResultContent(:final parts) => [
                      for (final text in parts) {'type': 'input_text', 'text': text},
                    ],
                    NativeToolResultContent() => throw const FormatException(
                      'Unreachable native result.',
                    ),
                  },
                  if (result is ToolFailure) 'status': 'failed',
                });
              }
            }
        }
      }
      final tools = <Map<String, Object?>>[
        for (final tool in request.tools)
          {
            'type': 'function',
            'name': tool.name,
            if (tool.description != null) 'description': tool.description,
            'parameters': tool.inputSchema,
          },
        ...?options.nativeTools.resolve(nativeDefaults.nativeTools.resolve(const [])),
      ];
      final output = switch (request.output) {
        TextOutput() => <String, Object?>{'type': 'text'},
        JsonObjectOutput() => <String, Object?>{'type': 'json_object'},
        JsonSchemaOutput(:final name, :final description, :final schema) => <String, Object?>{
          'type': 'json_schema',
          'name': name,
          'description': ?description,
          'schema': schema,
        },
      };
      return Success(
        ResponsesRequest(
          model: modelId,
          input: input,
          instructions: request.instructions,
          tools: tools,
          toolChoice: switch (request.toolChoice) {
            AutoToolChoice() => 'auto',
            NoToolChoice() => 'none',
            RequiredToolChoice() => 'required',
            NamedToolChoice(:final name) => {'type': 'function', 'name': name},
          },
          text: {'format': output},
          maxOutputTokens: resolved.maxOutputTokens,
          temperature: resolved.temperature,
          topP: resolved.topP,
          extraBody:
              options.extraBody.resolve(nativeDefaults.extraBody.resolve(const {})) ?? const {},
        ),
      );
    } on FormatException {
      return const Failure(InvalidRequestError('History contains incompatible native JSON.'));
    } on JsonUnsupportedObjectError {
      return const Failure(InvalidRequestError('Tool result is not JSON compatible.'));
    }
  }

  /// Produces endpoint wire JSON, enforcing the same policy for native calls.
  Result<Map<String, Object?>, AiError> prepare(ResponsesRequest request, {bool stream = false}) {
    if (request.model.isEmpty || request.input.isEmpty) {
      return const Failure(InvalidRequestError('Model and input must not be empty.'));
    }
    final optionsError = ResolvedGenerationOptions(
      maxOutputTokens: request.maxOutputTokens,
      temperature: request.temperature,
      topP: request.topP,
    ).validate();
    if (optionsError != null) return Failure(optionsError);
    final names = <String>{};
    for (final tool in request.tools) {
      if (tool['type'] == 'function') {
        if (tool['name'] is! String || tool['parameters'] is! Map<String, Object?>) {
          return const Failure(
            InvalidRequestError('Function tools require a name and object schema.'),
          );
        }
        final schemaError = _schemaError(tool['parameters']! as Map<String, Object?>);
        if (schemaError != null) return Failure(schemaError);
      }
      if (tool['name'] case final String name) {
        if (name.isEmpty || !names.add(name)) {
          return const Failure(InvalidRequestError('Conflicting tool declarations.'));
        }
      }
    }
    if (request.toolChoice == 'required' && request.tools.isEmpty) {
      return const Failure(InvalidRequestError('Required tool choice needs a declared tool.'));
    }
    if (request.toolChoice case final Map<String, Object?> choice) {
      if (choice['type'] == 'function' && !names.contains(choice['name'])) {
        return const Failure(InvalidRequestError('Named tool is not declared.'));
      }
    }
    final format = request.text?['format'];
    if (format is Map<String, Object?> && format['schema'] is Map<String, Object?>) {
      final schema = format['schema']! as Map<String, Object?>;
      final failure = _schemaError(schema);
      if (failure != null) return Failure(failure);
    }
    final input = request.instructions != null && dialect.instructionRole != null
        ? <Map<String, Object?>>[
            {
              'role': dialect.instructionRole,
              'content': [
                {'type': 'input_text', 'text': request.instructions},
              ],
            },
            ...request.input,
          ]
        : request.input;
    return TextRequestPolicy(
      typedFields: _typedFields,
      hostedToolTypes: dialect.hostedToolTypes,
      unsupportedFields: const {'stop'},
      storageField: 'store',
    ).prepare(
      native: {
        'model': request.model,
        'input': input,
        if (request.instructions != null && dialect.instructionRole == null)
          'instructions': request.instructions,
        if (request.tools.isNotEmpty) 'tools': request.tools,
        'tool_choice': ?request.toolChoice,
        'text': ?request.text,
        'max_output_tokens': ?request.maxOutputTokens,
        'temperature': ?request.temperature,
        'top_p': ?request.topP,
        if (stream) 'stream': true,
      },
      extraBody: request.extraBody,
    );
  }

  /// Decodes typed native fields once while keeping full JSON in NativePayload.
  Result<ResponsesResponse, AiError> decode(
    Map<String, Object?> data, {
    ResponseMetadata? metadata,
  }) {
    final error = errorFrom(data, metadata: metadata);
    if (error != null) return Failure(error);
    try {
      JsonValues.validate(data);
      return Success(ResponsesResponse.fromMap(data));
    } on MapperException {
      return Failure(ProtocolError('Malformed Responses response.', partialOutput: data));
    } on FormatException {
      return const Failure(ProtocolError('Responses data is not valid JSON.'));
    }
  }

  /// Applies the configured native-error hook consistently across execution paths.
  ProviderError? errorFrom(Map<String, Object?> data, {ResponseMetadata? metadata}) {
    final custom = dialect.nativeError?.call(data, metadata);
    if (custom != null) return custom;
    if (data['error'] case final Map<String, Object?> error) {
      return ProviderError(
        error['message'] is String ? error['message']! as String : 'Responses provider error.',
        code: error['code'] is String ? error['code']! as String : null,
        details: data,
        statusCode: metadata?.statusCode,
        requestId: metadata?.requestId,
      );
    }
    if (data['status'] == 'failed') {
      return ProviderError(
        'Responses operation failed.',
        details: data,
        statusCode: metadata?.statusCode,
        requestId: metadata?.requestId,
      );
    }
    return null;
  }

  /// Pure authoritative conversion, with explicit selection for native candidates.
  Result<GenerationResult, AiError> normalize(
    ResponsesResponse response,
    NativePayload raw, {
    ResponseMetadata? metadata,
    int? candidateIndex,
  }) {
    if (raw.providerId != dialect.providerId || raw.api != dialect.api) {
      return const Failure(InvalidRequestError('Native payload target differs from this codec.'));
    }
    if (response.candidates.isNotEmpty) {
      if (candidateIndex == null ||
          candidateIndex < 0 ||
          candidateIndex >= response.candidates.length) {
        return const Failure(
          InvalidRequestError('Native candidates require an explicit valid selection.'),
        );
      }
      final selected = decode(response.candidates[candidateIndex], metadata: metadata);
      return selected.flatMap((value) => normalize(value, raw, metadata: metadata));
    }
    try {
      JsonValues.validate(response.output);
      JsonValues.validate(response.usage);
      JsonValues.validate(raw.data);
    } on FormatException {
      return const Failure(ProtocolError('Native response is not JSON compatible.'));
    }
    if (response.id.isEmpty ||
        response.model.isEmpty ||
        (response.incompleteDetails?['reason'] != null &&
            response.incompleteDetails!['reason'] is! String)) {
      return const Failure(ProtocolError('Malformed response identity or finish detail.'));
    }
    final parts = <OutputPart>[];
    for (final item in response.output) {
      final decoded = normalizeItem(item);
      switch (decoded) {
        case Success(:final value):
          parts.addAll(value);
        case Failure(:final error):
          return Failure(error);
      }
    }
    Usage? usage;
    try {
      if (response.usage case final map?) {
        int? count(String name) {
          final value = map[name];
          if (value == null) return null;
          if (value is! int || value < 0) throw const FormatException('Invalid usage.');
          return value;
        }

        usage = Usage(
          inputTokens: count('input_tokens'),
          outputTokens: count('output_tokens'),
          totalTokens: count('total_tokens'),
        );
      }
    } on FormatException {
      return Failure(ProtocolError('Malformed usage.', partialOutput: raw.data));
    }
    final reason = switch (response.status) {
      'completed' =>
        parts.any((p) => p is RefusalOutputPart)
            ? FinishReason.refusal
            : parts.any((p) => p is ToolCallPart)
            ? FinishReason.toolCalls
            : FinishReason.stop,
      'incomplete' =>
        response.incompleteDetails?['reason'] == 'content_filter'
            ? FinishReason.contentFilter
            : FinishReason.outputLimit,
      'in_progress' || 'queued' || 'paused' => FinishReason.paused,
      _ => FinishReason.other,
    };
    return Success(
      GenerationResult(
        message: AssistantMessage(
          parts,
          replay: ProviderReplay(
            providerId: dialect.providerId,
            api: dialect.api,
            modelId: raw.modelId,
            items: response.output,
          ),
        ),
        finishReason: reason,
        nativeFinishReason: response.incompleteDetails?['reason'] as String? ?? response.status,
        usage: usage,
        responseId: response.id,
        native: raw,
        metadata: metadata,
      ),
    );
  }

  /// Converts one ordered native output item, preserving unknown variants.
  Result<List<OutputPart>, AiError> normalizeItem(Map<String, Object?> item) {
    final hook = dialect.toolItem?.call(item);
    if (hook != null) return hook.map((part) => [part]);
    try {
      final type = _string(item['type']);
      switch (type) {
        case 'message':
          final parts = <OutputPart>[];
          for (final content in _list(item['content'])) {
            final block = _object(content);
            switch (block['type']) {
              case 'output_text':
                parts.add(
                  TextOutputPart(
                    _string(block['text']),
                    citations: [
                      for (final citation in _list(block['annotations'] ?? const []))
                        Citation(
                          data: citation,
                          url: citation is Map<String, Object?>
                              ? _optionalString(citation['url'])
                              : null,
                        ),
                    ],
                  ),
                );
              case 'refusal':
                parts.add(RefusalOutputPart(text: _string(block['refusal'])));
              default:
                parts.add(
                  OpaqueOutputPart(providerId: dialect.providerId, api: dialect.api, data: block),
                );
            }
          }
          return Success(parts);
        case 'function_call':
          return Success([
            ToolCallPart(
              callId: _identity(item['call_id']),
              name: _identity(item['name']),
              arguments: ToolArguments.parse(_string(item['arguments'])),
            ),
          ]);
        case 'custom_tool_call':
          return Success([
            ToolCallPart(
              callId: _identity(item['call_id']),
              name: _identity(item['name']),
              arguments: FreeFormToolArguments(text: _string(item['input'])),
            ),
          ]);
        case 'reasoning':
          final summary = _list(item['summary'] ?? const []);
          if (summary.isEmpty) {
            return Success([
              OpaqueOutputPart(providerId: dialect.providerId, api: dialect.api, data: item),
            ]);
          }
          return Success([
            for (final block in summary)
              ReasoningOutputPart(summary: _string(_object(block)['text'])),
          ]);
        default:
          if (dialect.hostedToolTypes.contains(type) ||
              dialect.hostedToolTypes.contains(type.replaceFirst(RegExp(r'_call$'), ''))) {
            return Success([
              ProviderToolPart(
                id: _identity(item['id']),
                name: type,
                owner: ToolExecutionOwner.provider,
                status: switch (item['status']) {
                  'pending' || 'queued' => ToolStatus.pending,
                  'in_progress' || 'running' => ToolStatus.running,
                  'completed' => ToolStatus.completed,
                  'failed' => ToolStatus.failed,
                  _ => ToolStatus.unknown,
                },
                native: item,
              ),
            ]);
          }
          return Success([
            OpaqueOutputPart(providerId: dialect.providerId, api: dialect.api, data: item),
          ]);
      }
    } on FormatException {
      return Failure(ProtocolError('Malformed Responses output item.', partialOutput: item));
    }
  }

  Map<String, Object?> _portable(OutputPart part) => switch (part) {
    TextOutputPart(:final text, :final citations) => {
      'type': 'message',
      'role': 'assistant',
      'content': [
        {
          'type': 'output_text',
          'text': text,
          'annotations': [for (final citation in citations) citation.data],
        },
      ],
    },
    RefusalOutputPart(:final text) => {
      'type': 'message',
      'role': 'assistant',
      'content': [
        {'type': 'refusal', 'refusal': text},
      ],
    },
    ReasoningOutputPart(:final summary) => {
      'type': 'reasoning',
      'summary': [
        {'type': 'summary_text', 'text': summary},
      ],
    },
    ToolCallPart(:final callId, :final name, :final arguments) => switch (arguments) {
      JsonToolArguments(:final value, :final original) => {
        'type': 'function_call',
        'call_id': callId,
        'name': name,
        'arguments': original ?? jsonEncode(value),
      },
      MalformedToolArguments(:final original) => {
        'type': 'function_call',
        'call_id': callId,
        'name': name,
        'arguments': original,
      },
      FreeFormToolArguments(:final text) => {
        'type': 'custom_tool_call',
        'call_id': callId,
        'name': name,
        'input': text,
      },
      NativeToolArguments(:final value) => _nativeAction(value, callId),
    },
    ProviderToolPart(:final native) => _object(native),
    OpaqueOutputPart(:final providerId, :final api, :final data)
        when providerId == dialect.providerId && api == dialect.api =>
      _object(data),
    OpaqueOutputPart() => throw const FormatException('Opaque target mismatch.'),
  };

  AiError? _schemaError(Map<String, Object?> schema) {
    bool unsupported(Object? value) {
      if (value is! Map<String, Object?>) return false;
      for (final entry in value.entries) {
        if (dialect.unsupportedSchemaKeywords.contains(entry.key)) return true;
        final nested = entry.value;
        switch (entry.key) {
          case 'properties':
          case 'patternProperties':
          case r'$defs':
          case 'definitions':
          case 'dependentSchemas':
            if (nested is Map<String, Object?> && nested.values.any(unsupported)) return true;
          case 'allOf':
          case 'anyOf':
          case 'oneOf':
          case 'prefixItems':
            if (nested is List && nested.any(unsupported)) return true;
          case 'items':
          case 'additionalProperties':
          case 'unevaluatedProperties':
          case 'contains':
          case 'not':
          case 'if':
          case 'then':
          case 'else':
          case 'propertyNames':
            if (unsupported(nested)) return true;
        }
      }
      return false;
    }

    try {
      JsonValues.validate(schema);
    } on FormatException {
      return const InvalidRequestError('Invalid JSON Schema value.');
    }
    if (unsupported(schema)) {
      return const UnsupportedFeatureError('Schema uses a known unsupported construct.');
    }
    return dialect.validateSchema?.call(schema);
  }

  static Map<String, Object?> _nativeAction(Object? value, String callId) {
    final action = _object(value);
    if (action['call_id'] != callId) {
      throw const FormatException('Native action call identity mismatch.');
    }
    return action;
  }

  static String _identity(Object? value) {
    final text = _string(value);
    if (text.isEmpty) throw const FormatException('Empty identity.');
    return text;
  }

  static String? _optionalString(Object? value) => value == null ? null : _string(value);
  static Map<String, Object?> _object(Object? value) {
    if (value is! Map<String, Object?>) throw const FormatException('Expected object.');
    return value;
  }

  static List<Object?> _list(Object? value) {
    if (value is! List<Object?>) throw const FormatException('Expected list.');
    return value;
  }

  static String _string(Object? value) {
    if (value is! String) throw const FormatException('Expected string.');
    return value;
  }
}
