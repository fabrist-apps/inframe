import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

import {
  OpfsDirectory,
  assertOpfsDirectoryCompatibility,
  respondToAsyncOperation,
} from './wasm_common_patch.mjs';
import {
  normalizeOpfsFilePath,
  opfsFileExists,
  resolveOpfsFile,
} from '../../web/turso_opfs_paths.js';

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

test('attachment files cannot overlap an owned database or WAL', async () => {
  for (const mainDatabasePath of ['main.db', 'main.db-wal']) {
    const calls = [];
    const registry = registryWith({ calls, mainDatabasePath });
    const collision = mainDatabasePath === 'main.db' ? 'main.db-wal' : 'main.db';
    await assert.rejects(() => registry.acquire(collision), /overlap/);
    assert.deepEqual(calls, []);
  }

  for (const owned of ['attached.db', 'attached.db-wal']) {
    const calls = [];
    const registry = registryWith({ calls });
    registry.rememberAttachment({ alias: 'owner', filename: owned });
    const collision = owned === 'attached.db' ? 'attached.db-wal' : 'attached.db';
    await assert.rejects(() => registry.acquire(collision), /overlap/);
    assert.deepEqual(calls, []);
    assert.equal(await registry.acquire(owned), false);
  }
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

test('nested OPFS paths traverse directories and preserve the filename', async () => {
  const calls = [];
  const root = fakeDirectory({ calls });

  const file = await resolveOpfsFile(root, 'apps/example/main.db', { create: true });

  assert.equal(file.name, 'main.db');
  assert.deepEqual(calls, [
    ['directory', 'apps', true],
    ['directory', 'example', true],
    ['file', 'main.db', true],
  ]);
});

test('existence inspection never creates or opens an access handle', async () => {
  const calls = [];
  const root = fakeDirectory({ calls, existingFile: 'main.db' });

  assert.equal(await opfsFileExists(root, 'apps/example/main.db'), true);
  assert.deepEqual(calls, [
    ['directory', 'apps', false],
    ['directory', 'example', false],
    ['file', 'main.db', false],
  ]);

  calls.length = 0;
  assert.equal(await opfsFileExists(root, 'apps/example/missing.db'), false);
  assert.deepEqual(calls, [
    ['directory', 'apps', false],
    ['directory', 'example', false],
    ['file', 'missing.db', false],
  ]);
});

test('OPFS path normalization rejects ambiguous and escaping paths', () => {
  assert.equal(
    normalizeOpfsFilePath('apps/./example/../example/main.db'),
    'apps/example/main.db',
  );
  for (const path of ['', '/main.db', 'apps//main.db', '../main.db', 'apps/', 'apps\\main.db']) {
    assert.throws(() => normalizeOpfsFilePath(path), /OPFS file path/);
  }
});

function registryWith({
  calls = [],
  mainDatabasePath = 'main.db',
  registerFile = async (path) => calls.push(['register', path]),
  unregisterFile = async (path) => calls.push(['unregister', path]),
}) {
  return new AttachmentRegistry({ mainDatabasePath, registerFile, unregisterFile });
}

function fakeDirectory({ calls, existingFile }) {
  const directory = {
    async getDirectoryHandle(name, options) {
      calls.push(['directory', name, options.create]);
      return directory;
    },
    async getFileHandle(name, options) {
      calls.push(['file', name, options.create]);
      if (!options.create && name !== existingFile) {
        throw new DOMException('Missing', 'NotFoundError');
      }
      return { name };
    },
  };
  return directory;
}

test('attachment lifecycle shares canonical file ownership across encrypted URI aliases', async () => {
  const { createAttachments } = await import('../../web/turso_attachments.js');
  const calls = [];
  const attachments = createAttachments('main.db', {
    registerFile: async (path) => calls.push(['register', path]),
    unregisterFile: async (path) => calls.push(['unregister', path]),
    isWorkerUnavailable: () => false,
  }, () => assert.fail('A successful attachment must not retire the connection.'));
  const parameters = { named: false, values: [] };
  const key = 'ab'.repeat(32);
  const inspection = (filename, alias) => ({
    kind: 'attach',
    first: { form: 'direct', value: filename },
    second: { form: 'direct', value: alias },
  });
  const encrypted = inspection(`file:folder/data.db?cipher=aegis256&hexkey=${key}`, 'first');
  await attachments.complete(await attachments.prepare(encrypted, parameters));
  await attachments.complete(await attachments.prepare(inspection('folder/data.db', 'second'), parameters));
  assert.deepEqual(calls, [['register', 'folder/data.db'], ['register', 'folder/data.db-wal']]);
  await attachments.complete({ kind: 'detach', alias: 'first' });
  assert.equal(calls.length, 2);
  await attachments.complete({ kind: 'detach', alias: 'second' });
  assert.deepEqual(calls.slice(2), [['unregister', 'folder/data.db-wal'], ['unregister', 'folder/data.db']]);
  const sanitized = attachments.sanitize(new Error(`Cannot open ${encrypted.first.value}: key ${key}`), encrypted, parameters);
  assert.equal(sanitized.message, 'Cannot open [REDACTED]: key [REDACTED]');
});

test('discarding a failed ATTACH releases new files but preserves existing aliases', async () => {
  const { createAttachments } = await import('../../web/turso_attachments.js');
  const released = [];
  const attachments = createAttachments('main.db', {
    registerFile: async () => {},
    unregisterFile: async (path) => released.push(path),
    isWorkerUnavailable: () => false,
  }, () => assert.fail('A known SQL failure must not retire the connection.'));
  const parameters = { named: true, values: [[':file', 'attached.db'], [':alias', 'kept']] };
  const inspection = {
    kind: 'attach',
    first: { form: 'bound', value: ':file' },
    second: { form: 'bound', value: ':alias' },
  };
  const first = await attachments.prepare(inspection, parameters);
  await attachments.complete(first);
  await attachments.discard(await attachments.prepare(inspection, parameters));
  assert.deepEqual(released, []);
  parameters.values[0][1] = 'new.db';
  await attachments.discard(await attachments.prepare(inspection, parameters));
  assert.deepEqual(released, ['new.db-wal', 'new.db']);
  await attachments.releaseAll();
  assert.deepEqual(released.slice(2), ['attached.db-wal', 'attached.db']);
});
