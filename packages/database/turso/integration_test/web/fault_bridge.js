import { startWorker } from './turso/turso_worker.js';

const fault = new URL(import.meta.url).searchParams.get('__turso_test_fault');
let consumed = false;
startWorker({
  beforeAttachmentFinalize() {
    if (!consumed && fault === 'attach-finalization') {
      consumed = true;
      throw new Error('Controlled ATTACH finalization failure.');
    }
  },
  registerFile(path, register) {
    if (!consumed && fault === 'attachment-wal-registration' && path.endsWith('-wal')) {
      consumed = true;
      throw new Error('Controlled attachment WAL registration failure.');
    }
    return register(path);
  },
});
