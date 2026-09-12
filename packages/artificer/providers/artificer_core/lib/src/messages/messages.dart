/// One ordered conversation turn.
sealed class Message {
  const Message();
}

/// A caller-authored message.
final class UserMessage extends Message {
  UserMessage(Iterable<InputPart> parts) : parts = List.unmodifiable(parts) {
    if (this.parts.isEmpty) throw ArgumentError.value(parts, 'parts', 'must not be empty');
  }

  UserMessage.text(String text) : this([TextInputPart(text)]);

  final List<InputPart> parts;
}

/// A model-authored message.
final class AssistantMessage extends Message {
  AssistantMessage(Iterable<OutputPart> parts) : parts = List.unmodifiable(parts);

  final List<OutputPart> parts;

  String get text => parts.whereType<TextOutputPart>().map((part) => part.text).join();
}

/// One caller input within a message.
sealed class InputPart {
  const InputPart();
}

/// Text caller input.
final class TextInputPart extends InputPart {
  TextInputPart(this.text) {
    if (text.isEmpty) throw ArgumentError.value(text, 'text', 'must not be empty');
  }

  final String text;
}

/// One model output within a message.
sealed class OutputPart {
  const OutputPart();
}

/// Text model output.
final class TextOutputPart extends OutputPart {
  const TextOutputPart(this.text);

  final String text;
}
