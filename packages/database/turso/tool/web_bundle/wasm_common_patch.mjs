import {
  MainDummyImports,
  OpfsDirectory,
  ioNotifier,
  workerImports,
} from './node_modules/@tursodatabase/database-wasm-common/dist/index.js';
import {
  MessageHandler,
  WASI,
  getDefaultContext,
  instantiateNapiModule,
  instantiateNapiModuleSync,
} from '@napi-rs/wasm-runtime';

export * from './node_modules/@tursodatabase/database-wasm-common/dist/index.js';

const workerStates = new WeakMap();
const synchronousIoWorkers = new Set();
let workerRequestId = 0;
let synchronousIoDepth = 0;

function workerState(worker) {
  let state = workerStates.get(worker);
  if (state === undefined) {
    state = {
      paths: new Map(),
      handles: new Map(),
      sizes: new Map(),
      pending: new Map(),
      mutationTail: Promise.resolve(),
      poison: null,
    };
    workerStates.set(worker, state);
    worker.addEventListener('message', (event) => receiveWorkerResponse(state, event));
    worker.addEventListener('error', (event) => {
      event.preventDefault();
      const detail = event.message ? ` ${event.message}` : '';
      poisonWorker(state, new Error(`The Turso OPFS worker stopped unexpectedly.${detail}`));
    });
    worker.addEventListener('messageerror', (event) => {
      event.preventDefault();
      poisonWorker(state, workerFailure());
    });
  }
  return state;
}

function stringFromMemory(memory, pointer, length) {
  const bytes = new Uint8Array(memory.buffer, pointer >>> 0, length);
  return new TextDecoder().decode(bytes.slice());
}

export async function registerFileAtWorker(worker, path) {
  const registration = await queueWorkerMutation(worker, 'register', { path });
  if (
    !Number.isInteger(registration?.handle) ||
    registration.handle < 0 ||
    !Number.isSafeInteger(registration?.size) ||
    registration.size < 0
  ) {
    const error = new Error(`The Turso OPFS worker returned an invalid handle for ${path}.`);
    poisonWorker(workerState(worker), error);
    throw error;
  }
  const files = workerState(worker);
  const existingPath = files.handles.get(registration.handle);
  if (existingPath !== undefined && existingPath !== path) {
    const error = new Error(`The Turso OPFS worker reused a live handle for ${path}.`);
    poisonWorker(files, error);
    throw error;
  }
  files.paths.set(path, registration.handle);
  files.handles.set(registration.handle, path);
  files.sizes.set(registration.handle, registration.size);
}

export async function unregisterFileAtWorker(worker, path) {
  await queueWorkerMutation(worker, 'unregister', { path });
  const files = workerState(worker);
  const handle = files.paths.get(path);
  files.paths.delete(path);
  if (handle !== undefined) {
    files.handles.delete(handle);
    files.sizes.delete(handle);
  }
}

function queueWorkerMutation(worker, operation, payload) {
  const state = workerState(worker);
  const request = state.mutationTail.then(() => workerRequest(worker, operation, payload));
  state.mutationTail = request.catch(() => {});
  return request;
}

function workerRequest(worker, operation, payload) {
  const state = workerState(worker);
  if (state.poison !== null) return Promise.reject(state.poison);
  workerRequestId += 1;
  const id = `turso-dart-${workerRequestId}`;
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      const error = new Error(`The Turso OPFS worker did not answer ${operation} within 30 seconds.`);
      state.pending.delete(id);
      poisonWorker(state, error);
      reject(error);
    }, 30_000);
    state.pending.set(id, { operation, resolve, reject, timer });
    try {
      worker.postMessage({ __turso__: operation, ...payload, id });
    } catch (error) {
      clearTimeout(timer);
      state.pending.delete(id);
      poisonWorker(state, error);
      reject(error);
    }
  });
}

function receiveWorkerResponse(state, event) {
  const reply = event.data;
  if (reply?.__turso__ !== true || typeof reply.id !== 'string') return;
  const pending = state.pending.get(reply.id);
  if (pending === undefined) return;
  clearTimeout(pending.timer);
  state.pending.delete(reply.id);
  if (reply.error !== undefined && reply.error !== null) {
    pending.reject(workerResponseError(reply.error, pending.operation));
  } else {
    pending.resolve(reply.result);
  }
}

function workerResponseError(value, operation) {
  const message = typeof value?.message === 'string' ? value.message : String(value);
  return new Error(`The Turso OPFS worker could not ${operation}: ${message}`);
}

function workerFailure() {
  return new Error('The Turso OPFS worker stopped unexpectedly.');
}

function poisonWorker(state, error) {
  if (state.poison !== null) return;
  state.poison = error instanceof Error ? error : new Error(String(error));
  state.poison.tursoWorkerPoisoned = true;
  for (const pending of state.pending.values()) {
    clearTimeout(pending.timer);
    pending.reject(state.poison);
  }
  state.pending.clear();
}

export function isWorkerUnavailable(error) {
  return error?.tursoWorkerPoisoned === true;
}

function synchronousWorkerRequest(worker, operation, payload) {
  const state = workerState(worker);
  if (state.poison !== null) return -1;
  const signal = new Int32Array(new SharedArrayBuffer(8));
  worker.postMessage({ __turso_sync__: operation, ...payload, signal: signal.buffer });
  const waitResult = Atomics.wait(signal, 0, 0, 30_000);
  if (waitResult === 'timed-out') {
    poisonWorker(
      state,
      new Error(`The Turso OPFS worker did not answer synchronous ${operation} within 30 seconds.`),
    );
    return -1;
  }
  return Atomics.load(signal, 1);
}

export async function runWithSynchronousIo(action) {
  synchronousIoDepth += 1;
  let result;
  let failure;
  try {
    result = await action();
  } catch (error) {
    failure = error;
  } finally {
    synchronousIoDepth -= 1;
  }
  const poisoned = [...synchronousIoWorkers]
    .map((worker) => workerState(worker).poison)
    .find((error) => error !== null);
  if (poisoned !== undefined) throw poisoned;
  if (failure !== undefined) throw failure;
  return result;
}

// Turso's published worker registration response omits the handle. Returning it
// lets the main WASM instance resolve files that the same worker already owns.
export function setupWebWorker() {
  const opfs = new OpfsDirectory();
  let memory = null;
  let mutationTail = Promise.resolve();
  const handler = new MessageHandler({
    onLoad({ wasmModule, wasmMemory }) {
      memory = wasmMemory;
      const wasi = new WASI({
        print: (...arguments_) => console.log(...arguments_),
        printErr: (...arguments_) => console.error(...arguments_),
      });
      return instantiateNapiModuleSync(wasmModule, {
        childThread: true,
        wasi,
        overwriteImports(importObject) {
          importObject.env = {
            ...importObject.env,
            ...importObject.napi,
            ...importObject.emnapi,
            ...workerImports(opfs, memory),
            memory: wasmMemory,
          };
        },
      });
    },
  });

  globalThis.onmessage = async (event) => {
    if (event.data.__turso_sync__ !== undefined) {
      const signal = new Int32Array(event.data.signal);
      let result = -1;
      try {
        switch (event.data.__turso_sync__) {
          case 'read':
            result = opfs.read(
              event.data.handle,
              new Uint8Array(memory.buffer, event.data.ptr >>> 0, event.data.len),
              event.data.offset,
            );
            break;
          case 'write':
            result = opfs.write(
              event.data.handle,
              new Uint8Array(memory.buffer, event.data.ptr >>> 0, event.data.len),
              event.data.offset,
            );
            break;
          case 'sync':
            result = opfs.sync(event.data.handle);
            break;
          case 'truncate':
            result = opfs.truncate(event.data.handle, event.data.len);
            break;
          case 'size':
            result = opfs.size(event.data.handle);
            break;
        }
      } finally {
        Atomics.store(signal, 1, result);
        Atomics.store(signal, 0, 1);
        Atomics.notify(signal, 0);
      }
      return;
    }
    if (event.data.__turso__ === 'register') {
      mutationTail = respondToMutation(mutationTail, event.data, () =>
        registerWorkerFile(opfs, event.data.path),
      );
      return;
    }
    if (event.data.__turso__ === 'unregister') {
      mutationTail = respondToMutation(mutationTail, event.data, () =>
        unregisterWorkerFile(opfs, event.data.path),
      );
      return;
    }
    if (event.data.__turso__ === 'read_async') {
      const result = opfs.read(
        event.data.handle,
        new Uint8Array(memory.buffer, event.data.ptr >>> 0, event.data.len),
        event.data.offset,
      );
      self.postMessage({ __turso__: true, id: event.data.id, result });
      return;
    }
    if (event.data.__turso__ === 'write_async') {
      const result = opfs.write(
        event.data.handle,
        new Uint8Array(memory.buffer, event.data.ptr >>> 0, event.data.len),
        event.data.offset,
      );
      self.postMessage({ __turso__: true, id: event.data.id, result });
      return;
    }
    if (event.data.__turso__ === 'sync_async') {
      const result = opfs.sync(event.data.handle);
      self.postMessage({ __turso__: true, id: event.data.id, result });
      return;
    }
    if (event.data.__turso__ === 'truncate_async') {
      const result = opfs.truncate(event.data.handle, event.data.len);
      self.postMessage({ __turso__: true, id: event.data.id, result });
      return;
    }
    handler.handle(event);
  };
}

function respondToMutation(previous, request, action) {
  const result = previous.then(action, action);
  result.then(
    (value) => self.postMessage({ __turso__: true, id: request.id, result: value }),
    (error) =>
      self.postMessage({
        __turso__: true,
        id: request.id,
        error: { message: error instanceof Error ? error.message : String(error) },
      }),
  );
  return result.catch(() => {});
}

async function registerWorkerFile(opfs, path) {
  const existing = opfs.fileByPath.get(path);
  if (existing !== undefined) {
    return { handle: existing.handle, size: existing.sync.getSize() };
  }
  const root = await navigator.storage.getDirectory();
  const file = await root.getFileHandle(path, { create: true });
  const sync = await file.createSyncAccessHandle();
  const handle = opfs.fileHandleNo + 1;
  opfs.fileHandleNo = handle;
  opfs.fileByPath.set(path, { handle, sync });
  opfs.fileByHandle.set(handle, sync);
  return { handle, size: sync.getSize() };
}

async function unregisterWorkerFile(opfs, path) {
  const file = opfs.fileByPath.get(path);
  if (file === undefined) return;
  file.sync.close();
  opfs.fileByPath.delete(path);
  opfs.fileByHandle.delete(file.handle);
}

// The pinned glue rejects lookup_file on the main WASM instance even after the
// IO worker has registered a file. ATTACH opens a registry miss synchronously,
// so resolve only handles confirmed by that same worker.
export async function setupMainThread(wasmFile, factory) {
  const worker = factory();
  workerState(worker);
  synchronousIoWorkers.add(worker);
  let completeOpfs = null;
  const context = getDefaultContext();
  const wasi = new WASI({ version: 'preview1' });
  const sharedMemory = new WebAssembly.Memory({
    initial: 4000,
    maximum: 65536,
    shared: true,
  });
  const { napiModule } = await instantiateNapiModule(wasmFile, {
    context,
    asyncWorkPoolSize: 1,
    wasi,
    onCreateWorker: () => worker,
    overwriteImports(importObject) {
      const imports = MainDummyImports(worker, (completion, result) => {
        completeOpfs(completion, result);
      });
      imports.lookup_file = (pointer, length) => {
        const path = stringFromMemory(sharedMemory, pointer, length);
        return workerState(worker).paths.get(path) ?? -404;
      };
      imports.is_web_worker = () => synchronousIoDepth > 0;
      imports.read = (handle, pointer, length, offset) =>
        synchronousWorkerRequest(worker, 'read', {
          handle,
          ptr: pointer,
          len: length,
          offset,
        });
      imports.write = (handle, pointer, length, offset) => {
        const result = synchronousWorkerRequest(worker, 'write', {
          handle,
          ptr: pointer,
          len: length,
          offset,
        });
        if (result >= 0) {
          const files = workerState(worker);
          files.sizes.set(handle, Math.max(files.sizes.get(handle) ?? 0, offset + result));
        }
        return result;
      };
      imports.sync = (handle) => synchronousWorkerRequest(worker, 'sync', { handle });
      imports.truncate = (handle, length) => {
        const result = synchronousWorkerRequest(worker, 'truncate', { handle, len: length });
        if (result >= 0) workerState(worker).sizes.set(handle, length);
        return result;
      };
      imports.size = (handle) => synchronousWorkerRequest(worker, 'size', { handle });
      imports.read_async = (handle, pointer, length, offset, completion) => {
        workerRequest(worker, 'read_async', { handle, ptr: pointer, len: length, offset }).then(
          (result) => completeOpfs(completion, result),
          () => completeOpfs(completion, -1),
        );
      };
      imports.write_async = (handle, pointer, length, offset, completion) => {
        workerRequest(worker, 'write_async', { handle, ptr: pointer, len: length, offset }).then(
          (result) => {
            if (result >= 0) {
              const files = workerState(worker);
              files.sizes.set(handle, Math.max(files.sizes.get(handle) ?? 0, offset + result));
            }
            completeOpfs(completion, result);
          },
          () => completeOpfs(completion, -1),
        );
      };
      imports.sync_async = (handle, completion) => {
        workerRequest(worker, 'sync_async', { handle }).then(
          (result) => completeOpfs(completion, result),
          () => completeOpfs(completion, -1),
        );
      };
      imports.truncate_async = (handle, length, completion) => {
        workerRequest(worker, 'truncate_async', { handle, len: length }).then(
          (result) => {
            if (result >= 0) workerState(worker).sizes.set(handle, length);
            completeOpfs(completion, result);
          },
          () => completeOpfs(completion, -1),
        );
      };
      importObject.env = {
        ...importObject.env,
        ...importObject.napi,
        ...importObject.emnapi,
        ...imports,
        memory: sharedMemory,
      };
      return importObject;
    },
    beforeInit({ instance }) {
      for (const name of Object.keys(instance.exports)) {
        if (name.startsWith('__napi_register__')) instance.exports[name]();
      }
    },
  });
  const nativeCompleteOpfs = napiModule.exports.completeOpfs;
  completeOpfs = (completion, result) => {
    nativeCompleteOpfs(completion, result);
    ioNotifier.notify();
  };
  return napiModule;
}
