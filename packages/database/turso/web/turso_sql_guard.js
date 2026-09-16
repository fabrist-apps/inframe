import { InputError, SqlError, IntegrationError } from './turso_codec.js';
const textEncoder = new TextEncoder();
const textDecoder = new TextDecoder();
let sqlGuard;

export function initializeSqlGuard() {
  return sqlGuard ??= loadSqlGuard();
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

export async function inspectSql(sql) {
  const guard = await initializeSqlGuard();
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
