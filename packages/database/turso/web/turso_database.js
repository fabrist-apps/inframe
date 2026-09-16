import { createAttachments } from './turso_attachments.js';
import { initializeSqlGuard, inspectSql } from './turso_sql_guard.js';
import { normalizeOpfsFilePath, opfsFileExists } from './turso_opfs_paths.js';
import { InputError, UnsupportedError, IntegrationError, decodeValue, encodeValue, encodeError } from './turso_codec.js';
const upstreamVersion = '0.8.0-pre.10';

export function createDatabase(hooks = {}) {
  let database;
  let fileRegistration;
  let attachments;
  const sensitiveValues = new Set();
  return { dispatch, encodeError: (error, operation) => encodeError(error, operation, sensitiveValues) };

  async function dispatch(operation, payload) {
    switch (operation) {
      case 'open':
        return open(payload);
      case 'exists':
        return inspectFileExistence(payload);
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

  async function inspectFileExistence({ path }) {
    if (!globalThis.isSecureContext) {
      throw new UnsupportedError('Turso web requires a secure browser context.');
    }
    if (typeof navigator.storage?.getDirectory !== 'function') {
      throw new UnsupportedError('Origin-private file storage is unavailable.');
    }
    const normalizedPath = normalizeOpfsFilePath(path);
    const root = await navigator.storage.getDirectory();
    return {
      upstreamVersion,
      exists: await opfsFileExists(root, normalizedPath),
    };
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
    await initializeSqlGuard();
    const {
      Database,
      isWorkerUnavailable,
      registerFile,
      runWithSynchronousIo,
      unregisterFile,
      workerFailure,
    } = await import('./turso_upstream.js');
    const options = {
      experimental: encryption === null ? ['attach'] : ['attach', 'encryption'],
      ...(encryption === null ? {} : encryptionOptions(encryption)),
    };
    const candidate = new Database(path, options);
    try {
      await candidate.connect();
      database = candidate;
      fileRegistration = {
        isWorkerUnavailable,
        registerFile: hooks.registerFile ? (path) => hooks.registerFile(path, registerFile) : registerFile,
        runWithSynchronousIo,
        unregisterFile,
        workerFailure,
      };
      attachments = createAttachments(
        persistent ? path : null, fileRegistration, retireAfterUncertainOutcome,
      );
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
    const sanitize = attachments.sanitize;
    let statement;
    let pendingAttachment;
    try {
      statement = await database.prepare(sql);
      bind(statement, parameters);
      pendingAttachment = await attachments.prepare(inspection, parameters);
    } catch (error) {
      if (statement === undefined) throw sanitize(error, inspection, parameters);
      await closeStatementAfterFailure(
        statement,
        pendingAttachment,
        sanitize(error, inspection, parameters),
      );
    }

    let result;
    try {
      result =
        pendingAttachment?.kind === 'attach' && pendingAttachment.filename !== null
          ? await fileRegistration.runWithSynchronousIo(() => action(statement))
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
        sanitize(error, inspection, parameters),
      );
    }
    if (opfsWorkerFailed()) {
      await retireAfterUncertainOutcome(
        pendingAttachment,
        'The Turso OPFS worker failed; the statement outcome is uncertain.',
      );
    }
    try {
      if (pendingAttachment?.kind === 'attach') hooks.beforeAttachmentFinalize?.();
      statement.close();
    } catch (_) {
      await retireAfterUncertainOutcome(
        pendingAttachment,
        'The Turso statement could not be finalized; its outcome is uncertain.',
      );
    }
    try {
      await attachments.complete(pendingAttachment);
    } catch (_) {
      await retireAfterUncertainOutcome(
        pendingAttachment,
        'The Turso attachment registry could not release its files.',
      );
    }
    return result;
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
      await attachments.discard(pendingAttachment);
    } catch (_) {
      await retireAfterUncertainOutcome(
        pendingAttachment,
        'The Turso attachment registry could not release its files.',
      );
    }
    throw error;
  }

  async function shutdownDatabase(additionalFilenames = []) {
    const owned = database;
    const registry = attachments;
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
    fileRegistration = undefined;
    attachments = undefined;
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

  function opfsWorkerFailed() {
    return fileRegistration !== undefined && fileRegistration.workerFailure() !== null;
  }
}
