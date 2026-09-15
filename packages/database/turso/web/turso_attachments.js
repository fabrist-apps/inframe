import { AttachmentRegistry, AttachmentRegistryError } from './turso_attachment_registry.js';
import { normalizeOpfsFilePath } from './turso_opfs_paths.js';
import { InputError, UnsupportedError, IntegrationError, decodeValue, sanitizeError } from './turso_codec.js';
const textEncoder = new TextEncoder();
const textDecoder = new TextDecoder();

// Owns the SQL attachment lifecycle and the OPFS registrations it acquires.
export function createAttachments(mainDatabasePath, files, retire) {
  const registry = new AttachmentRegistry({
    mainDatabasePath,
    registerFile: files.registerFile,
    unregisterFile: files.unregisterFile,
  });
  return {
    prepare: prepareAttachment,
    complete: completeAttachment,
    discard: discardAttachment,
    releaseAll: (filenames) => registry.releaseAll(filenames),
    sanitize: (error, inspection, parameters) =>
      sanitizeError(error, attachmentSensitiveValues(inspection, parameters)),
  };

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
          acquired = await registry.acquire(canonicalFilename);
        } catch (error) {
          if (
            error instanceof AttachmentRegistryError ||
            files.isWorkerUnavailable(error)
          ) {
            await retire(
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

  async function completeAttachment(pending) {
    if (pending === null || pending === undefined) return;
    if (pending.kind === 'detach') {
      await registry.releaseAlias(pending.alias);
      return;
    }
    registry.rememberAttachment(pending);
  }

  async function discardAttachment(pending) {
    if (pending?.kind !== 'attach') return;
    await registry.discardNewAttachment(pending);
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
  return normalizeBrowserStoragePath(filename);
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
  const normalizedFilename = normalizeBrowserStoragePath(filename);

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
  return normalizedFilename;
}

function normalizeBrowserStoragePath(path) {
  if (path.startsWith('file:')) {
    throw new UnsupportedError('A browser attachment path cannot start with file:.');
  }
  try {
    const normalized = normalizeOpfsFilePath(path);
    if (normalized !== path) {
      throw new Error('An OPFS file path must already be normalized.');
    }
    return normalized;
  } catch (error) {
    throw new UnsupportedError(error instanceof Error ? error.message : String(error));
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
