import { createDatabase } from './turso_database.js';

export function startWorker(hooks) {
  const database = createDatabase(hooks);
  self.onmessage = async ({ data: { id, operation, payload } }) => {
    try {
      const result = await database.dispatch(operation, payload);
      self.postMessage({ id, ok: true, result });
    } catch (error) {
      self.postMessage({ id, ok: false, error: database.encodeError(error, operation) });
    }
  };
}
