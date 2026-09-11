import {
  AttachmentRegistry,
  AttachmentRegistryError,
} from './turso_attachment_registry.js';

const upstreamVersion = '0.8.0-pre.10';
const testFault = new URL(import.meta.url).searchParams.get('__turso_test_fault');
const textEncoder = new TextEncoder();
const textDecoder = new TextDecoder();
const sqlGuard = loadSqlGuard();
const upstreamModule = import('./turso_upstream.js');

let database;
let mainDatabasePath;
let fileRegistration;
let attachmentRegistry;
let testFaultConsumed = false;
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
  const {
    Database,
    isWorkerUnavailable,
    registerFile,
    runWithSynchronousIo,
    unregisterFile,
    workerFailure,
  } = await upstreamModule;
  const options = {
    experimental: encryption === null ? ['attach'] : ['attach', 'encryption'],
    ...(encryption === null ? {} : encryptionOptions(encryption)),
  };
  const candidate = new Database(path, options);
  try {
    await candidate.connect();
    database = candidate;
    mainDatabasePath = persistent ? path : null;
    fileRegistration = {
      isWorkerUnavailable,
      registerFile,
      runWithSynchronousIo,
      unregisterFile,
      workerFailure,
    };
    attachmentRegistry = new AttachmentRegistry({
      mainDatabasePath,
      registerFile: registerAttachmentFile,
      unregisterFile,
    });
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
  await shutdownDatabase();
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
  const sensitiveAttachmentValues = attachmentSensitiveValues(inspection, parameters);
  let statement;
  let pendingAttachment;
  try {
    statement = await database.prepare(sql);
    bind(statement, parameters);
    pendingAttachment = await prepareAttachment(inspection, parameters);
  } catch (error) {
    if (statement === undefined) throw sanitizeError(error, sensitiveAttachmentValues);
    await closeStatementAfterFailure(
      statement,
      pendingAttachment,
      sanitizeError(error, sensitiveAttachmentValues),
    );
  }

  let result;
  try {
    result =
      pendingAttachment?.kind === 'attach' && pendingAttachment.filename !== null
        ? await requireFileRegistration().runWithSynchronousIo(() => action(statement))
        : await action(statement);
  } catch (error) {
    if (opfsWorkerFailed()) {
      await retireAfterUncertainOutcome(
        pendingAttachment,
        'The Turso OPFS worker failed; the statement outcome is uncertain.',
      );
    }
    await closeStatementAfterFailure(
      statement,
      pendingAttachment,
      sanitizeError(error, sensitiveAttachmentValues),
    );
  }
  if (opfsWorkerFailed()) {
    await retireAfterUncertainOutcome(
      pendingAttachment,
      'The Turso OPFS worker failed; the statement outcome is uncertain.',
    );
  }
  try {
    closeCompletedStatement(statement, pendingAttachment);
  } catch (_) {
    await retireAfterUncertainOutcome(
      pendingAttachment,
      'The Turso statement could not be finalized; its outcome is uncertain.',
    );
  }
  try {
    await completeAttachment(pendingAttachment);
  } catch (_) {
    await retireAfterUncertainOutcome(
      pendingAttachment,
      'The Turso attachment registry could not release its files.',
    );
  }
  return result;
}

function closeCompletedStatement(statement, pendingAttachment) {
  if (
    !testFaultConsumed &&
    testFault === 'attach-finalization' &&
    pendingAttachment?.kind === 'attach'
  ) {
    testFaultConsumed = true;
    throw new Error('Controlled ATTACH finalization failure.');
  }
  statement.close();
}

async function closeStatementAfterFailure(statement, pendingAttachment, error) {
  try {
    statement.close();
  } catch (_) {
    await retireAfterUncertainOutcome(
      pendingAttachment,
      'The Turso statement could not be finalized; its outcome is uncertain.',
    );
  }
  try {
    await discardAttachment(pendingAttachment);
  } catch (_) {
    await retireAfterUncertainOutcome(
      pendingAttachment,
      'The Turso attachment registry could not release its files.',
    );
  }
  throw error;
}

async function prepareAttachment(inspection, parameters) {
  switch (inspection.kind) {
    case 'ordinary':
      return null;
    case 'attach': {
      const filename = resolvedArgument(inspection.first, parameters, 'ATTACH filename');
      const alias = resolvedArgument(inspection.second, parameters, 'ATTACH alias');
      if (filename === ':memory:') return { kind: 'attach', alias, filename: null, acquired: false };
      if (mainDatabasePath === null) {
        throw new UnsupportedError(
          'A persistent browser database cannot be attached to an in-memory main database.',
        );
      }
      const canonicalFilename = browserStorageFilename(filename);
      let acquired;
      try {
        acquired = await requireAttachmentRegistry().acquire(canonicalFilename);
      } catch (error) {
        if (
          error instanceof AttachmentRegistryError ||
          requireFileRegistration().isWorkerUnavailable(error)
        ) {
          await retireAfterUncertainOutcome(
            { kind: 'attach', filename: canonicalFilename, acquired: true },
            'The Turso attachment registration outcome is uncertain.',
          );
        }
        throw error;
      }
      return { kind: 'attach', alias, filename: canonicalFilename, acquired };
    }
    case 'detach':
      return {
        kind: 'detach',
        alias: resolvedArgument(inspection.first, parameters, 'DETACH alias'),
      };
    default:
      throw new IntegrationError(`Unknown SQL inspection kind: ${inspection.kind}.`);
  }
}

function resolvedArgument(argument, parameters, label) {
  let value;
  switch (argument.form) {
    case 'direct':
      value = argument.value;
      break;
    case 'bound': {
      const encoded = boundArgument(argument, parameters);
      value = decodeValue(encoded);
      break;
    }
    case 'unsupported':
      throw new UnsupportedError(`${label} must be a direct string or identifier on web.`);
    default:
      throw new IntegrationError(`Missing ${label} parser metadata.`);
  }
  if (typeof value !== 'string') throw new InputError(`${label} must resolve to a string.`);
  return value;
}

function boundArgument(argument, parameters) {
  if (!parameters.named) return parameters.values[argument.bindingIndex - 1];
  return new Map(parameters.values).get(argument.value);
}

function browserStorageFilename(filename) {
  if (filename.startsWith('file:')) return browserFileUri(filename);
  validateBrowserFilename(filename);
  return filename;
}

function browserFileUri(uri) {
  const withoutScheme = uri.slice(5);
  if (withoutScheme.startsWith('//')) {
    throw new UnsupportedError('Browser attachment file URIs cannot contain an authority.');
  }
  if (withoutScheme.includes('#')) {
    throw new UnsupportedError('Browser attachment file URIs cannot contain a fragment.');
  }

  const queryIndex = withoutScheme.indexOf('?');
  const encodedPath = queryIndex < 0 ? withoutScheme : withoutScheme.slice(0, queryIndex);
  const query = queryIndex < 0 ? '' : withoutScheme.slice(queryIndex + 1);
  const filename = decodePercent(encodedPath);
  validateBrowserFilename(filename);

  let cipher;
  let hexkey;
  for (const parameter of query.length === 0 ? [] : query.split('&')) {
    const separator = parameter.indexOf('=');
    if (separator < 0) {
      throw new UnsupportedError('Browser attachment file URI options must use key=value.');
    }
    const key = parameter.slice(0, separator);
    const rawValue = parameter.slice(separator + 1);
    switch (key) {
      case 'mode':
        if (rawValue.trim().toLowerCase() !== 'rwc') {
          throw new UnsupportedError('Browser attachment file URIs support only mode=rwc.');
        }
        break;
      case 'cipher':
        cipher = decodePercent(rawValue);
        break;
      case 'hexkey':
        hexkey = decodePercent(rawValue);
        break;
      default:
        throw new UnsupportedError(`Unsupported browser attachment file URI option: ${key}.`);
    }
  }
  if ((cipher === undefined) !== (hexkey === undefined)) {
    throw new InputError('Browser attachment file URIs require cipher and hexkey together.');
  }
  if (cipher !== undefined && cipher !== 'aegis256' && cipher !== 'aes256gcm') {
    throw new UnsupportedError(`Unsupported Turso attachment cipher: ${cipher}.`);
  }
  if (hexkey !== undefined && !/^[0-9a-fA-F]{64}$/.test(hexkey)) {
    throw new InputError('A browser attachment hexkey must contain exactly 64 hexadecimal digits.');
  }
  return filename;
}

function validateBrowserFilename(filename) {
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
}

function decodePercent(value) {
  const input = textEncoder.encode(value);
  const output = [];
  for (let index = 0; index < input.length; index += 1) {
    if (input[index] !== 37) {
      output.push(input[index]);
      continue;
    }
    if (index + 2 >= input.length) {
      output.push(...input.slice(index));
      break;
    }
    const first = hexDigit(input[index + 1]);
    const second = hexDigit(input[index + 2]);
    if (first === null) {
      output.push(37);
      continue;
    }
    if (second === null) {
      output.push(37, input[index + 1]);
      index += 1;
      continue;
    }
    output.push((first << 4) | second);
    index += 2;
  }
  return textDecoder.decode(Uint8Array.from(output));
}

function hexDigit(byte) {
  if (byte >= 48 && byte <= 57) return byte - 48;
  if (byte >= 65 && byte <= 70) return byte - 65 + 10;
  if (byte >= 97 && byte <= 102) return byte - 97 + 10;
  return null;
}

function attachmentSensitiveValues(inspection, parameters) {
  if (inspection.kind !== 'attach') return new Set();
  const encoded = inspectionArgumentValue(inspection.first, parameters);
  if (typeof encoded !== 'string' || !encoded.startsWith('file:')) return new Set();

  const values = new Set([encoded]);
  const queryIndex = encoded.indexOf('?');
  if (queryIndex < 0) return values;
  const query = encoded.slice(queryIndex + 1).split('#', 1)[0];
  for (const parameter of query.split('&')) {
    const separator = parameter.indexOf('=');
    if (separator < 0 || parameter.slice(0, separator) !== 'hexkey') continue;
    const rawKey = parameter.slice(separator + 1);
    values.add(rawKey);
    values.add(decodePercent(rawKey));
  }
  return values;
}

function inspectionArgumentValue(argument, parameters) {
  if (argument.form === 'direct') return argument.value;
  if (argument.form !== 'bound') return undefined;
  return boundArgument(argument, parameters);
}

function sanitizeError(error, values) {
  if (values.size === 0) return error;
  let message = error instanceof Error ? error.message : String(error);
  for (const value of values) {
    if (value.length !== 0) message = message.replaceAll(value, '[REDACTED]');
  }
  let sanitized;
  if (error instanceof InputError) sanitized = new InputError(message);
  else if (error instanceof UnsupportedError) sanitized = new UnsupportedError(message);
  else if (error instanceof SqlError) sanitized = new SqlError(message);
  else if (error instanceof IntegrationError) sanitized = new IntegrationError(message);
  else sanitized = new Error(message);
  if (Number.isInteger(error?.code)) sanitized.code = error.code;
  return sanitized;
}

async function completeAttachment(pending) {
  if (pending === null || pending === undefined) return;
  if (pending.kind === 'detach') {
    await requireAttachmentRegistry().releaseAlias(pending.alias);
    return;
  }
  requireAttachmentRegistry().rememberAttachment(pending);
}

async function discardAttachment(pending) {
  if (pending?.kind !== 'attach') return;
  await requireAttachmentRegistry().discardNewAttachment(pending);
}

async function shutdownDatabase(additionalFilenames = []) {
  const owned = database;
  const registry = attachmentRegistry;
  database = undefined;
  let closeError;
  let releaseError;
  try {
    owned?.closeEngine();
  } catch (error) {
    closeError = error;
  }
  if (closeError === undefined) {
    const releases = await Promise.allSettled([
      owned?.releaseFiles(),
      registry?.releaseAll(additionalFilenames),
    ]);
    const failures = releases
      .filter((result) => result.status === 'rejected')
      .map((result) => result.reason);
    if (failures.length !== 0) {
      releaseError = new AggregateError(failures, 'The Turso OPFS files could not be released.');
    }
  }
  mainDatabasePath = undefined;
  fileRegistration = undefined;
  attachmentRegistry = undefined;
  if (closeError !== undefined) throw closeError;
  if (releaseError !== undefined) throw releaseError;
}

async function retireAfterUncertainOutcome(pending, message) {
  const additionalFilenames =
    pending?.kind === 'attach' && pending.acquired && pending.filename !== null
      ? [pending.filename]
      : [];
  try {
    await shutdownDatabase(additionalFilenames);
  } catch (_) {
    // The platform failure retires the owning worker after this response.
  }
  throw new IntegrationError(message);
}

function requireFileRegistration() {
  if (fileRegistration === undefined) {
    throw new IntegrationError('The Turso file registration bridge is unavailable.');
  }
  return fileRegistration;
}

function opfsWorkerFailed() {
  return fileRegistration !== undefined && fileRegistration.workerFailure() !== null;
}

function registerAttachmentFile(path) {
  if (
    !testFaultConsumed &&
    testFault === 'attachment-wal-registration' &&
    path.endsWith('-wal')
  ) {
    testFaultConsumed = true;
    throw new Error('Controlled attachment WAL registration failure.');
  }
  return requireFileRegistration().registerFile(path);
}

function requireAttachmentRegistry() {
  if (attachmentRegistry === undefined) {
    throw new IntegrationError('The Turso attachment registry is unavailable.');
  }
  return attachmentRegistry;
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
