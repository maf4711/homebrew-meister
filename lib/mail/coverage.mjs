import { createHash } from 'node:crypto';

const rfc = value => typeof value === 'string' ? value.trim().replace(/^<|>$/g, '') : '';
// This is traversal history, never an authorization or proof of body review.
export const traversalIdentity = row => createHash('sha256').update(JSON.stringify([
  row.id, row.sender, row.subject, row.dateReceived, row.isFlagged, rfc(row.indexRfcMessageId),
])).digest('hex');

export function matchesInventory(item, row) {
  if (item.messageID !== row.id) return false;
  if (item.traversalIdentity) return item.traversalIdentity === traversalIdentity(row);
  // Older journals did not save index identities. Require all recorded headers;
  // this can establish a previous attempt only, never complete content review.
  return item.sender === row.sender && item.subject === row.subject &&
    typeof item.dateReceived === 'string' && Number.isFinite(Date.parse(item.dateReceived)) && Date.parse(item.dateReceived) === Date.parse(row.dateReceived) &&
    (!item.rfcMessageId || rfc(item.rfcMessageId) === rfc(row.indexRfcMessageId));
}

export function traversalCoverage(listing, records, { account, mailbox, policy }) {
  const current = new Map(listing.messages.map(row => [row.id, row]));
  const latest = new Map();
  const matching = records.filter(job => job.account === account && job.mailbox === mailbox &&
    (!job.localAccountID || job.localAccountID === listing.localAccountID) &&
    ['kind', 'classifier', 'classifierVersion', 'destination'].every(key => job.policy?.[key] === policy?.[key]));
  matching.sort((a, b) => (a.createdAt ?? '').localeCompare(b.createdAt ?? ''));
  for (const job of matching) for (const item of job.items ?? []) {
    const row = current.get(item.messageID);
    if (row && matchesInventory(item, row)) latest.set(row.id, item);
  }
  const values = [...latest.values()];
  const unavailable = values.filter(item => item.localUnavailable || item.nativeUnverified).length;
  const deferred = values.filter(item => item.deferred).length;
  const uncertain = values.filter(item => !item.deferred && item.classification?.category === 'uncertain').length;
  return { inventory: current.size, inventoryComplete: listing.hasMore === false,
    attempted: latest.size, neverAttempted: current.size - latest.size,
    unavailable, deferred, uncertain,
    unresolved: values.filter(item => item.localUnavailable || item.nativeUnverified || item.deferred || item.classification?.category === 'uncertain').length };
}
