import {
  MainDummyImports,
  OpfsDirectory,
  ioNotifier,
  waitForWorkerResponse,
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

const registeredFilesByWorker = new WeakMap();
let workerRequestId = 0;
let synchronousIoDepth = 0;

function registeredFiles(worker) {
  let files = registeredFilesByWorker.get(worker);
  if (files === undefined) {
    files = { paths: new Map(), handles: new Map(), sizes: new Map() };
    registeredFilesByWorker.set(worker, files);
  }
  return files;
}

function stringFromMemory(memory, pointer, length) {
  const bytes = new Uint8Array(memory.buffer, pointer >>> 0, length);
  return new TextDecoder().decode(bytes.slice());
}

export async function registerFileAtWorker(worker, path) {
  const registration = await workerRequest(worker, 'register', { path });
  if (
    !Number.isInteger(registration?.handle) ||
    registration.handle < 0 ||
    !Number.isSafeInteger(registration?.size) ||
    registration.size < 0
  ) {
    throw new Error(`The Turso OPFS worker returned an invalid handle for ${path}.`);
  }
  const files = registeredFiles(worker);
  const existingPath = files.handles.get(registration.handle);
  if (existingPath !== undefined && existingPath !== path) {
    throw new Error(`The Turso OPFS worker reused a live handle for ${path}.`);
  }
  files.paths.set(path, registration.handle);
  files.handles.set(registration.handle, path);
  files.sizes.set(registration.handle, registration.size);
}

export async function unregisterFileAtWorker(worker, path) {
  await workerRequest(worker, 'unregister', { path });
  const files = registeredFiles(worker);
  const handle = files.paths.get(path);
  files.paths.delete(path);
  if (handle !== undefined) {
    files.handles.delete(handle);
    files.sizes.delete(handle);
  }
}

function workerRequest(worker, operation, payload) {
  workerRequestId += 1;
  const id = `turso-dart-${workerRequestId}`;
  const response = waitForWorkerResponse(worker, id);
  worker.postMessage({ __turso__: operation, ...payload, id });
  return response;
}

function synchronousWorkerRequest(worker, operation, payload) {
  const signal = new Int32Array(new SharedArrayBuffer(8));
  worker.postMessage({ __turso_sync__: operation, ...payload, signal: signal.buffer });
  const waitResult = Atomics.wait(signal, 0, 0, 30_000);
  if (waitResult === 'timed-out') return -1;
  return Atomics.load(signal, 1);
}

export async function runWithSynchronousIo(action) {
  synchronousIoDepth += 1;
  try {
    return await action();
  } finally {
    synchronousIoDepth -= 1;
  }
}

// Turso's published worker registration response omits the handle. Returning it
// lets the main WASM instance resolve files that the same worker already owns.
export function setupWebWorker() {
  const opfs = new OpfsDirectory();
  let memory = null;
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
      try {
        await opfs.registerFile(event.data.path);
        const handle = opfs.lookupFileHandle(event.data.path);
        const size = opfs.size(handle);
        self.postMessage({
          __turso__: true,
          id: event.data.id,
          result: { handle, size },
        });
      } catch (error) {
        self.postMessage({ __turso__: true, id: event.data.id, error });
      }
      return;
    }
    if (event.data.__turso__ === 'unregister') {
      try {
        await opfs.unregisterFile(event.data.path);
        self.postMessage({ __turso__: true, id: event.data.id });
      } catch (error) {
        self.postMessage({ __turso__: true, id: event.data.id, error });
      }
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

// The pinned glue rejects lookup_file on the main WASM instance even after the
// IO worker has registered a file. ATTACH opens a registry miss synchronously,
// so resolve only handles confirmed by that same worker.
export async function setupMainThread(wasmFile, factory) {
  const worker = factory();
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
        return registeredFiles(worker).paths.get(path) ?? -404;
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
          const files = registeredFiles(worker);
          files.sizes.set(handle, Math.max(files.sizes.get(handle) ?? 0, offset + result));
        }
        return result;
      };
      imports.sync = (handle) => synchronousWorkerRequest(worker, 'sync', { handle });
      imports.truncate = (handle, length) => {
        const result = synchronousWorkerRequest(worker, 'truncate', { handle, len: length });
        if (result >= 0) registeredFiles(worker).sizes.set(handle, length);
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
              const files = registeredFiles(worker);
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
            if (result >= 0) registeredFiles(worker).sizes.set(handle, length);
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
