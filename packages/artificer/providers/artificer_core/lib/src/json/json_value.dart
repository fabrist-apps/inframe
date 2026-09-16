import 'dart:collection';

/// JSON serialization boundary shared by provider codecs.
abstract final class JsonValues {
  /// Rejects cycles, unsupported objects, keys and nonfinite numbers.
  /// Shared acyclic collections are permitted and never copied or frozen.
  static void validate(Object? value) {
    final active = HashSet<Object>.identity();
    void visit(Object? item) {
      if (item == null || item is String || item is bool) return;
      if (item is num) {
        if (!item.isFinite) throw const FormatException('Nonfinite JSON number.');
        return;
      }
      if (item is! List && item is! Map) {
        throw const FormatException('Unsupported JSON value.');
      }
      if (!active.add(item)) throw const FormatException('Cyclic JSON value.');
      if (item is List) {
        item.forEach(visit);
      } else if (item is Map) {
        for (final entry in item.entries) {
          if (entry.key is! String) throw const FormatException('JSON keys must be strings.');
          visit(entry.value);
        }
      }
      active.remove(item);
    }

    visit(value);
  }
}
