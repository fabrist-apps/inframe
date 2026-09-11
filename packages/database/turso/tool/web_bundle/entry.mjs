import {
  Database,
  SqliteError,
  Transaction,
  connect,
} from './node_modules/@tursodatabase/database-wasm/dist/promise-bundle.js';
import { MainWorker } from './node_modules/@tursodatabase/database-wasm/dist/index-bundle.js';
import {
  registerFileAtWorker,
  runWithSynchronousIo,
  unregisterFileAtWorker,
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

export {
  Database,
  SqliteError,
  Transaction,
  connect,
  registerFile,
  runWithSynchronousIo,
  unregisterFile,
};
