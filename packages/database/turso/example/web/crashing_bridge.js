self.onmessage = ({ data }) => {
  if (data.operation === 'open') {
    self.postMessage({
      id: data.id,
      ok: true,
      result: {
        upstreamVersion: '0.8.0-pre.10',
        capabilities: { fts: false, vectorFunctions: false, vectorIndexes: false },
      },
    });
    return;
  }

  queueMicrotask(() => {
    throw new Error('Controlled worker failure.');
  });
};
