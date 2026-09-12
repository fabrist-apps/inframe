/// Validates and returns an authoritative `models/{id}` embedding name.
String googleEmbeddingModelName(String name) {
  if (!name.startsWith('models/') || name.length == 7 || name.substring(7).contains('/')) {
    throw ArgumentError.value(name, 'model', 'must have the format models/{id}');
  }
  return name;
}

/// Returns the bare ID from an authoritative Google model resource name.
String googleEmbeddingModelId(String name) => googleEmbeddingModelName(name).substring(7);
