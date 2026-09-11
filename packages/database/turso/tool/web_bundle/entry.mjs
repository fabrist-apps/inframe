import {
  Database as UpstreamDatabase,
  SqliteError,
  Transaction,
} from './node_modules/@tursodatabase/database-wasm/dist/promise-bundle.js';
import { MainWorker } from './node_modules/@tursodatabase/database-wasm/dist/index-bundle.js';
import {
  isWorkerUnavailable,
  registerFileAtWorker,
  runWithSynchronousIo,
  unregisterFileAtWorker,
  workerFailureFor,
} from '@tursodatabase/database-wasm-common';

function ioWorker() {
  if (MainWorker === null) {
    throw new Error('The Turso IO worker is unavailable.');
  }
  return MainWorker;
}

function registerFile(path) {
  return registerFileAtWorker(ioWorker(), path);
}

function unregisterFile(path) {
  return unregisterFileAtWorker(ioWorker(), path);
}

function workerFailure() {
  return workerFailureFor(ioWorker());
}

class Database extends UpstreamDatabase {
  constructor(path, options) {
    super(path, options);
    this.storagePath = path === ':memory:' ? null : path;
  }

  closeEngine() {
    this.db.close();
  }

  async releaseFiles() {
    const path = this.storagePath;
    if (path === null) return;

    const results = await Promise.allSettled([
      unregisterFile(path),
      unregisterFile(`${path}-wal`),
    ]);
    const failures = results
      .filter((result) => result.status === 'rejected')
      .map((result) => result.reason);
    if (failures.length !== 0) {
      throw new AggregateError(failures, `The Turso files for ${path} could not be released.`);
    }
  }

  async close() {
    this.closeEngine();
    await this.releaseFiles();
  }
}

async function connect(path, options = {}) {
  const database = new Database(path, options);
  await database.connect();
  return database;
}

export {
  Database,
  SqliteError,
  Transaction,
  connect,
  isWorkerUnavailable,
  registerFile,
  runWithSynchronousIo,
  unregisterFile,
  workerFailure,
};
