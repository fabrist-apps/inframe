import 'package:rivet/rivet.dart';

part 'generated_consumer.g.dart';

@RivetTable(schema: 'fbr116', name: 'userProfiles')
final class UserProfiles extends RivetTableDefinition<UserProfiles> {
  static const db = _$UserProfilesDB();

  late final displayName = text(name: 'displayName')();
}

@RivetDatabase(name: 'rivet_test', tables: [UserProfiles])
final class RivetTestDatabase extends _$RivetTestDatabase {}
