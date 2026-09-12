import 'package:rivet/rivet.dart';

part 'generated_consumer.g.dart';

@RivetTable(schema: 'fbr116', name: 'userProfiles')
final class UserProfiles extends RivetTableDefinition<UserProfiles> {
  static const db = _$UserProfilesDB();

  late final displayName = text(name: 'displayName')();
  late final posts = many<Posts>()();
  late final _indexes = [
    index('display_name_idx').on([displayName.indexAsc()]),
  ];
  late final _constraints = [check('display_name_present', displayName.equals(''))];
}

@RivetTable(schema: 'fbr116')
final class Posts extends RivetTableDefinition<Posts> {
  static const db = _$PostsDB();

  late final authorName = text().references<UserProfiles>((users) => users.displayName)();
  late final author = one<UserProfiles>(
    fields: [authorName],
    references: (users) => [users.displayName],
  )();
}

@RivetDatabase(name: 'rivet_test', tables: [UserProfiles, Posts])
final class RivetTestDatabase extends _$RivetTestDatabase {}
