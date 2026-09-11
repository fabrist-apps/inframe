const upstreamVersion = '0.8.0-pre.10';
const textEncoder = new TextEncoder();
const textDecoder = new TextDecoder();
const sqlGuard = loadSqlGuard();
const upstreamModule = import('./turso_upstream.js');

let database;
let mainDatabasePath;
let fileRegistration;
const attachedSchemas = new Map();
const attachmentOwners = new Map();
const sensitiveValues = new Set();

class InputError extends Error {}
class UnsupportedError extends Error {}
class SqlError extends Error {}
class IntegrationError extends Error {}

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
  const { Database, registerFile, runWithSynchronousIo, unregisterFile } = await upstreamModule;
  const options = {
    experimental: encryption === null ? ['attach'] : ['attach', 'encryption'],
    ...(encryption === null ? {} : encryptionOptions(encryption)),
  };
  const candidate = new Database(path, options);
  try {
    await candidate.connect();
    database = candidate;
    mainDatabasePath = persistent ? path : null;
    fileRegistration = { registerFile, runWithSynchronousIo, unregisterFile };
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
  return runStatement(sql, parameters, async (statement) => {
    statement.raw(true);
    statement.safeIntegers(true);
    const columns = statement.columns().map(({ name, type }) => [name, type ?? null]);
    const rows = (await statement.all()).map((row) => row.map(encodeValue));
    return [columns, rows];
  });
}

async function execute({ sql, parameters }) {
  requireOpen();
  return runStatement(sql, parameters, async (statement) => {
    const result = await statement.run();
    return BigInt(result.changes).toString();
  });
}

async function close() {
  if (database === undefined) return null;
  const owned = database;
  database = undefined;
  try {
    await owned.close();
  } finally {
    await releaseAllAttachments();
    mainDatabasePath = undefined;
    fileRegistration = undefined;
  }
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

async function runStatement(sql, parameters, action) {
  const inspection = await inspectSql(sql);
  const statement = await database.prepare(sql);
  let pendingAttachment;
  try {
    bind(statement, parameters);
    pendingAttachment = await prepareAttachment(inspection);
  } catch (error) {
    await closeStatementAfterFailure(statement, pendingAttachment, error);
  }

  let result;
  try {
    result =
      pendingAttachment?.kind === 'attach' && pendingAttachment.filename !== null
        ? await requireFileRegistration().runWithSynchronousIo(() => action(statement))
        : await action(statement);
  } catch (error) {
    await closeStatementAfterFailure(statement, pendingAttachment, error);
  }
  try {
    statement.close();
  } catch (_) {
    await discardAttachment(pendingAttachment);
    throw new IntegrationError(
      'The Turso statement could not be finalized; its outcome is uncertain.',
    );
  }
  try {
    await completeAttachment(pendingAttachment);
  } catch (_) {
    throw new IntegrationError('The Turso attachment registry could not release its files.');
  }
  return result;
}

async function closeStatementAfterFailure(statement, pendingAttachment, error) {
  try {
    statement.close();
  } catch (_) {
    await discardAttachment(pendingAttachment);
    throw new IntegrationError(
      'The Turso statement could not be finalized; its outcome is uncertain.',
    );
  }
  try {
    await discardAttachment(pendingAttachment);
  } catch (_) {
    throw new IntegrationError('The Turso attachment registry could not release its files.');
  }
  throw error;
}

async function prepareAttachment(inspection) {
  switch (inspection.kind) {
    case 'ordinary':
      return null;
    case 'attach': {
      const filename = directArgument(inspection.first, 'ATTACH filename');
      const alias = canonicalAlias(directArgument(inspection.second, 'ATTACH alias'));
      if (filename === ':memory:') return { kind: 'attach', alias, filename: null, acquired: false };
      if (mainDatabasePath === null) {
        throw new UnsupportedError(
          'A persistent browser database cannot be attached to an in-memory main database.',
        );
      }
      const canonicalFilename = browserFilename(filename);
      const acquired = await acquireAttachment(canonicalFilename);
      return { kind: 'attach', alias, filename: canonicalFilename, acquired };
    }
    case 'detach':
      return {
        kind: 'detach',
        alias: canonicalAlias(directArgument(inspection.first, 'DETACH alias')),
      };
    default:
      throw new IntegrationError(`Unknown SQL inspection kind: ${inspection.kind}.`);
  }
}

function directArgument(argument, label) {
  switch (argument.form) {
    case 'direct':
      return argument.value;
    case 'bound':
      throw new UnsupportedError(`${label} placeholders are not supported by this bridge asset.`);
    case 'unsupported':
      throw new UnsupportedError(`${label} must be a direct string or identifier on web.`);
    default:
      throw new IntegrationError(`Missing ${label} parser metadata.`);
  }
}

function browserFilename(filename) {
  if (
    filename.length === 0 ||
    filename.includes('/') ||
    filename.includes('\\') ||
    filename.includes('\0') ||
    filename.startsWith('file:')
  ) {
    throw new UnsupportedError(
      'A browser attachment filename must be one nonempty OPFS filename.',
    );
  }
  return filename;
}

function canonicalAlias(alias) {
  let normalized = '';
  for (const character of alias) {
    const code = character.charCodeAt(0);
    normalized += code >= 65 && code <= 90 ? String.fromCharCode(code + 32) : character;
  }
  return normalized;
}

async function acquireAttachment(filename) {
  if (filename === mainDatabasePath || attachmentOwners.has(filename)) return false;
  const registration = requireFileRegistration();
  await registration.registerFile(filename);
  try {
    await registration.registerFile(`${filename}-wal`);
  } catch (error) {
    await registration.unregisterFile(filename);
    throw error;
  }
  return true;
}

async function completeAttachment(pending) {
  if (pending === null || pending === undefined) return;
  if (pending.kind === 'detach') {
    await releaseAlias(pending.alias);
    return;
  }

  attachedSchemas.set(pending.alias, pending.filename);
  if (pending.filename === null || pending.filename === mainDatabasePath) return;
  let owners = attachmentOwners.get(pending.filename);
  if (owners === undefined) {
    owners = new Set();
    attachmentOwners.set(pending.filename, owners);
  }
  owners.add(pending.alias);
}

async function discardAttachment(pending) {
  if (pending?.kind !== 'attach' || !pending.acquired) return;
  await unregisterAttachmentFiles(pending.filename);
}

async function releaseAlias(alias) {
  if (!attachedSchemas.has(alias)) return;
  const filename = attachedSchemas.get(alias);
  attachedSchemas.delete(alias);
  if (filename === null || filename === mainDatabasePath) return;
  const owners = attachmentOwners.get(filename);
  owners?.delete(alias);
  if (owners !== undefined && owners.size !== 0) return;
  attachmentOwners.delete(filename);
  await unregisterAttachmentFiles(filename);
}

async function releaseAllAttachments() {
  const filenames = [...attachmentOwners.keys()];
  attachedSchemas.clear();
  attachmentOwners.clear();
  for (const filename of filenames) {
    await unregisterAttachmentFiles(filename);
  }
}

async function unregisterAttachmentFiles(filename) {
  const registration = requireFileRegistration();
  await registration.unregisterFile(`${filename}-wal`);
  await registration.unregisterFile(filename);
}

function requireFileRegistration() {
  if (fileRegistration === undefined) {
    throw new IntegrationError('The Turso file registration bridge is unavailable.');
  }
  return fileRegistration;
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

async function inspectSql(sql) {
  const guard = await sqlGuard;
  const bytes = textEncoder.encode(sql);
  const pointer = guard.turso_sql_guard_alloc(bytes.length);
  let inspectionPointer;
  try {
    new Uint8Array(guard.memory.buffer, pointer, bytes.length).set(bytes);
    inspectionPointer = guard.turso_sql_guard_inspect(pointer, bytes.length);
    const header = new DataView(guard.memory.buffer, inspectionPointer, 48);
    const length = header.getUint32(0, true);
    if (length < 48 || header.getUint32(4, true) !== 1) {
      throw new IntegrationError('The Turso SQL guard ABI does not match the bridge asset.');
    }
    switch (header.getUint32(8, true)) {
      case 0:
        break;
      case 1:
        throw new InputError('SQL must not be empty.');
      case 2:
        throw new InputError('SQL must contain exactly one statement.');
      case 3:
        throw new SqlError('SQL after the first statement could not be parsed.');
      default:
        throw new InputError('SQL could not be validated as UTF-8.');
    }
    return {
      kind: ['ordinary', 'attach', 'detach'][header.getUint32(12, true)],
      first: decodeInspectionArgument(guard.memory.buffer, inspectionPointer, length, header, 16),
      second: decodeInspectionArgument(guard.memory.buffer, inspectionPointer, length, header, 32),
    };
  } finally {
    if (inspectionPointer !== undefined) {
      const length = new DataView(guard.memory.buffer, inspectionPointer, 4).getUint32(0, true);
      guard.turso_sql_guard_dealloc(inspectionPointer, length);
    }
    guard.turso_sql_guard_dealloc(pointer, bytes.length);
  }
}

function decodeInspectionArgument(memory, inspectionPointer, inspectionLength, header, offset) {
  const form = ['none', 'direct', 'bound', 'unsupported'][header.getUint32(offset, true)];
  const bindingIndex = header.getUint32(offset + 4, true);
  const payloadOffset = header.getUint32(offset + 8, true);
  const payloadLength = header.getUint32(offset + 12, true);
  if (
    form === undefined ||
    payloadOffset > inspectionLength ||
    payloadLength > inspectionLength - payloadOffset
  ) {
    throw new IntegrationError('The Turso SQL guard returned invalid argument metadata.');
  }
  const value = textDecoder.decode(
    new Uint8Array(memory, inspectionPointer + payloadOffset, payloadLength),
  );
  return { form, bindingIndex, value };
}

function encodeError(error, operation) {
  let message = error instanceof Error ? error.message : String(error);
  for (const sensitiveValue of sensitiveValues) {
    message = message.replaceAll(sensitiveValue, '[REDACTED]');
  }
  if (error instanceof InputError) return { kind: 'argument', message };
  if (error instanceof UnsupportedError) return { kind: 'unsupported', message };
  if (error instanceof SqlError) return { kind: 'database', message, code: null };
  if (error instanceof IntegrationError) return { kind: 'platform', message };
  if (operation === 'open') return { kind: 'platform', message };
  return {
    kind: 'database',
    message,
    code: Number.isInteger(error?.code) ? error.code : null,
  };
}
