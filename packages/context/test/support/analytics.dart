import 'package:context/context.dart';

final _analyticsKey = ContextKey<List<String>>('analytics');

extension AnalyticsContext on Context {
  List<String> get analytics => require(_analyticsKey);

  Context withAnalytics(List<String> events) => withBinding(_analyticsKey.bind(events));
}
