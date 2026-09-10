const upstreamVersion = '0.8.0-pre.10';
const textEncoder = new TextEncoder();
const sqlGuard = loadSqlGuard();
const upstreamModule = import('./turso_upstream.js');

let database;
const sensitiveValues = new Set();

class InputError extends Error {}
class UnsupportedError extends Error {}
class SqlError extends Error {}

self.onmessage = async ({ data }) => {
  const { id, operation, payload } = data;
  try {
    const result = await dispatch(operation, payload);
    self.postMessage({ id, ok: true, result });
  } catch (error) {
    self.postMessage({ id, ok: false, error: encodeError(error, operation) });
  }
};

async function dispatch(operation, payload) {
  switch (operation) {
    case 'open':
      return open(payload);
    case 'query':
      return query(payload);
    case 'execute':
      return execute(payload);
    case 'close':
      return close();
    default:
      throw new Error(`Unknown Turso worker operation: ${operation}.`);
  }
}

async function open({ path, persistent, encryption }) {
  if (database !== undefined) {
    throw new InputError('This Turso worker already owns a database.');
  }
  if (!globalThis.isSecureContext) {
    throw new UnsupportedError('Turso web requires a secure browser context.');
  }
  if (!globalThis.crossOriginIsolated || typeof SharedArrayBuffer === 'undefined') {
    throw new UnsupportedError(
      'Turso web requires cross-origin isolation with COOP and COEP headers.',
    );
  }
  if (persistent && typeof navigator.storage?.getDirectory !== 'function') {
    throw new UnsupportedError('Origin-private file storage is unavailable.');
  }
  await sqlGuard;
  const { Database } = await upstreamModule;
  const options = encryption === null ? {} : encryptionOptions(encryption);
  const candidate = new Database(path, options);
  try {
    await candidate.connect();
    database = candidate;
  } catch (error) {
    try {
      await candidate.close();
    } catch (_) {
      // The original initialization failure is the useful diagnostic.
    }
    throw error;
  }
  return {
    upstreamVersion,
    capabilities: { fts: false, vectorFunctions: true, vectorIndexes: false },
  };
}

function encryptionOptions(encryption) {
  const hexkey = encryption.key.map((byte) => byte.toString(16).padStart(2, '0')).join('');
  sensitiveValues.add(hexkey);
  sensitiveValues.add(encryption.key.join(','));
  return {
    experimental: ['encryption'],
    encryption: {
      cipher: browserCipher(encryption.cipher),
      hexkey,
    },
  };
}

function browserCipher(cipher) {
  switch (cipher) {
    case 'aes256gcm':
      return 1;
    case 'aegis256':
      return 2;
    default:
      throw new UnsupportedError(`Unsupported Turso encryption cipher: ${cipher}.`);
  }
}

async function query({ sql, parameters }) {
  requireOpen();
  await validateSql(sql);
  const statement = await database.prepare(sql);
  try {
    statement.raw(true);
    statement.safeIntegers(true);
    bind(statement, parameters);
    const columns = statement.columns().map(({ name, type }) => [name, type ?? null]);
    const rows = (await statement.all()).map((row) => row.map(encodeValue));
    return [columns, rows];
  } finally {
    statement.close();
  }
}

async function execute({ sql, parameters }) {
  requireOpen();
  await validateSql(sql);
  const statement = await database.prepare(sql);
  try {
    bind(statement, parameters);
    const result = await statement.run();
    return BigInt(result.changes).toString();
  } finally {
    statement.close();
  }
}

async function close() {
  if (database === undefined) return null;
  const owned = database;
  database = undefined;
  await owned.close();
  return null;
}

function requireOpen() {
  if (database === undefined) throw new InputError('The Turso database is closed.');
}

function bind(statement, parameters) {
  const nativeStatement = statement.stmt.must();
  const expectedCount = nativeStatement.parameterCount();
  if (!parameters.named) {
    if (parameters.values.length !== expectedCount) {
      throw new InputError(
        `Expected ${expectedCount} positional parameters, got ${parameters.values.length}.`,
      );
    }
    parameters.values.forEach((value, index) => {
      nativeStatement.bindAt(index + 1, decodeValue(value));
    });
    return;
  }

  const supplied = new Map(parameters.values.map(([name, value]) => [name, value]));
  const expected = [];
  for (let index = 1; index <= expectedCount; index += 1) {
    const name = nativeStatement.parameterName(index);
    if (name === null) {
      throw new InputError('Named parameters cannot bind an unnamed SQL placeholder.');
    }
    expected.push(name);
  }
  const expectedNames = new Set(expected);
  if (
    supplied.size !== parameters.values.length ||
    supplied.size !== expectedNames.size ||
    [...supplied.keys()].some((name) => !expectedNames.has(name))
  ) {
    throw new InputError(`Named parameters must exactly match: ${[...expectedNames].join(', ')}.`);
  }
  expected.forEach((name, index) => {
    nativeStatement.bindAt(index + 1, decodeValue(supplied.get(name)));
  });
}

function decodeValue(value) {
  if (!Array.isArray(value)) return value;
  switch (value[0]) {
    case 'integer':
      return BigInt(value[1]);
    case 'blob':
      return Uint8Array.from(value[1]);
    default:
      throw new InputError(`Unknown Turso parameter encoding: ${value[0]}.`);
  }
}

function encodeValue(value) {
  if (typeof value === 'bigint') return ['integer', value.toString()];
  if (value instanceof Uint8Array) return ['blob', Array.from(value)];
  return value;
}

async function loadSqlGuard() {
  const uri = new URL('./turso_sql_guard.wasm', import.meta.url);
  const response = await fetch(uri);
  if (!response.ok) {
    throw new Error(`Could not load the Turso SQL guard (${response.status}).`);
  }
  const bytes = await response.arrayBuffer();
  const { instance } = await WebAssembly.instantiate(bytes);
  return instance.exports;
}

async function validateSql(sql) {
  const guard = await sqlGuard;
  const bytes = textEncoder.encode(sql);
  const pointer = guard.turso_sql_guard_alloc(bytes.length);
  try {
    new Uint8Array(guard.memory.buffer, pointer, bytes.length).set(bytes);
    switch (guard.turso_sql_guard_validate(pointer, bytes.length)) {
      case 0:
        return;
      case 1:
        throw new InputError('SQL must not be empty.');
      case 2:
        throw new InputError('SQL must contain exactly one statement.');
      case 3:
        throw new SqlError('SQL after the first statement could not be parsed.');
      default:
        throw new InputError('SQL could not be validated as UTF-8.');
    }
  } finally {
    guard.turso_sql_guard_dealloc(pointer, bytes.length);
  }
}

function encodeError(error, operation) {
  let message = error instanceof Error ? error.message : String(error);
  for (const sensitiveValue of sensitiveValues) {
    message = message.replaceAll(sensitiveValue, '[REDACTED]');
  }
  if (error instanceof InputError) return { kind: 'argument', message };
  if (error instanceof UnsupportedError) return { kind: 'unsupported', message };
  if (error instanceof SqlError) return { kind: 'database', message, code: null };
  if (operation === 'open') return { kind: 'platform', message };
  return {
    kind: 'database',
    message,
    code: Number.isInteger(error?.code) ? error.code : null,
  };
}
