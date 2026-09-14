import 'dart:async';

import 'package:test/test.dart';
import 'package:voxel/voxel.dart';
import 'package:voxel_fixture_app/app_database.dart';
import 'package:voxel_fixture_app/fixture_app.voxel_migrations.dart';

void main() {
  group('Voxel transactions and shutdown', () {
    late VoxelDb database;

    setUp(() async {
      database = await FixtureAppDatabase().open(
        storage: const VoxelStorage.memory(),
      );
      await VoxelTesting.execute(
        database,
        "INSERT INTO content.authors VALUES ('author-1', 'Ada')",
      );
    });

    tearDown(() => database.close());

    test('should commit through the transaction executor and expire it', () async {
      late VoxelTransaction expired;
      final name = await database.transaction((transaction) async {
        expired = transaction;
        await VoxelTesting.execute(
          transaction,
          "INSERT INTO content.authors VALUES ('author-2', 'Grace')",
        );
        return VoxelTesting.scalarText(
          transaction,
          "SELECT name AS value FROM content.authors WHERE id = 'author-2'",
        );
      });

      expect(name, 'Grace');
      await expectLater(
        VoxelTesting.scalarInt(expired, 'SELECT 1 AS value'),
        throwsA(isA<VoxelExecutorClosedException>()),
      );
      expect(
        await VoxelTesting.scalarInt(
          database,
          'SELECT COUNT(*) AS value FROM content.authors',
        ),
        2,
      );
    });

    test('should roll back callback failures and preserve their identity', () async {
      final failure = StateError('rollback');

      await expectLater(
        database.transaction<void>((transaction) async {
          await VoxelTesting.execute(
            transaction,
            "INSERT INTO content.authors VALUES ('author-2', 'Grace')",
          );
          throw failure;
        }),
        throwsA(same(failure)),
      );
      expect(
        await VoxelTesting.scalarInt(
          database,
          'SELECT COUNT(*) AS value FROM content.authors',
        ),
        1,
      );
    });

    test('should reject root work inside its own transaction', () async {
      await database.transaction((transaction) async {
        await expectLater(
          VoxelTesting.scalarInt(database, 'SELECT 1 AS value'),
          throwsA(isA<VoxelExecutorClosedException>()),
        );
        await expectLater(
          database.transaction<void>((_) async {}),
          throwsA(isA<VoxelExecutorClosedException>()),
        );
        expect(
          await VoxelTesting.scalarInt(transaction, 'SELECT 1 AS value'),
          1,
        );
      });
    });

    test('should reject reentrant close before changing lifecycle state', () async {
      await database.transaction((transaction) async {
        expect(
          database.close,
          throwsA(isA<VoxelExecutorClosedException>()),
        );
        expect(
          await VoxelTesting.scalarInt(transaction, 'SELECT 1 AS value'),
          1,
        );
      });

      expect(await VoxelTesting.scalarInt(database, 'SELECT 1 AS value'), 1);
    });

    test('should drain accepted work and share repeated close completion', () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      final transaction = database.transaction<void>((transaction) async {
        entered.complete();
        await release.future;
        await VoxelTesting.scalarInt(transaction, 'SELECT 1 AS value');
      });
      await entered.future;

      final firstClose = database.close();
      final secondClose = database.close();
      var closed = false;
      unawaited(firstClose.then((_) => closed = true));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(closed, isFalse);
      await expectLater(
        VoxelTesting.scalarInt(database, 'SELECT 1 AS value'),
        throwsA(isA<VoxelExecutorClosedException>()),
      );

      release.complete();
      await transaction;
      await Future.wait([firstClose, secondClose]);
      expect(closed, isTrue);
    });

    test('should drain root SQL accepted before external close', () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      final transaction = database.transaction<void>((transaction) async {
        entered.complete();
        await release.future;
      });
      await entered.future;

      final acceptedSql = VoxelTesting.scalarInt(database, 'SELECT 1 AS value');
      final close = database.close();
      var closed = false;
      unawaited(close.then((_) => closed = true));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(closed, isFalse);

      release.complete();
      await transaction;
      expect(await acceptedSql, 1);
      await close;
      expect(closed, isTrue);
    });
  });

  group('Voxel afterCommit', () {
    late VoxelDb database;

    setUp(() async {
      database = await FixtureAppDatabase().open(
        storage: const VoxelStorage.memory(),
      );
    });

    tearDown(() => database.close());

    test('should release the reservation then await callbacks in order', () async {
      final events = <String>[];
      final result = await database.transaction((transaction) async {
        transaction
          ..afterCommit(() => events.add('sync'))
          ..afterCommit(() async {
            events.add(
              await VoxelTesting.scalarText(
                database,
                "SELECT 'root' AS value",
              ),
            );
          })
          ..afterCommit(() async {
            await database.transaction<void>((nested) async {
              events.add(
                await VoxelTesting.scalarText(
                  nested,
                  "SELECT 'nested' AS value",
                ),
              );
            });
          });
        return 42;
      });

      expect(result, 42);
      expect(events, ['sync', 'root', 'nested']);
    });

    test('should discard callbacks on rollback', () async {
      var called = false;
      await expectLater(
        database.transaction<void>((transaction) async {
          transaction.afterCommit(() => called = true);
          throw StateError('rollback');
        }),
        throwsStateError,
      );
      expect(called, isFalse);
    });

    test('should reject registration through an expired transaction', () async {
      late VoxelTransaction expired;
      await database.transaction<void>((transaction) async {
        expired = transaction;
      });

      expect(
        () => expired.afterCommit(() {}),
        throwsA(isA<VoxelExecutorClosedException>()),
      );
    });

    test('should continue callbacks and aggregate committed failures', () async {
      final events = <String>[];

      await expectLater(
        database.transaction<void>((transaction) async {
          transaction
            ..afterCommit(() => throw StateError('first'))
            ..afterCommit(() => events.add('continued'))
            ..afterCommit(() async => throw ArgumentError('last'));
        }),
        throwsA(
          isA<AfterCommitException>()
              .having((error) => error.alreadyCommitted, 'alreadyCommitted', isTrue)
              .having((error) => error.failures, 'failures', hasLength(2)),
        ),
      );
      expect(events, ['continued']);
    });

    test('should run database callbacks immediately', () async {
      final transactionEntered = Completer<void>();
      final releaseTransaction = Completer<void>();
      final unrelatedTransaction = database.transaction<void>((transaction) async {
        transactionEntered.complete();
        await releaseTransaction.future;
      });
      addTearDown(() async {
        if (!releaseTransaction.isCompleted) releaseTransaction.complete();
        await unrelatedTransaction;
      });
      await transactionEntered.future;

      final completed = Completer<void>();
      await database
          .afterCommit(() async {
            await Future<void>.delayed(const Duration(milliseconds: 10));
            completed.complete();
          })
          .timeout(const Duration(seconds: 1));
      expect(completed.isCompleted, isTrue);
      final failure = StateError('immediate');
      await expectLater(
        database.afterCommit(() => throw failure),
        throwsA(same(failure)),
      );

      releaseTransaction.complete();
      await unrelatedTransaction;
    });

    test('should reject root registration inside its own transaction', () async {
      await database.transaction<void>((transaction) async {
        await expectLater(
          database.afterCommit(() {}),
          throwsA(isA<VoxelExecutorClosedException>()),
        );
      });
    });

    test('should reject reentrant callback close without closing database', () async {
      await expectLater(
        database.transaction<void>((transaction) async {
          transaction.afterCommit(database.close);
        }),
        throwsA(
          isA<AfterCommitException>()
              .having((error) => error.alreadyCommitted, 'alreadyCommitted', isTrue)
              .having(
                (error) => error.failures.single.error,
                'failure',
                isA<VoxelExecutorClosedException>(),
              ),
        ),
      );
      expect(await VoxelTesting.scalarInt(database, 'SELECT 1 AS value'), 1);
    });

    test('should reject close from an immediate database callback', () async {
      await expectLater(
        database.afterCommit(database.close),
        throwsA(isA<VoxelExecutorClosedException>()),
      );
      expect(await VoxelTesting.scalarInt(database, 'SELECT 1 AS value'), 1);
    });

    test('should drain an accepted database callback during close', () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      final callback = database.afterCommit(() async {
        entered.complete();
        await release.future;
      });
      await entered.future;

      final close = database.close();
      var closed = false;
      unawaited(close.then((_) => closed = true));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(closed, isFalse);

      release.complete();
      await callback;
      await close;
      expect(closed, isTrue);
    });

    test('should retain committed state when external close rejects callback SQL', () async {
      final callbackEntered = Completer<void>();
      final releaseCallback = Completer<void>();
      final transaction = database.transaction<void>((transaction) async {
        transaction.afterCommit(() async {
          callbackEntered.complete();
          await releaseCallback.future;
          await VoxelTesting.scalarInt(database, 'SELECT 1 AS value');
        });
      });
      await callbackEntered.future;

      final close = database.close();
      releaseCallback.complete();
      await expectLater(
        transaction,
        throwsA(
          isA<AfterCommitException>()
              .having((error) => error.alreadyCommitted, 'alreadyCommitted', isTrue)
              .having(
                (error) => error.failures.single.error,
                'failure',
                isA<VoxelExecutorClosedException>(),
              ),
        ),
      );
      await close;
    });
  });
}
