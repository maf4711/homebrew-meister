import test from 'node:test';
import assert from 'node:assert/strict';
import { readAhead } from '../lib/mail/pipeline.mjs';

const deferred = () => {
  let resolve;
  const promise = new Promise(r => { resolve = r; });
  return { promise, resolve };
};
test('read-ahead overlaps consumption, preserves order and bounds native reads', async () => {
  const secondStarted = deferred(), finishSecond = deferred();
  let active = 0, peak = 0;
  const started = [], consumed = [];
  for await (const value of readAhead([1, 2, 3], async page => {
    started.push(page); peak = Math.max(peak, ++active);
    if (page === 2) { secondStarted.resolve(); await finishSecond.promise; }
    active--; return page;
  })) {
    consumed.push(value);
    if (value === 1) {
      await secondStarted.promise;
      assert.deepEqual(started, [1, 2]);
      finishSecond.resolve();
    }
  }
  assert.deepEqual(consumed, [1, 2, 3]); assert.equal(peak, 1);
});
test('consumer failure drains prefetched read without starting more work', async () => {
  const secondStarted = deferred(), finishSecond = deferred();
  let drained = false; const started = [];
  const work = (async () => {
    for await (const value of readAhead([1, 2, 3], async page => {
      started.push(page);
      if (page === 2) { secondStarted.resolve(); await finishSecond.promise; drained = true; throw new Error('prefetch failed'); }
      return page;
    })) { assert.equal(value, 1); await secondStarted.promise; throw new Error('classification failed'); }
  })();
  await secondStarted.promise;
  const rejected = assert.rejects(work, /classification failed/);
  assert.equal(drained, false); finishSecond.resolve(); await rejected;
  assert.equal(drained, true); assert.deepEqual(started, [1, 2]);
});
test('native read failure surfaces and stops additional pages', async () => {
  const started = [];
  await assert.rejects(async () => {
    for await (const _ of readAhead([1, 2, 3], async page => {
      started.push(page); if (page === 2) throw new Error('native failure'); return page;
    })) { /* consume */ }
  }, /native failure/);
  assert.deepEqual(started, [1, 2]);
});
