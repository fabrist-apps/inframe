import 'package:conflux/conflux.dart';
import 'package:context/context.dart';

Future<void> main() async {
  final users = _Users();
  final runtime = Runtime(context: Context().withUsers(users));
  final program = Effect.build<String, String>(($) async {
    final userId = $.sync(_parseUserId('42'));
    final connection = await $.acquireRelease(
      $.context.users.connect(),
      release: (connection) => connection.closeEffect(),
    );
    $.addFinalizer(Effect.sync((_) => users.events.add('finished')));
    return $(connection.loadUser(userId));
  });

  try {
    final exit = await runtime.run(program);
    if (exit case Succeeded<String, String>(:final value)) {
      if (value != 'User 42') throw StateError('Unexpected user: $value');
    } else {
      throw StateError('Unexpected exit: $exit');
    }
  } finally {
    await runtime.close();
  }

  if (users.events.join(',') != 'connected,finished,closed') {
    throw StateError('Unexpected lifecycle: ${users.events}');
  }
}

Result<String, String> _parseUserId(String raw) {
  return int.tryParse(raw) == null ? const Failure('Invalid ID') : Success(raw);
}

final _usersKey = ContextKey<_Users>('users');

extension _UsersContext on Context {
  _Users get users => require(_usersKey);

  Context withUsers(_Users users) => withBinding(_usersKey.bind(users));
}

final class _Users {
  final events = <String>[];

  Effect<_Connection, String> connect() {
    return Effect.sync((_) {
      events.add('connected');
      return _Connection(events);
    }).mapError((error, _) => '$error');
  }
}

final class _Connection {
  const _Connection(this.events);

  final List<String> events;

  Effect<String, String> loadUser(String id) => Effect.succeed('User $id');

  Effect<void, Never> closeEffect() => Effect.sync((_) => events.add('closed'));
}
