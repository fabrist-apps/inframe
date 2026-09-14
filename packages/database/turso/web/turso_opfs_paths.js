export function normalizeOpfsFilePath(path) {
  if (
    typeof path !== 'string' ||
    path.length === 0 ||
    path.startsWith('/') ||
    path.endsWith('/') ||
    path.includes('//') ||
    path.includes('\\') ||
    path.includes('\0')
  ) {
    throw new Error('An OPFS file path must be a nonempty normalized relative path.');
  }

  const normalized = [];
  for (const segment of path.split('/')) {
    if (segment === '.') continue;
    if (segment === '..') {
      if (normalized.length === 0) {
        throw new Error('An OPFS file path must not escape the origin storage root.');
      }
      normalized.pop();
      continue;
    }
    normalized.push(segment);
  }
  if (normalized.length === 0) throw new Error('An OPFS file path must identify a file.');
  return normalized.join('/');
}

export async function resolveOpfsFile(root, path, { create }) {
  const segments = normalizeOpfsFilePath(path).split('/');
  const filename = segments.pop();
  let directory = root;
  for (const segment of segments) {
    directory = await directory.getDirectoryHandle(segment, { create });
  }
  return directory.getFileHandle(filename, { create });
}

export async function opfsFileExists(root, path) {
  try {
    await resolveOpfsFile(root, path, { create: false });
    return true;
  } catch (error) {
    if (error?.name === 'NotFoundError' || error?.name === 'TypeMismatchError') return false;
    throw error;
  }
}
