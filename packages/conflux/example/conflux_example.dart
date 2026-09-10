import 'package:conflux/conflux.dart';

void main() {
  const Option<String?> field = Some(null);

  final description = field.match(
    onSome: (value) => 'The field was supplied as $value.',
    onNone: () => 'The field was not supplied.',
  );

  if (description != 'The field was supplied as null.') {
    throw StateError('Unexpected description: $description');
  }

  const Result<int, String> count = Success(42);
  final label = count.map((value) => 'Count: $value').getOrElse((error) => 'Error: $error');
  if (label != 'Count: 42') throw StateError('Unexpected result: $label');

  final collected = Option.all<int>(const [Some(1), Some(2), Some(3)]).getOrNull();
  if (collected?.join(',') != '1,2,3') {
    throw StateError('Unexpected collection: $collected');
  }
}
