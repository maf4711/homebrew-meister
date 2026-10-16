import test from 'node:test';
import assert from 'node:assert/strict';
import { traversalCoverage, traversalIdentity } from '../lib/mail/coverage.mjs';
import { summary } from '../scripts/megasmart.mjs';

const policy = { kind: 'newsletter-trash', classifier: 'apple-fm', classifierVersion: 'v1', destination: 'Trash', before: '2026-01-01' };
const row = id => ({ id, sender: 'news@example.test', subject: 'Weekly news', dateReceived: '2020-01-01T00:00:00Z', isFlagged: false, indexRfcMessageId: id + '@example.test' });
const item = (id, extra = {}) => ({ ...row(id), messageID: id, traversalIdentity: traversalIdentity(row(id)), ...extra });
const job = (items, extra = {}) => ({ account: 'Personal', mailbox: 'INBOX', localAccountID: 'account-1', policy,
  createdAt: '2026-01-01T00:00:00Z', items, ...extra });
const listing = ids => ({ localAccountID: 'account-1', hasMore: false, messages: ids.map(row) });
const scope = { account: 'Personal', mailbox: 'INBOX', policy };

test('cumulative current-inventory traversal distinguishes never attempted and unresolved across runs', () => {
  const records = [job([item('1'), item('2', { localUnavailable: true }), item('3', { deferred: true })]),
    job([item('2'), item('3', { classification: { category: 'uncertain' } }), item('4', { nativeUnverified: true })], { createdAt: '2026-01-02T00:00:00Z' })];
  assert.deepEqual(traversalCoverage(listing(['1','2','3','4','5']), records, scope), {
    inventory: 5, inventoryComplete: true, attempted: 4, neverAttempted: 1,
    unavailable: 1, deferred: 0, uncertain: 1, unresolved: 2,
  });
  const next = traversalCoverage(listing(['2','4','5','6']), records, scope);
  assert.equal(next.attempted, 2); assert.equal(next.neverAttempted, 2);
});

test('coverage excludes other accounts, mailboxes, policies, account identities and changed inventory headers', () => {
  const records = [job([item('1')], { account: 'Work' }), job([item('2')], { mailbox: 'Sent' }),
    job([item('3')], { policy: { ...policy, classifierVersion: 'old' } }),
    job([item('4')], { localAccountID: 'other-account' }), job([item('5')])];
  const current = listing(['1','2','3','4','5']); current.messages[4].isFlagged = true;
  assert.equal(traversalCoverage(current, records, scope).attempted, 0);
  assert.equal(traversalCoverage(listing(['1']), [job([item('1')], { policy: { ...policy, before: '2026-02-01' } })], scope).attempted, 1);
});

test('legacy traversal needs matching recorded headers and never means full body review', () => {
  const legacy = item('1'); delete legacy.traversalIdentity;
  const current = listing(['1']);
  assert.equal(traversalCoverage(current, [job([legacy])], scope).attempted, 1);
  assert.equal(traversalCoverage(current, [job([{ ...legacy, dateReceived: '2020-01-01T00:00:00.000Z' }])], scope).attempted, 1);
  for (const change of [{ subject: 'Changed' }, { sender: 'different@example.test' }, { dateReceived: undefined }, { rfcMessageId: 'different@example.test' }]) {
    assert.equal(traversalCoverage(current, [job([{ ...legacy, ...change }])], scope).attempted, 0);
  }
});

test('summary preserves total unavailable while identifying partial storage and per-run progress', () => {
  const result = summary({ id: 'test', status: 'completed', unscanned: 16176, coverage: { neverAttempted: 4445 },
    items: [item('1', { localUnavailable: true, localUnavailableReason: 'partial-emlx' }), item('2', { localUnavailable: true, localUnavailableReason: 'identity-mismatch' }), item('3', { nativeUnverified: true })] });
  assert.equal(result.unavailable, 3); assert.equal(result.partialUnavailable, 1);
  assert.equal(result.unscannedThisRun, 16176); assert.equal(result.coverage.neverAttempted, 4445);
});
