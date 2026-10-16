import test from 'node:test';
import assert from 'node:assert/strict';
import { inspectUnavailable, inspectionRunner } from '../lib/mail/inspect.mjs';
import { traversalIdentity } from '../lib/mail/coverage.mjs';

function fixture() {
  const rows = Array.from({ length: 4 }, (_, index) => ({ id: String(index + 1), subject: 'Weekly news', sender: 'news@example.test',
    dateReceived: '2020-01-01T00:00:00Z', isFlagged: false, indexRfcMessageId: `${index + 1}@example.test` }));
  const calls = [];
  const listing = { messages: rows, localAccountID: 'account-1', hasMore: false };
  const job = { id: 'job', account: 'Personal', mailbox: 'INBOX', localAccountID: 'account-1',
    items: rows.map(row => ({ messageID: row.id, traversalIdentity: traversalIdentity(row), localUnavailable: true })) };
  const reader = { nativeFallback: false, async configure() {}, async readMessages(a, m, ids) {
    return ids.map(id => ({ ...rows.find(row => row.id === id), localUnavailable: true, localUnavailableReason: 'partial-emlx', body: '', rfcMessageId: '' }));
  } };
  const nativeMail = { async readMessages(a, m, ids) {
    calls.push([a,m,ids]); return ids.map(id => ({ ...rows.find(row => row.id === id), body: 'Private diagnostic text', rfcMessageId: `${id}@example.test` }));
  } };
  return { listing, job, reader, nativeMail, calls };
}

test('inspection bounds saved unavailable targets and never converts readable partial text to a move approval', async () => {
  const f = fixture(); const before = JSON.stringify(f.job);
  const result = await inspectUnavailable({ ...f, limit: 2, offset: 1 });
  assert.equal(result.inspected, 2); assert.equal(result.nextOffset, 3); assert.equal(result.hasMore, true);
  assert.equal(result.nativeBodyReadable, 2); assert.equal(result.partial, 2); assert.equal(result.localUnavailable, 2);
  assert.equal(result.localComplete, 0); assert.equal(result.moved, 0); assert.equal(result.attachmentCompletenessVerified, false);
  assert.ok(result.records.every(row => row.protected)); assert.doesNotMatch(JSON.stringify(result), /Private diagnostic text/);
  assert.equal(JSON.stringify(f.job), before); assert.deepEqual(f.calls.map(call => call[2]), [['2'],['3']]);
});

test('mismatched native identity, timeouts and stale saved identities stay unresolved', async () => {
  const f = fixture(); f.listing.messages[3].subject = 'Changed';
  f.nativeMail.readMessages = async (a,m,ids) => {
    if (ids[0] === '3') throw Object.assign(new Error('timeout'), { code: 'MAIL_READ_TIMEOUT' });
    return [{ ...f.listing.messages[0], body: 'readable text', rfcMessageId: 'foreign@example.test' }];
  };
  const result = await inspectUnavailable(f);
  assert.equal(result.missingOrChanged, 1); assert.equal(result.inspected, 3);
  assert.equal(result.nativeIdentityMismatch, 2); assert.equal(result.nativeReadFailed, 1); assert.equal(result.nativeBodyReadable, 0);
  assert.ok(result.records.every(row => row.protected));
});

test('inspection observes stop and deadline between individual native reads', async () => {
  const f = fixture();
  const result = await inspectUnavailable({ ...f, shouldStop: () => f.calls.length >= 1 });
  assert.equal(result.inspected, 1); assert.equal(result.stopped, true); assert.equal(result.nextOffset, 1);
  assert.equal(f.calls.length, 1);
  const deadline = await inspectUnavailable({ ...fixture(), now: () => 0, budgetMs: 0 });
  assert.equal(deadline.inspected, 0); assert.equal(deadline.stopped, true);
  await assert.rejects(inspectUnavailable({ ...fixture(), limit: 101 }), /bounds/);
  const unsafe = fixture(); unsafe.reader.nativeFallback = true;
  await assert.rejects(inspectUnavailable(unsafe), /strict local/);
});

test('inspection runner limits stalled native reads to 15 seconds and preserves timeout classification', async () => {
  await assert.rejects(inspectionRunner({ operation: 'read' }, async (file, args, options) => {
    assert.equal(file, '/usr/bin/osascript'); assert.equal(options.timeout, 15000);
    throw Object.assign(new Error('killed'), { killed: true, signal: 'SIGTERM', code: null });
  }), error => error.code === 'MAIL_READ_TIMEOUT');
  await assert.rejects(inspectionRunner({ operation: 'read' }, async () => ({ stdout: JSON.stringify({ ok: false, errorCode: -1712 }) })),
    error => error.code === 'MAIL_READ_TIMEOUT');
});

test('inspection stops after the first timed-out native read instead of repeating a known stall', async () => {
  const f = fixture(); let calls = 0;
  f.nativeMail.readMessages = async () => { calls++; throw Object.assign(new Error('timeout'), { code: 'MAIL_READ_TIMEOUT' }); };
  const result = await inspectUnavailable(f);
  assert.equal(calls, 1); assert.equal(result.inspected, 1); assert.equal(result.nextOffset, 1);
  assert.equal(result.stopped, true); assert.equal(result.hasMore, true); assert.equal(result.localUnavailable, 1);
  assert.equal(result.records[0].protected, true);
});
