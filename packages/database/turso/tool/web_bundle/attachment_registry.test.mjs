import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

import {
  OpfsDirectory,
  assertOpfsDirectoryCompatibility,
  respondToAsyncOperation,
} from './wasm_common_patch.mjs';

const source = await readFile(new URL('../../web/turso_attachment_registry.js', import.meta.url));
const { AttachmentRegistry, AttachmentRegistryError } = await import(
  `data:text/javascript;base64,${source.toString('base64')}`
);

test('a WAL registration failure releases only the new registration', async () => {
  const calls = [];
  const registry = registryWith({
    calls,
    registerFile: async (path) => {
      calls.push(['register', path]);
      if (path.endsWith('-wal')) throw new Error('WAL is locked');
    },
  });

  await assert.rejects(() => registry.acquire('new.db'), /WAL is locked/);
  assert.deepEqual(calls, [
    ['register', 'new.db'],
    ['register', 'new.db-wal'],
    ['unregister', 'new.db-wal'],
    ['unregister', 'new.db'],
  ]);
});

test('a cleanup failure preserves both registration errors', async () => {
  const registry = registryWith({
    registerFile: async (path) => {
      if (path.endsWith('-wal')) throw new Error('WAL is locked');
    },
    unregisterFile: async () => {
      throw new Error('cleanup failed');
    },
  });

  await assert.rejects(
    () => registry.acquire('new.db'),
    (error) =>
      error instanceof AttachmentRegistryError &&
      error.primaryError.message === 'WAL is locked' &&
      error.cleanupError instanceof AggregateError,
  );
});

test('failed last-owner release retains retryable ownership', async () => {
  let fail = true;
  const calls = [];
  const registry = registryWith({
    calls,
    unregisterFile: async (path) => {
      calls.push(['unregister', path]);
      if (fail && path === 'shared.db') throw new Error('close failed');
    },
  });
  registry.rememberAttachment({ alias: 'first', filename: 'shared.db' });

  await assert.rejects(() => registry.releaseAlias('first'), /could not be released/);
  fail = false;
  await registry.releaseAlias('first');
  assert.deepEqual(calls, [
    ['unregister', 'shared.db-wal'],
    ['unregister', 'shared.db'],
    ['unregister', 'shared.db-wal'],
    ['unregister', 'shared.db'],
  ]);
});

test('multiple aliases and the main database never double-register', async () => {
  const calls = [];
  const registry = registryWith({ calls, mainDatabasePath: 'main.db' });
  assert.equal(await registry.acquire('main.db'), false);
  assert.equal(await registry.acquire('shared.db'), true);
  registry.rememberAttachment({ alias: 'MiXeD', filename: 'shared.db' });
  assert.equal(await registry.acquire('shared.db'), false);
  registry.rememberAttachment({ alias: 'mixed', filename: 'shared.db' });

  await registry.releaseAlias('MiXeD');
  assert.equal(calls.filter(([kind]) => kind === 'unregister').length, 0);
  await registry.releaseAlias('mixed');
  assert.deepEqual(calls, [
    ['register', 'shared.db'],
    ['register', 'shared.db-wal'],
    ['unregister', 'shared.db-wal'],
    ['unregister', 'shared.db'],
  ]);
});

test('releaseAll attempts every owned and uncertain filename', async () => {
  let fail = true;
  const calls = [];
  const registry = registryWith({
    calls,
    unregisterFile: async (path) => {
      calls.push(['unregister', path]);
      if (fail && (path === 'first.db' || path === 'uncertain.db')) {
        throw new Error(`${path} failed`);
      }
    },
  });
  registry.rememberAttachment({ alias: 'first', filename: 'first.db' });
  registry.rememberAttachment({ alias: 'second', filename: 'second.db' });

  await assert.rejects(() => registry.releaseAll(['uncertain.db']), AggregateError);
  assert.deepEqual(
    calls.map(([, path]) => path),
    [
      'first.db-wal',
      'first.db',
      'second.db-wal',
      'second.db',
      'uncertain.db-wal',
      'uncertain.db',
    ],
  );

  fail = false;
  calls.length = 0;
  await registry.releaseAll();
  assert.deepEqual(
    calls.map(([, path]) => path),
    ['first.db-wal', 'first.db', 'uncertain.db-wal', 'uncertain.db'],
  );
});

test('async worker operations report failures immediately', () => {
  const replies = [];
  respondToAsyncOperation(
    { id: 'request-1' },
    () => {
      throw new Error('read failed');
    },
    (reply) => replies.push(reply),
  );
  assert.deepEqual(replies, [
    {
      __turso__: true,
      id: 'request-1',
      error: { message: 'read failed' },
    },
  ]);
});

test('the pinned OPFS directory exposes the fields used by registration', () => {
  assert.doesNotThrow(() => assertOpfsDirectoryCompatibility(new OpfsDirectory()));
  assert.throws(
    () =>
      assertOpfsDirectoryCompatibility({
        fileByPath: new Map(),
        fileByHandle: new Map(),
        fileHandleNo: undefined,
      }),
    /incompatible/,
  );
});

function registryWith({
  calls = [],
  mainDatabasePath = 'main.db',
  registerFile = async (path) => calls.push(['register', path]),
  unregisterFile = async (path) => calls.push(['unregister', path]),
}) {
  return new AttachmentRegistry({ mainDatabasePath, registerFile, unregisterFile });
}
