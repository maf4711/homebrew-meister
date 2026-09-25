// One read ahead overlaps native Mail I/O with classification. Only two pages
// can be resident, and only one native read runs at a time. Drain on cancellation
// or consumer failure before releasing the shared Mail lock.
export async function* readAhead(pages, read) {
  let next = 0;
  const start = () => next < pages.length
    ? Promise.resolve().then(() => read(pages[next++])).then(value => ({ value }), error => ({ error }))
    : null;
  let pending = start();
  try {
    while (pending) {
      const result = await pending;
      pending = null;
      if (result.error) throw result.error;
      pending = start();
      yield result.value;
    }
  } finally {
    if (pending) await pending;
  }
}
