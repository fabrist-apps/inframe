import 'package:artificer_core/json.dart';

/// One application function declaration in a native Gemini tool.
final class GoogleFunctionDeclaration {
  /// Creates a native function declaration.
  GoogleFunctionDeclaration({
    required String name,
    required this.parameters,
    this.description,
  }) : name = _nonEmpty(name, 'name');

  /// Function name.
  final String name;

  /// Optional function description.
  final String? description;

  /// JSON Schema accepted by the function.
  final JsonObject parameters;

  /// Encodes the declaration.
  JsonObject toJson() => JsonObject({
    'name': name,
    'description': ?description,
    'parameters': parameters.toDart(),
  });
}

/// One typed native Gemini tool definition.
sealed class GoogleToolDefinition {
  const GoogleToolDefinition();

  /// Function names declared by this tool, if any.
  Iterable<String> get functionNames => const [];

  /// Encodes the native tool object.
  JsonObject toJson();
}

/// Application function declarations.
final class GoogleFunctionDeclarationsTool extends GoogleToolDefinition {
  /// Creates a tool containing one or more declarations.
  GoogleFunctionDeclarationsTool(Iterable<GoogleFunctionDeclaration> declarations)
    : declarations = List.unmodifiable(declarations) {
    if (this.declarations.isEmpty) {
      throw ArgumentError.value(declarations, 'declarations', 'must not be empty');
    }
  }

  /// Ordered function declarations.
  final List<GoogleFunctionDeclaration> declarations;

  @override
  Iterable<String> get functionNames => declarations.map((value) => value.name);

  @override
  JsonObject toJson() => JsonObject({
    'functionDeclarations': declarations.map((value) => value.toJson().toDart()).toList(),
  });
}

/// Provider-hosted Google Search.
final class GoogleSearchTool extends GoogleToolDefinition {
  /// Creates Google Search with its native configuration.
  GoogleSearchTool({JsonObject? config}) : config = config ?? JsonObject({});

  /// Native search configuration.
  final JsonObject config;

  @override
  JsonObject toJson() => JsonObject({'googleSearch': config.toDart()});
}

/// Provider-hosted code execution.
final class GoogleCodeExecutionTool extends GoogleToolDefinition {
  /// Creates code execution.
  GoogleCodeExecutionTool({JsonObject? config}) : config = config ?? JsonObject({});

  /// Native code-execution configuration.
  final JsonObject config;

  @override
  JsonObject toJson() => JsonObject({'codeExecution': config.toDart()});
}

/// Provider-hosted URL context.
final class GoogleUrlContextTool extends GoogleToolDefinition {
  /// Creates URL context.
  GoogleUrlContextTool({JsonObject? config}) : config = config ?? JsonObject({});

  /// Native URL-context configuration.
  final JsonObject config;

  @override
  JsonObject toJson() => JsonObject({'urlContext': config.toDart()});
}

/// Provider-hosted File Search over existing stores.
final class GoogleFileSearchTool extends GoogleToolDefinition {
  /// Creates File Search over explicit existing store names.
  GoogleFileSearchTool(Iterable<String> storeNames) : storeNames = List.unmodifiable(storeNames) {
    if (this.storeNames.isEmpty || this.storeNames.any((value) => value.isEmpty)) {
      throw ArgumentError.value(storeNames, 'storeNames', 'must contain nonempty names');
    }
  }

  /// Existing File Search store resource names.
  final List<String> storeNames;

  @override
  JsonObject toJson() => JsonObject({
    'fileSearch': {'fileSearchStoreNames': storeNames},
  });
}

/// Provider-hosted Google Maps.
final class GoogleMapsTool extends GoogleToolDefinition {
  /// Creates Google Maps with its native configuration.
  GoogleMapsTool({JsonObject? config}) : config = config ?? JsonObject({});

  /// Native Maps configuration.
  final JsonObject config;

  @override
  JsonObject toJson() => JsonObject({'googleMaps': config.toDart()});
}

/// Provider-hosted remote MCP access.
final class GoogleRemoteMcpTool extends GoogleToolDefinition {
  /// Creates a remote MCP tool using the pinned native schema.
  GoogleRemoteMcpTool(Iterable<JsonObject> servers) : servers = List.unmodifiable(servers) {
    if (this.servers.isEmpty) {
      throw ArgumentError.value(servers, 'servers', 'must not be empty');
    }
  }

  /// Complete native remote-MCP server configurations.
  final List<JsonObject> servers;

  @override
  JsonObject toJson() => JsonObject({
    'mcpServers': servers.map((server) => server.toDart()).toList(),
  });
}

/// Computer-use actions that the application executes.
final class GoogleComputerUseTool extends GoogleToolDefinition {
  /// Creates computer use with its pinned native configuration.
  GoogleComputerUseTool(this.config);

  /// Complete native computer-use configuration.
  final JsonObject config;

  @override
  JsonObject toJson() => JsonObject({'computerUse': config.toDart()});
}

/// Legacy Google Search retrieval retained for native callers.
final class GoogleSearchRetrievalTool extends GoogleToolDefinition {
  /// Creates legacy search retrieval.
  GoogleSearchRetrievalTool(this.config);

  /// Complete legacy configuration.
  final JsonObject config;

  @override
  JsonObject toJson() => JsonObject({'googleSearchRetrieval': config.toDart()});
}

/// Native Gemini function-calling mode.
enum GoogleFunctionCallingMode {
  /// Provider default behavior.
  auto('AUTO'),

  /// Disable function calling.
  none('NONE'),

  /// Require a function call.
  any('ANY'),

  /// Require validated function arguments when supported.
  validated('VALIDATED');

  const GoogleFunctionCallingMode(this.wireValue);

  /// Native enum value.
  final String wireValue;
}

/// Native function-calling configuration.
final class GoogleFunctionCallingConfig {
  /// Creates a function-calling configuration.
  GoogleFunctionCallingConfig({
    required this.mode,
    Iterable<String> allowedFunctionNames = const [],
  }) : allowedFunctionNames = List.unmodifiable(allowedFunctionNames) {
    if (this.allowedFunctionNames.any((value) => value.isEmpty)) {
      throw ArgumentError.value(
        allowedFunctionNames,
        'allowedFunctionNames',
        'must not contain empty names',
      );
    }
    if (this.allowedFunctionNames.isNotEmpty &&
        mode != GoogleFunctionCallingMode.any &&
        mode != GoogleFunctionCallingMode.validated) {
      throw ArgumentError.value(
        allowedFunctionNames,
        'allowedFunctionNames',
        'requires ANY or VALIDATED mode',
      );
    }
  }

  /// Native mode.
  final GoogleFunctionCallingMode mode;

  /// Functions allowed when mode is ANY or VALIDATED.
  final List<String> allowedFunctionNames;

  /// Encodes the configuration.
  JsonObject toJson() => JsonObject({
    'mode': mode.wireValue,
    if (allowedFunctionNames.isNotEmpty) 'allowedFunctionNames': allowedFunctionNames,
  });
}

/// Native Gemini tool configuration.
final class GoogleToolConfig {
  /// Creates tool configuration.
  GoogleToolConfig({this.functionCallingConfig, JsonObject? extensions})
    : extensions = extensions ?? JsonObject({});

  /// Function-call selection.
  final GoogleFunctionCallingConfig? functionCallingConfig;

  /// Other pinned-schema fields.
  final JsonObject extensions;

  /// Encodes the configuration.
  JsonObject toJson() => JsonObject({
    ...extensions.toDart(),
    if (functionCallingConfig case final value?) 'functionCallingConfig': value.toJson().toDart(),
  });
}

String _nonEmpty(String value, String name) {
  if (value.isEmpty) throw ArgumentError.value(value, name, 'must not be empty');
  return value;
}
