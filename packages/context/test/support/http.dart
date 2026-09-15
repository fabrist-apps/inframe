import 'package:context/context.dart';

final _httpKey = ContextKey<List<String>>('http');

extension HttpContext on Context {
  List<String> get http => require(_httpKey);

  Context withHttp(List<String> responses) => withBinding(_httpKey.bind(responses));
}
