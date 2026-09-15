export class InputError extends Error {}
export class UnsupportedError extends Error {}
export class SqlError extends Error {}
export class IntegrationError extends Error {}

export function decodeValue(value) {
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

export function encodeValue(value) {
  if (typeof value === 'bigint') return ['integer', value.toString()];
  if (value instanceof Uint8Array) return ['blob', Array.from(value)];
  return value;
}

export function sanitizeError(error, values) {
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

export function encodeError(error, operation, sensitiveValues = []) {
  let message = error instanceof Error ? error.message : String(error);
  for (const sensitiveValue of sensitiveValues) {
    message = message.replaceAll(sensitiveValue, '[REDACTED]');
  }
  if (error instanceof InputError) return { kind: 'argument', message };
  if (error instanceof UnsupportedError) return { kind: 'unsupported', message };
  if (error instanceof SqlError) return { kind: 'database', message, code: null };
  if (error instanceof IntegrationError) return { kind: 'platform', message };
  if (operation === 'open' || operation === 'exists') return { kind: 'platform', message };
  return {
    kind: 'database',
    message,
    code: Number.isInteger(error?.code) ? error.code : null,
  };
}
