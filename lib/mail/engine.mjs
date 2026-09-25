import { randomUUID, createHash } from 'node:crypto';
import { mkdir, readFile, open, rename, readdir } from 'node:fs/promises';
import { join } from 'node:path';
import { readAhead } from './pipeline.mjs';

export async function durableJSON(path, value) {
  const temporary = `${path}.${randomUUID()}.tmp`;
  const file = await open(temporary, 'wx', 0o600);
  try { await file.writeFile(JSON.stringify(value)); await file.sync(); } finally { await file.close(); }
  await rename(temporary, path);
  const directory = await open(join(path, '..'), 'r');
  try { await directory.sync(); } finally { await directory.close(); }
}
export function destinationName(value) {
  if (typeof value !== 'string' || !value.trim() || value !== value.trim() || value.length > 60 ||
      /[\\/.:\x00-\x1f\x7f]/.test(value) || /^(inbox|posteingang|sent|gesendet|drafts|entwürfe|trash|papierkorb|junk|spam|all mail|alle nachrichten|archive|archiv)$/i.test(value)) {
    throw new Error('Use a short folder name without paths or reserved mailbox names');
  }
  return value;
}
const protectedText = /\b(invoice|rechnung|zahlung|payment|overdue|mahnung|security|sicherheit|password|passwort|verification|verify|bestätigungscode|login|sign.in|one.time|2fa|otp|angebot angefordert|appointment|termin|vertrag|contract|order|bestellung|receipt|quittung|tax|steuer|bank|insurance|versicherung|doctor|arzt|anwalt|legal|invitation|einladung|family|familie|action required|handlungsbedarf|bitte antworten)\b/i;
const marketingText = /\b(newsletter|digest|weekly roundup|wochenrückblick|unsubscribe|abbestellen|sale|sonderangebot|rabatt|promotion|marketing)\b/i;
const protectedCompound = /\b(sicherheits\w*|zahlungs\w*|steuer\w*|bank\w*|versicherungs\w*|arzt\w*|gerichts\w*|schul\w*|rechnungen|mahnungen|termine|einladungen|passwort\w*|bestell\w*)/i;
const hash = value => createHash('sha256').update(value).digest('hex');
const senderAddress = sender => (/<([^<>]+)>/.exec(sender)?.[1] ?? sender).trim().toLowerCase();
const senderKey = (account, sender) => JSON.stringify([account, senderAddress(sender)]);
const trashNames = /^(Deleted Messages|Trash|Papierkorb|Gelöschte Elemente)$/iu;
function targetName(job, value) {
  if (job.policy?.kind === 'newsletter-trash') {
    if (value !== job.policy.destination || !trashNames.test(value.normalize('NFC'))) throw new Error('Invalid trash destination');
    return value;
  }
  return destinationName(value);
}
function newsletterDecision(row, detail, policy, memory) {
  if (memory?.action === 'keep') return { action: 'keep', destination: '', protected: true, reason: 'Your saved keep decision' };
  const received = Date.parse(row.dateReceived);
  if (!Number.isFinite(received) || received >= Date.parse(policy.before)) {
    return { action: 'keep', destination: '', protected: true, reason: 'Recent or undated message stays' };
  }
  if (policy.classifier !== 'apple-fm' && !/\b(newsletter|digest|weekly roundup|wochenrückblick)\b/i.test(`${row.subject}\n${row.sender}`)) {
    return { action: 'keep', destination: '', protected: true, reason: 'Not an explicitly identified newsletter' };
  }
  const decision = classify({ ...row, subject: `${row.subject}\nnewsletter` }, detail, { action: 'move', destination: 'Newsletters' });
  return decision.action === 'move'
    ? { ...decision, destination: policy.destination, reason: 'Newsletter older than seven days: move to trash' }
    : decision;
}
function identity(row, detail) {
  return hash(JSON.stringify([row.sender, row.subject, detail.rfcMessageId, detail.body]));
}
export function classify(row, detail = {}, memory) {
  const text = `${row.subject ?? ''}\n${detail.body ?? ''}`;
  if (row.isFlagged || (row.subject ?? '').includes('?') || /^(re|aw|fw|fwd):/i.test(row.subject ?? '') || protectedText.test(text) || protectedCompound.test(text)) {
    return { action: 'keep', destination: '', protected: true, reason: 'Personal, financial or security message stays in the inbox' };
  }
  if (memory?.action === 'keep') return { ...memory, protected: false, reason: 'Your saved sender decision' };
  if (!marketingText.test(row.subject ?? '')) return { action: 'keep', destination: '', protected: true, reason: 'No clear newsletter or marketing signal' };
  const display = /^\s*"?([^<>]+?)"?\s*</.exec(row.sender ?? '')?.[1]?.replace(/^"|"$/g, '').trim();
  let destination = memory?.destination ?? display;
  try { destination = destinationName(destination); } catch { destination = ''; }
  if (!destination) return { action: 'keep', destination: '', protected: false, reason: 'Choose a meaningful folder name before moving' };
  return { action: 'move', destination, protected: false, reason: memory ? 'Your saved sender decision; current message matches marketing signals' : 'Explicit newsletter or marketing signal' };
}

export class MegasmartEngine {
  constructor(mail, stateDir, { previewLimit = Infinity, verificationLimit = Infinity, persist = durableJSON, onProgress = () => {}, classifier, localHeaders, previewReader } = {}) {
    this.previewReader = previewReader;
    this.classifier = classifier;
    this.onProgress = onProgress;
    this.localHeaders = localHeaders;
    this.mail = mail; this.stateDir = stateDir; this.previewLimit = previewLimit;
    this.verificationLimit = verificationLimit; this.persist = persist;
    this.jobs = new Map(); this.decisions = {}; this.running = null; this.cancellations = new Set();
  }
  async initialize() {
    await mkdir(this.stateDir, { recursive: true, mode: 0o700 });
    try { this.decisions = JSON.parse(await readFile(join(this.stateDir, 'decisions.json'), 'utf8')); }
    catch (error) { if (error.code !== 'ENOENT') throw error; }
    for (const name of await readdir(this.stateDir)) {
      if (!/^job-[\w-]+\.json$/.test(name)) continue;
      const job = JSON.parse(await readFile(join(this.stateDir, name), 'utf8'));
      if (job.status === 'applying') {
        job.status = 'interrupted'; job.error = 'Bridge stopped. Ambiguous moves require manual inspection; pending items may be resumed explicitly.';
        await this.save(job);
      }
      this.jobs.set(job.id, job);
    }
  }
  save(job) { return this.persist(join(this.stateDir, `job-${job.id}.json`), job); }
  job(id) { const job = this.jobs.get(id); if (!job) throw new Error('Job not found'); return job; }
  async call(name, args) {
    const result = await this.mail.call(name, args);
    if (!result || result.partial || ['failedAccounts', 'failedMailboxes', 'timedOutAccounts', 'notSearchedMailboxes', 'skippedLargeMailboxes'].some(k => result[k]?.length)) throw new Error('Incomplete Mail result');
    return result;
  }
  async list(account, mailbox, maximum, from, startOffset = 0, search) {
    const messages = []; const ids = new Set();
    for (let offset = 0; offset < maximum; offset += 500) {
      const limit = Math.min(500, maximum - offset);
      const result = await this.call(search ? 'search-messages' : 'list-messages', { account, mailbox, limit, offset: startOffset + offset, ...(from ? { from } : {}), ...search });
      if (!Array.isArray(result.messages)) throw new Error('Missing message list');
      for (const row of result.messages) {
        if (!row.id || typeof row.sender !== 'string' || typeof row.subject !== 'string' || ids.has(String(row.id))) throw new Error('Invalid or unstable message listing');
        if (row.account && row.account !== account) throw new Error('Message account mismatch');
        if (row.mailbox && row.mailbox !== mailbox) throw new Error('Message mailbox mismatch');
        ids.add(String(row.id)); messages.push({ ...row, id: String(row.id) });
      }
      if (result.messages.length < limit) return { messages, hasMore: false };
    }
    return { messages, hasMore: true };
  }
  async detail(account, mailbox, row, supplied) {
    const detail = supplied ?? await this.call('get-message', { account, mailbox, id: row.id });
    if (String(detail.id) !== row.id || typeof detail.body !== 'string' || (row.subject !== undefined && detail.subject !== row.subject)) throw new Error('Message identity mismatch');
    // IMAP list rows expose the envelope Message-ID even when get-message omits it.
    const rfc = String(detail.rfcMessageId || row.messageId || '').trim().replace(/^<|>$/g, '');
    if (/[\x00-\x20\x7f]/.test(rfc) || rfc.length > 998) throw new Error('Invalid stable Message-ID');
    return { ...detail, rfcMessageId: rfc };
  }
  async batchDetails(account, mailbox, rows, reader = this.mail) {
    const result = new Map();
    for (let start = 0; start < rows.length; start += 25) {
      const chunk = rows.slice(start, start + 25);
      const batch = reader.readMessages ? await reader.readMessages(account, mailbox, chunk.map(r => r.id)) : null;
      if (batch && (batch.length !== chunk.length || new Set(batch.map(r => String(r.id))).size !== chunk.length)) throw new Error('Incomplete native batch');
      for (const row of chunk) {
        const supplied = batch?.find(d => String(d.id) === row.id);
        if (batch && !supplied) throw new Error('Native batch omitted a message');
        result.set(row.id, await this.detail(account, mailbox, row, supplied));
      }
    }
    return result;
  }
  async identities(job, mailbox) {
    if (this.mail.identityRows) return this.mail.identityRows(job.account, mailbox);
    return this.stableRows(job, mailbox, await this.checkedListing(job, mailbox));
  }
  async exactCandidate(job, mailbox, candidate) {
    const detail = candidate.detail ?? await this.detail(job.account, mailbox, candidate.row);
    const row = { ...candidate.row, ...detail };
    return identity(row, detail);
  }
  async preview(account, mailbox, afterJobID, trashMailbox) {
    if (!/^(inbox|posteingang)$/i.test(mailbox)) throw new Error('Only an explicitly selected inbox can be previewed');
    if (this.running) throw new Error('Wait for the active job before creating another preview');
    let offset = 0;
    if (afterJobID) {
      const previous = this.job(afterJobID);
      if (previous.account !== account || previous.mailbox !== mailbox || !previous.hasMore ||
          previous.status === 'applying' || previous.items.some(i => i.status === 'moving')) throw new Error('Invalid continuation');
      offset = (previous.offset ?? 0) + previous.scanned - previous.items.filter(i => i.status === 'moved').length;
    }
    let policy;
    if (trashMailbox !== undefined) {
      if (afterJobID || typeof trashMailbox !== 'string' || !trashNames.test(trashMailbox.normalize('NFC'))) throw new Error('Invalid newsletter trash policy');
      const boxes = await this.call('list-mailboxes', { account });
      if (!boxes.mailboxes?.some(b => b.name === trashMailbox)) throw new Error('Trash mailbox must already exist');
      policy = { kind: 'newsletter-trash', before: new Date(Date.now() - 7 * 86400000).toISOString(), destination: trashMailbox, ...(this.classifier ? { classifier: 'apple-fm', ...(this.classifier.namespace ? { classifierVersion: this.classifier.namespace } : {}) } : {}) };
    }
    // Read local Mail headers once in bounded pages. Repeated native `whose`
    // searches re-scan the entire mailbox and can stall Mail on large inboxes.
    // Age, sender, subject and flag rules are evaluated locally; bodies remain lazy.
    const listing = policy && this.localHeaders
      ? await this.localHeaders(account, mailbox, policy.before)
      : await this.list(account, mailbox, this.previewLimit, undefined, offset);
    const items = [];
    const startedAt = performance.now();
    let readMilliseconds = 0, modelMilliseconds = 0;
    const pages = [];
    for (let base = 0; base < listing.messages.length; base += 25) pages.push(listing.messages.slice(base, base + 25));
    const prepared = readAhead(pages, async page => {
      const eligible = page.filter(row => {
        const memory = this.decisions[senderKey(account, row.sender)];
        const d = policy ? newsletterDecision(row, {}, policy, memory) : classify(row, {}, memory);
        return !d.protected && (d.action !== 'keep' || !d.destination);
      });
      const readStarted = performance.now();
      const details = await this.batchDetails(account, mailbox, eligible, this.previewReader ?? this.mail);
      readMilliseconds += performance.now() - readStarted;
      return { page, eligible, details };
    });
    for await (const { page, eligible, details } of prepared) {
      const modelRows = eligible.filter(row => {
        const detail = details.get(row.id);
        return detail && detail.body.trim() && !(policy ? newsletterDecision({ ...row, ...detail }, detail, policy, this.decisions[senderKey(account, row.sender)]) : classify(row, detail)).protected;
      });
      const modelStarted = performance.now();
      const classified = this.classifier && modelRows.length
        ? await this.classifier.classify(modelRows.map(row => ({ ...row, ...details.get(row.id) }))) : [];
      modelMilliseconds += performance.now() - modelStarted;
      if (this.classifier && (classified.length !== modelRows.length || new Set(classified.map(r => r.id)).size !== modelRows.length)) throw new Error('Incomplete Apple FM classification');
      const classifications = new Map(classified.map(r => [r.id, r]));
      // Local files can establish KEEP only. Every possible move must be checked
      // against the current, explicitly scoped native message before planning it.
      const localMoves = modelRows.filter(row => details.get(row.id)?.localPreview === true &&
        classifications.get(row.id)?.category === 'newsletter' && classifications.get(row.id)?.safeToTrash === true);
      if (localMoves.length) {
        const confirmationStarted = performance.now();
        const nativeDetails = await this.batchDetails(account, mailbox, localMoves);
        readMilliseconds += performance.now() - confirmationStarted;
        const changed = [];
        for (const row of localMoves) {
          const local = details.get(row.id), native = nativeDetails.get(row.id);
          if (!local.rfcMessageId || local.rfcMessageId !== native.rfcMessageId) throw new Error('Local/native stable message identity mismatch');
          if (native.localPreview) throw new Error('Move confirmation must use native Mail');
          const current = { ...row, ...native };
          const protectedNow = policy
            ? newsletterDecision(current, native, policy, this.decisions[senderKey(account, current.sender)]).protected
            : classify(current, native).protected;
          // Native protections already settle KEEP. Do not spend a second FM
          // request on content that cannot become a move.
          if (protectedNow) classifications.delete(row.id);
          else if (['subject', 'sender', 'body'].some(key => local[key] !== native[key])) changed.push(current);
          details.set(row.id, native);
        }
        if (changed.length) {
          const confirmationModelStarted = performance.now();
          const verified = await this.classifier.classify(changed);
          modelMilliseconds += performance.now() - confirmationModelStarted;
          if (verified.length !== changed.length || new Set(verified.map(r => r.id)).size !== changed.length || verified.some(r => !changed.some(c => c.id === r.id))) throw new Error('Incomplete native Apple FM confirmation');
          for (const result of verified) classifications.set(result.id, result);
        }
      }
      for (const row of page) {
      const memory = this.decisions[senderKey(account, row.sender)];
      let decision = policy ? newsletterDecision(row, {}, policy, memory) : classify(row, {}, memory); let detail;
      // Read bodies only for possible moves, keeping large previews bounded.
      if (!decision.protected && decision.action !== 'keep' || (!decision.protected && !decision.destination)) {
        detail = details.get(row.id);
        if (listing.source === 'local-mail-index') {
          if (typeof detail.sender !== 'string' || typeof detail.isFlagged !== 'boolean' || !Number.isFinite(Date.parse(detail.dateReceived))) throw new Error('Mail did not confirm local index metadata');
          row.sender = detail.sender; row.dateReceived = detail.dateReceived; row.isFlagged = detail.isFlagged;
        }
        decision = policy ? newsletterDecision(row, detail, policy, memory) : classify(row, detail, memory);
        if (this.classifier && !detail.body.trim()) decision = { action: 'keep', destination: '', protected: true, reason: 'Empty Mail body; classification cannot authorize moving' };
        if (!detail.rfcMessageId) decision = { action: 'keep', destination: '', protected: true, reason: 'No stable Message-ID for verified moving' };
        if (detail.localUnavailable) decision = { action: 'keep', destination: '', protected: true, reason: 'Complete local contents unavailable; kept without fetching' };
      }
      const classification = classifications.get(row.id);
      if (this.classifier && decision.action === 'move') {
        if (!classification) throw new Error('Apple FM classification missing');
        if (classification.category !== 'newsletter' || classification.safeToTrash !== true) {
          decision = { action: 'keep', destination: '', protected: true, reason: 'Apple FM: not an unambiguous disposable newsletter' };
        } else decision.reason = 'Apple FM: newsletter; protection and age checks passed';
      }
      if (detail?.localPreview) {
        if (decision.action === 'move') throw new Error('Local-only content cannot authorize a move');
        decision.protected = true;
      }
      items.push({ id: randomUUID(), messageID: row.id, sender: row.sender, subject: row.subject, ...(policy ? { dateReceived: row.dateReceived } : {}),
        ...decision, ...(detail?.localUnavailable ? { localUnavailable: true } : {}), ...(classification ? { classification } : {}), status: 'pending', ...(detail && !detail.localPreview ? { fingerprint: identity(row, detail), rfcMessageId: detail.rfcMessageId } : {}) });
    }
      this.onProgress({ phase: 'preview', checked: items.length, total: listing.messages.length,
        elapsedMs: Math.round(performance.now() - startedAt), readMs: Math.round(readMilliseconds), modelMs: Math.round(modelMilliseconds),
        localReads: this.previewReader?.stats?.localReads, unavailableReads: this.previewReader?.stats?.unavailableReads });
    }
    const job = { id: randomUUID(), account, mailbox, createdAt: new Date().toISOString(), status: 'preview', items, scanned: items.length, hasMore: listing.hasMore, offset, ...(listing.source ? { source: listing.source, headersScanned: listing.headersScanned } : {}), ...(policy ? { policy } : {}) };
    await this.save(job); this.jobs.set(job.id, job); return job;
  }
  async edit(id, itemId, action, destination) {
    const job = this.job(id); const item = job.items.find(i => i.id === itemId);
    if (!item || item.status !== 'pending' || job.status === 'applying') throw new Error('Item is not editable');
    if (!['keep', 'move'].includes(action)) throw new Error('Invalid action');
    if (action === 'move' && (item.protected || !item.fingerprint || !item.rfcMessageId)) throw new Error('Protected or unverified message must stay');
    if (action === 'move') targetName(job, destination);
    const previous = { ...item };
    Object.assign(item, { action, destination: action === 'move' ? destination : '', reason: 'Your explicit correction' });
    try { await this.save(job); } catch (error) { Object.assign(item, previous); throw error; }
    // A one-run trash policy must never become a permanent sender routing rule.
    if (job.policy) return job;
    const next = { ...this.decisions, [senderKey(job.account, item.sender)]: { action, destination: item.destination } };
    await this.persist(join(this.stateDir, 'decisions.json'), next); this.decisions = next;
    return job;
  }
  async apply(id) {
    if (this.running) throw new Error('Another job is already applying');
    const job = this.job(id);
    if ([...this.jobs.values()].some(other => other.account === job.account && other.mailbox === job.mailbox && other.items.some(i => i.status === 'moving'))) throw new Error('Uncertain previous move in this mailbox; manual reconciliation required');
    if (!['preview', 'cancelled', 'interrupted', 'failed'].includes(job.status)) throw new Error('Job cannot be applied');
    if (job.items.some(i => i.status === 'moving')) throw new Error('Uncertain previous move: inspect Apple Mail before creating a new preview');
    this.running = id; this.cancellations.delete(id);
    job.status = 'applying'; delete job.error;
    try { await this.save(job); } catch (error) { this.running = null; job.status = 'failed'; throw error; }
    this.task = this.run(job).finally(() => { this.running = null; });
    return job;
  }
  async cancel(id) {
    const job = this.job(id); this.cancellations.add(id);
    if (job.status !== 'applying') { job.status = 'cancelled'; await this.save(job); }
    return job;
  }
  async reconcile(id) {
    if (this.running) throw new Error('Wait for the active job before checking an interrupted result');
    const job = this.job(id);
    for (const item of job.items.filter(i => i.status === 'moving')) {
      const inSource = (await this.identities(job, job.mailbox)).filter(r => r.rfc === item.rfcMessageId);
      const boxes = await this.call('list-mailboxes', { account: job.account });
      if (!Array.isArray(boxes.mailboxes)) throw new Error('Reconciliation incomplete');
      const inTarget = boxes.mailboxes.some(b => b.name === item.destination)
        ? (await this.identities(job, item.destination)).filter(r => r.rfc === item.rfcMessageId) : [];
      const exact = async (candidate, mailbox) => await this.exactCandidate(job, mailbox, candidate) === item.fingerprint;
      if (inSource.length === 0 && inTarget.length === 1 && await exact(inTarget[0], item.destination)) item.status = 'moved';
      else if (inSource.length === 1 && inTarget.length === 0 && inSource[0].row.id === item.messageID && await exact(inSource[0], job.mailbox)) item.status = 'pending';
      else throw new Error('Result remains ambiguous. Inspect both mailboxes in Apple Mail, then check again.');
      try { await this.save(job); } catch (error) { item.status = 'moving'; throw error; }
    }
    job.status = job.items.some(i => i.action === 'move' && i.status === 'pending') ? 'interrupted' : 'completed';
    delete job.error; await this.save(job); return job;
  }
  async checkedListing(job, mailbox, from) {
    const listing = await this.list(job.account, mailbox, this.verificationLimit, from);
    if (listing.hasMore) throw new Error('Mailbox exceeds verification limit; move refused');
    return listing.messages;
  }
  async stableRows(job, mailbox, rows) {
    const result = [];
    for (const row of rows) {
      const envelopeID = String(row.messageId || '').trim().replace(/^<|>$/g, '');
      // IMAP exposes envelope identities. AppleScript rows need a scoped detail
      // read, even when a duplicate's sender or subject has changed.
      const detail = envelopeID ? null : await this.detail(job.account, mailbox, row);
      result.push({ row, rfc: envelopeID || detail.rfcMessageId, detail });
    }
    return result;
  }
  async prepareBatch(job, items) {
    const destination = targetName(job, items[0].destination);
    if (destination.toLowerCase() === job.mailbox.toLowerCase() ||
        items.some(i => i.destination !== destination || i.protected || !i.rfcMessageId || !i.fingerprint)) {
      throw new Error('Unsafe destination or protected message');
    }
    if (job.policy?.classifier === 'apple-fm' && items.some(i => i.classification?.category !== 'newsletter' || i.classification?.safeToTrash !== true)) throw new Error('Missing Apple FM move classification');
    const identities = new Set(items.map(i => i.rfcMessageId));
    if (identities.size !== items.length) throw new Error('Duplicate stable identity in batch');
    const source = this.mail.readMessages
      ? items.map(i => ({ id: i.messageID }))
      : await this.checkedListing(job, job.mailbox, new Set(items.map(i => senderAddress(i.sender))).size === 1 ? senderAddress(items[0].sender) : undefined);
    const byID = new Map(source.map(row => [row.id, row]));
    const details = await this.batchDetails(job.account, job.mailbox, items.map(i => byID.get(i.messageID)).filter(Boolean));
    for (const item of items) {
      const original = byID.get(item.messageID);
      if (!original) throw new Error('Source message no longer exists');
      const detail = details.get(item.messageID);
      const row = { ...original, ...detail };
      if (job.source === 'local-mail-index') {
        if (typeof detail.sender !== 'string' || typeof detail.isFlagged !== 'boolean' || !Number.isFinite(Date.parse(detail.dateReceived))) throw new Error('Mail did not confirm local index metadata');
        row.sender = detail.sender; row.dateReceived = detail.dateReceived; row.isFlagged = detail.isFlagged;
      }
      if (identity(row, detail) !== item.fingerprint || (job.policy ? newsletterDecision(row, detail, job.policy).protected : classify(row, detail).protected)) {
        throw new Error('Message changed or is now protected');
      }
      if (job.policy && newsletterDecision(row, detail, job.policy, this.decisions[senderKey(job.account, row.sender)]).action !== 'move') throw new Error('Newsletter age or classification changed');
    }
    const boxes = await this.call('list-mailboxes', { account: job.account });
    if (!Array.isArray(boxes.mailboxes)) throw new Error('Missing mailboxes');
    const exists = boxes.mailboxes.some(b => b.name === destination);
    if (job.policy && !exists) throw new Error('Trash mailbox no longer exists');
    if (exists) {
      for (const candidate of await this.identities(job, destination)) {
        if (identities.has(candidate.rfc)) throw new Error('Destination already contains this identity; duplicate move refused');
      }
    }
    return { destination, exists };
  }
  async verifyBatch(job, items, destination) {
    const identities = new Set(items.map(i => i.rfcMessageId));
    const source = await this.identities(job, job.mailbox);
    const oldIDs = new Set(items.map(i => i.messageID));
    if (source.some(candidate => oldIDs.has(candidate.row.id))) throw new Error('Source still contains message; label-only move stopped');
    if (source.some(candidate => identities.has(candidate.rfc))) throw new Error('Source still contains the stable message identity');
    const stable = await this.identities(job, destination);
    const matchesByItem = new Map();
    for (const item of items) {
      const matches = stable.filter(candidate => candidate.rfc === item.rfcMessageId);
      if (matches.length !== 1) throw new Error('Destination does not contain one exact moved message');
      matchesByItem.set(item.id, matches[0]);
    }
    const confirmed = this.mail.readMessages
      ? await this.batchDetails(job.account, destination, [...matchesByItem.values()].map(c => c.row)) : null;
    for (const item of items) {
      const matches = stable.filter(candidate => candidate.rfc === item.rfcMessageId);
      if (matches.length !== 1) throw new Error('Destination does not contain one exact moved message');
      const candidate = matches[0];
      const currentFingerprint = confirmed ? identity(confirmed.get(candidate.row.id), confirmed.get(candidate.row.id)) : await this.exactCandidate(job, destination, candidate);
      if (currentFingerprint !== item.fingerprint) throw new Error('Destination does not contain the exact moved message');
    }
  }
  async moveBatch(job, items) {
    const { destination, exists } = await this.prepareBatch(job, items);
    if (this.cancellations.has(job.id)) return false;
    // Journal the ENTIRE candidate set before even creating a destination.
    for (const item of items) item.status = 'moving';
    await this.save(job);
    const stopBeforeMove = async () => {
      if (!this.cancellations.has(job.id)) return false;
      for (const item of items) item.status = 'pending';
      await this.save(job);
      return true;
    };
    if (await stopBeforeMove()) return false;
    if (!exists) {
      const created = await this.call('create-mailbox', { account: job.account, name: destination });
      if (created.ok !== true) throw new Error('Folder creation failed');
    }
    if (await stopBeforeMove()) return false;
    const result = await this.call('batch-move-messages', {
      ids: items.map(i => i.messageID), account: job.account, mailbox: destination,
      sourceAccount: job.account, sourceMailbox: job.mailbox,
    });
    if (result.ok !== true || result.success !== items.length || result.failed !== 0 || result.errors?.length) {
      throw new Error('Move returned incomplete or failed outcome');
    }
    await this.verifyBatch(job, items, destination);
    for (const item of items) item.status = 'moved';
    this.onProgress({ phase: 'apply', moved: job.items.filter(i => i.status === 'moved').length, total: job.items.filter(i => i.action === 'move').length });
    try { await this.save(job); } catch (error) {
      // Keep memory and the last durable pre-mutation record consistent.
      for (const item of items) item.status = 'moving';
      throw error;
    }
    return true;
  }
  async run(job) {
    try {
      const pending = job.items.filter(i => i.status === 'pending' && i.action === 'move');
      for (const item of job.items) if (item.status === 'pending' && item.action === 'keep') item.status = 'skipped';
      await this.save(job);
      // One real, fully verified probe per account run detects label-only Mail
      // behavior before a larger batch is ever allowed to mutate that account.
      if (pending.length && !this.cancellations.has(job.id)) {
        const probe = pending.shift();
        if (await this.moveBatch(job, [probe])) {
          const groups = new Map();
          for (const item of pending) {
            if (!groups.has(item.destination)) groups.set(item.destination, []);
            groups.get(item.destination).push(item);
          }
          batches: for (const items of groups.values()) {
            for (let offset = 0; offset < items.length; offset += 100) {
              if (this.cancellations.has(job.id) || !await this.moveBatch(job, items.slice(offset, offset + 100))) break batches;
            }
          }
        }
      }
      job.status = this.cancellations.has(job.id) ? 'cancelled' : 'completed';
      await this.save(job);
    } catch (error) {
      job.status = 'failed'; job.error = error.message;
      // Preserve moving: never replay an ambiguous operation after crash/timeout.
      try { await this.save(job); } catch { job.error = 'State could not be saved; stop and inspect Apple Mail before retrying'; }
    }
  }
}
