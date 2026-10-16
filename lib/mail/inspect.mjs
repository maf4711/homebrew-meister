import { matchesInventory } from './coverage.mjs';
import { normalizeSubjectFolding } from './local-content.mjs';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { defaultRunner } from './native-mail.mjs';

const rfc = value => typeof value === 'string' ? value.trim().replace(/^<|>$/g, '') : '';
const exec = promisify(execFile);

// Diagnostic reads may prompt Mail to fetch text. Bound the helper process so a
// stalled body cannot inherit the 120-second operational confirmation timeout.
export async function inspectionRunner(payload, execute = exec) {
  const result = await defaultRunner(payload, (file, args, options) => execute(file, args, { ...options, timeout: 15000 }));
  // A diagnostic must not multiply a stalled read through NativeMail retries.
  if (payload.operation === 'read' && result?.ok !== true) {
    throw Object.assign(new Error('Inspection native read failed'), { code: result?.errorCode === -1712 ? 'MAIL_READ_TIMEOUT' : 'MAIL_INSPECTION_READ_FAILED' });
  }
  return result;
}

/** Read-only diagnostics. Native text never enters a preview or move decision. */
export async function inspectUnavailable({ job, listing, reader, nativeMail, limit = 25, offset = 0,
  shouldStop = () => false, now = () => performance.now(), budgetMs = 60000 }) {
  if (!Number.isSafeInteger(limit) || limit < 1 || limit > 100 || !Number.isSafeInteger(offset) || offset < 0) throw new Error('Invalid inspection bounds');
  if (reader.nativeFallback !== false) throw new Error('Inspection requires strict local protection');
  if (job.localAccountID && job.localAccountID !== listing.localAccountID) throw new Error('Inspection account identity changed');
  const inventory = new Map(listing.messages.map(row => [row.id, row]));
  const targets = (job.items ?? []).filter(item => item.localUnavailable || item.nativeUnverified);
  const matched = targets.filter(item => inventory.has(item.messageID) && matchesInventory(item, inventory.get(item.messageID)));
  const selected = matched.slice(offset, offset + limit);
  const records = [], started = now(); let stopped = false;
  await reader.configure(job.account, job.mailbox, listing);
  for (const item of selected) {
    if (await shouldStop() || now() - started >= budgetMs) { stopped = true; break; }
    const source = inventory.get(item.messageID);
    const [local] = await reader.readMessages(job.account, job.mailbox, [item.messageID]);
    const result = { messageID: item.messageID, localComplete: !local.localUnavailable,
      ...(local.localUnavailableReason ? { localUnavailableReason: local.localUnavailableReason } : {}),
      protected: true, attachmentCompletenessVerified: false, nativeChecked: false,
      nativeIdentityVerified: false, nativeBodyReadable: false };
    if (local.localUnavailable || item.nativeUnverified) {
      if (await shouldStop() || now() - started >= budgetMs) { stopped = true; break; }
      result.nativeChecked = true;
      try {
        const batch = await nativeMail.readMessages(job.account, job.mailbox, [item.messageID]);
        const native = batch?.length === 1 ? batch[0] : null;
        const expectedRFC = rfc(source.indexRfcMessageId);
        result.nativeIdentityVerified = Boolean(native && native.id === item.messageID && expectedRFC &&
          !/[\x00-\x20\x7f<>]/.test(expectedRFC) && expectedRFC.length <= 998 && rfc(native.rfcMessageId) === expectedRFC &&
          normalizeSubjectFolding(native.subject) === normalizeSubjectFolding(source.subject) && native.sender === source.sender &&
          Date.parse(native.dateReceived) === Date.parse(source.dateReceived));
        result.nativeBodyReadable = result.nativeIdentityVerified && typeof native.body === 'string' &&
          Boolean(native.body.trim()) && Buffer.byteLength(native.body) <= 1000000;
        if (!result.nativeIdentityVerified) result.nativeError = 'identity-mismatch';
      } catch (error) { result.nativeError = error.code === 'MAIL_READ_TIMEOUT' ? 'read-timeout' : 'read-failed'; }
    }
    records.push(result);
    if (result.nativeError === 'read-timeout') { stopped = true; break; }
  }
  const nextOffset = offset + records.length;
  return { status: 'inspection', job: job.id, account: job.account, mailbox: job.mailbox, moved: 0,
    targets: targets.length, matched: matched.length, missingOrChanged: targets.length - matched.length,
    inspected: records.length, offset, nextOffset, hasMore: nextOffset < matched.length, stopped,
    localComplete: records.filter(row => row.localComplete).length,
    localUnavailable: records.filter(row => !row.localComplete).length,
    partial: records.filter(row => row.localUnavailableReason === 'partial-emlx').length,
    nativeChecked: records.filter(row => row.nativeChecked).length,
    nativeIdentityVerified: records.filter(row => row.nativeIdentityVerified).length,
    nativeBodyReadable: records.filter(row => row.nativeBodyReadable).length,
    nativeIdentityMismatch: records.filter(row => row.nativeError === 'identity-mismatch').length,
    nativeReadFailed: records.filter(row => ['read-timeout', 'read-failed'].includes(row.nativeError)).length,
    budgetMs, budgetIsSoft: true, nativeReadTimeoutMs: 15000,
    attachmentCompletenessVerified: false, records };
}
