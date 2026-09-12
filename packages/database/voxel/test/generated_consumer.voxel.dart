// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

part of 'generated_consumer.dart';

// **************************************************************************
// VoxelTableGenerator
// **************************************************************************

/// Generated row returned by reads from 'main.users'.
final class User {
  /// Creates a row from decoded column and relation values.
  const User({
    required this.id,
    required this.displayName,
    required this.nickname,
  });

  /// Value read from `id`.
  final String id;

  /// Value read from `displayName`.
  final String displayName;

  /// Value read from `nickname`.
  final String? nickname;
}

/// Generated values accepted by mutations of 'main.users'.
final class UsersCompanion implements VoxelCompanion<Users> {
  const UsersCompanion._({
    required this.id,
    required this.displayName,
    required this.nickname,
  });

  /// Creates values for an insert, leaving defaulted columns absent.
  factory UsersCompanion.insert({
    required VoxelValue<Users, String, String> displayName,
    VoxelValue<Users, String, String> id = const VoxelValue.absent(),
    VoxelValue<Users, String?, String?> nickname = const VoxelValue.absent(),
  }) => UsersCompanion._(id: id, displayName: displayName, nickname: nickname);

  /// Creates values for an update, leaving untouched columns absent.
  factory UsersCompanion.update({
    VoxelValue<Users, String, String> id = const VoxelValue.absent(),
    VoxelValue<Users, String, String> displayName = const VoxelValue.absent(),
    VoxelValue<Users, String?, String?> nickname = const VoxelValue.absent(),
  }) => UsersCompanion._(id: id, displayName: displayName, nickname: nickname);

  /// Mutation value for `id`.
  final VoxelValue<Users, String, String> id;

  /// Mutation value for `displayName`.
  final VoxelValue<Users, String, String> displayName;

  /// Mutation value for `nickname`.
  final VoxelValue<Users, String?, String?> nickname;

  /// The generated column assignments in declaration order.
  @override
  List<VoxelAssignment<Users>> operator [](VoxelCompanionKey key) => [
    VoxelAssignment('id', id),
    VoxelAssignment('displayName', displayName),
    VoxelAssignment('nickname', nickname),
  ];
}

final class _$UsersDB extends VoxelTableAccessor<Users, User> {
  const _$UsersDB();

  @override
  VoxelTableSchema<Users, User> buildSchema() {
    Users createDefinition() {
      final definition = Users();

      return definition;
    }

    final definition = createDefinition();
    return VoxelTableSchema<Users, User>(
      schemaName: 'main',
      tableName: 'users',
      renamedFrom: 'people',
      definition: definition,
      columns: [
        definition.id as VoxelColumn<Object?>,
        definition.displayName as VoxelColumn<Object?>,
        definition.nickname as VoxelColumn<Object?>,
      ],
      columnNames: ['id', 'displayName', 'nickname'],
      createDefinition: createDefinition,
      columnsFor: (definition) => [
        definition.id as VoxelColumn<Object?>,
        definition.displayName as VoxelColumn<Object?>,
        definition.nickname as VoxelColumn<Object?>,
      ],
      decode: (values, sqlNulls) => User(
        id: definition.id.decodeValue(values[0], isSqlNull: sqlNulls[0]),
        displayName: definition.displayName.decodeValue(
          values[1],
          isSqlNull: sqlNulls[1],
        ),
        nickname: definition.nickname.decodeValue(
          values[2],
          isSqlNull: sqlNulls[2],
        ),
      ),
    );
  }
}
