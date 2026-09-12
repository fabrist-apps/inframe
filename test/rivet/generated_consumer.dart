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

final class UserCode {
  const UserCode(this.value);

  final String value;
}

final class UserCodeConverter implements RivetTypeConverter<UserCode, String> {
  const UserCodeConverter();

  @override
  UserCode fromSql(String value) => UserCode(value);

  @override
  String toSql(UserCode value) => value.value;
}

@RivetTable(schema: 'fbr119')
final class ScalarValues extends RivetTableDefinition<ScalarValues> {
  static const db = _$ScalarValuesDB();

  late final id = chronoID(prefix: 'usr')();
  late final count = integer()();
  late final score = real()();
  late final active = boolean()();
  late final createdAt = dateTime()();
  late final payload = json()();
  late final code = text().map(const UserCodeConverter())();
  late final optionalCode = text().map(const UserCodeConverter()).nullable()();
}

@RivetDatabase(name: 'rivet_test', tables: [UserProfiles, Posts, ScalarValues])
final class RivetTestDatabase extends _$RivetTestDatabase {}
