export class AttachmentRegistry {
  constructor({ mainDatabasePath, registerFile, unregisterFile }) {
    this.mainDatabasePath = mainDatabasePath;
    this.registerFile = registerFile;
    this.unregisterFile = unregisterFile;
    this.schemas = new Map();
    this.owners = new Map();
  }

  async acquire(filename) {
    if (filename === this.mainDatabasePath || this.owners.has(filename)) return false;

    await this.registerFile(filename);
    try {
      await this.registerFile(`${filename}-wal`);
    } catch (primaryError) {
      try {
        await this.releaseFiles(filename);
      } catch (cleanupError) {
        throw new AttachmentRegistryError(
          'Attachment registration and its cleanup both failed.',
          filename,
          primaryError,
          cleanupError,
        );
      }
      throw primaryError;
    }
    return true;
  }

  rememberAttachment({ alias, filename }) {
    this.schemas.set(alias, filename);
    if (filename === null || filename === this.mainDatabasePath) return;

    let owners = this.owners.get(filename);
    if (owners === undefined) {
      owners = new Set();
      this.owners.set(filename, owners);
    }
    owners.add(alias);
  }

  async discardNewAttachment({ filename, acquired }) {
    if (!acquired || filename === null) return;
    await this.releaseFiles(filename);
  }

  async releaseAlias(alias) {
    if (!this.schemas.has(alias)) return;
    const filename = this.schemas.get(alias);
    if (filename === null || filename === this.mainDatabasePath) {
      this.schemas.delete(alias);
      return;
    }

    const owners = this.owners.get(filename);
    if (owners === undefined || !owners.has(alias)) {
      throw new Error(`Missing Turso attachment ownership for alias ${alias}.`);
    }
    if (owners.size > 1) {
      owners.delete(alias);
      this.schemas.delete(alias);
      return;
    }

    await this.releaseFiles(filename);
    this.owners.delete(filename);
    this.schemas.delete(alias);
  }

  async releaseAll(additionalFilenames = []) {
    const filenames = new Set([...this.owners.keys(), ...additionalFilenames]);
    const failures = [];
    for (const filename of filenames) {
      try {
        await this.releaseFiles(filename);
      } catch (error) {
        failures.push(error);
      }
    }
    this.schemas.clear();
    this.owners.clear();
    if (failures.length !== 0) {
      throw new AggregateError(failures, 'One or more Turso attachment files could not be released.');
    }
  }

  async releaseFiles(filename) {
    const failures = [];
    for (const path of [`${filename}-wal`, filename]) {
      try {
        await this.unregisterFile(path);
      } catch (error) {
        failures.push(error);
      }
    }
    if (failures.length !== 0) {
      throw new AggregateError(failures, `The Turso attachment files for ${filename} could not be released.`);
    }
  }
}

export class AttachmentRegistryError extends Error {
  constructor(message, filename, primaryError, cleanupError) {
    super(message, { cause: primaryError });
    this.name = 'AttachmentRegistryError';
    this.filename = filename;
    this.primaryError = primaryError;
    this.cleanupError = cleanupError;
  }
}
