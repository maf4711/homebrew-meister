import { spawn } from 'node:child_process';
import { readdir, lstat, realpath } from 'node:fs/promises';
import { homedir } from 'node:os';
import { join, dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
const uuid = /^[a-f\d]{8}(?:-[a-f\d]{4}){3}-[a-f\d]{12}$/i;
const numericID = /^[1-9]\d*$/;
const normalizeRFC = value => typeof value === 'string' ? value.trim().replace(/^<|>$/g, '') : '';

export function runLocalContent(file, args, { input }) {
  return new Promise((accept, reject) => {
    const child = spawn(file, args, { stdio: ['pipe', 'pipe', 'pipe'] });
    const chunks = []; let length = 0, failed = false;
    const timer = setTimeout(() => { failed = true; child.kill('SIGKILL'); }, 30000);
    child.stdout.on('data', data => {
      length += data.length;
      if (length > 27_000_000) { failed = true; child.kill('SIGKILL'); }
      else chunks.push(data);
    });
    child.stderr.on('data', () => {});
    child.stdin.on('error', () => {});
    child.on('error', () => { clearTimeout(timer); reject(new Error('Local mail reader unavailable')); });
    child.on('close', code => {
      clearTimeout(timer);
      if (failed || code !== 0) reject(new Error('Local mail reader unavailable'));
      else accept({ stdout: Buffer.concat(chunks).toString('utf8') });
    });
    child.stdin.end(input);
  });
}

/** Local bodies are preview hints only. Engine must natively confirm every move. */
export class LocalContentReader {
  constructor({ nativeMail, runner = runLocalContent, mailRoot = join(homedir(), 'Library/Mail/V10'), nativeFallback = false } = {}) {
    if (!nativeMail?.readMessages) throw new Error('Native mail fallback required');
    this.nativeMail = nativeMail; this.runner = runner; this.mailRoot = resolve(mailRoot);
    this.nativeFallback = nativeFallback;
  }
  async configure(account, mailbox, listing) {
    this.stats = { localReads: 0, nativeFallbackReads: 0, unavailableReads: 0 };
    this.account = account; this.mailbox = mailbox; this.files = new Map(); this.rows = new Map(); this.accountID = null;
    if (!/^(inbox|posteingang)$/i.test(mailbox) || !uuid.test(listing?.localAccountID ?? '') || !Array.isArray(listing.messages)) return;
    for (const row of listing.messages) {
      if (!numericID.test(row.id) || this.rows.has(row.id)) { this.rows.clear(); return; }
      this.rows.set(row.id, row);
    }
    this.accountID = listing.localAccountID;
    const root = join(this.mailRoot, this.accountID, 'INBOX.mbox');
    try {
      // Resolving symlinks is not permission to broaden the selected mailbox.
      if (await realpath(root) !== root) throw new Error('Noncanonical mailbox');
      let visited = 0;
      const walk = async (path, depth) => {
        if (++visited > 100000 || depth > 20) throw new Error('Mailbox tree too large');
        for (const entry of await readdir(path, { withFileTypes: true })) {
          if (++visited > 100000) throw new Error('Mailbox tree too large');
          const file = join(path, entry.name);
          const partial = /^([1-9]\d*)\.partial\.emlx$/.exec(entry.name);
          if (partial) { this.files.set(partial[1], null); continue; }
          const match = /^([1-9]\d*)\.emlx$/.exec(entry.name);
          if (entry.isSymbolicLink()) { if (match) this.files.set(match[1], null); continue; }
          if (entry.isDirectory() && !entry.name.toLowerCase().endsWith('.mbox')) await walk(file, depth + 1);
          else if (entry.isFile() && match) {
            const id = match[1]; this.files.set(id, this.files.has(id) ? null : file);
          }
        }
      };
      if (!(await lstat(root)).isDirectory()) throw new Error('Missing mailbox');
      await walk(root, 0);
    } catch { this.files.clear(); }
  }
  async readMessages(account, mailbox, ids) {
    if (!Array.isArray(ids) || ids.length > 25 || ids.some(id => !numericID.test(id)) || new Set(ids).size !== ids.length) throw new Error('Invalid local read IDs');
    if (account !== this.account || mailbox !== this.mailbox || !this.accountID) {
      if (!this.nativeFallback) throw new Error('Local preview scope is unavailable or does not match');
      if (this.stats) this.stats.nativeFallbackReads += ids.length;
      return this.nativeMail.readMessages(account, mailbox, ids);
    }
    const found = new Map();
    const requests = ids.filter(id => this.files.get(id) && this.rows.has(id)).map(id => ({ id, path: this.files.get(id) }));
    if (requests.length) {
      try {
        const response = JSON.parse((await this.runner('/usr/bin/python3', [join(dirname(fileURLToPath(import.meta.url)), 'local-content.py')], {
          input: JSON.stringify({ accountID: this.accountID, mailRoot: this.mailRoot, rows: requests }),
        })).stdout);
        if (!Array.isArray(response.rows) || response.rows.length !== requests.length || new Set(response.rows.map(r => r.id)).size !== requests.length) throw new Error('Incomplete local result');
        for (const result of response.rows) {
          if (!requests.some(r => r.id === result.id)) throw new Error('Unexpected local ID');
          const source = this.rows.get(result.id), detail = result.value;
          const rfc = normalizeRFC(source.indexRfcMessageId);
          if (!detail || !rfc || /[\x00-\x20\x7f<>]/.test(rfc) || rfc.length > 998 || detail.rfcMessageId !== rfc || detail.subject !== source.subject || typeof detail.body !== 'string' || !detail.body.trim() || Buffer.byteLength(detail.body) > 1000000) continue;
          found.set(result.id, { ...source, body: detail.body, rfcMessageId: rfc, localPreview: true });
        }
      } catch { found.clear(); }
    }
    const missing = ids.filter(id => !found.has(id));
    if (missing.length && !this.nativeFallback) {
      for (const id of missing) {
        const source = this.rows.get(id);
        if (!source) throw new Error('Local preview header missing');
        found.set(id, { ...source, body: '', rfcMessageId: '', localPreview: true, localUnavailable: true });
      }
      this.stats.unavailableReads += missing.length;
    } else if (missing.length) {
      const native = await this.nativeMail.readMessages(account, mailbox, missing);
      if (!Array.isArray(native) || native.length !== missing.length || new Set(native.map(r => String(r.id))).size !== missing.length) throw new Error('Incomplete native fallback');
      for (const row of native) {
        if (!missing.includes(String(row.id))) throw new Error('Unexpected native fallback ID');
        found.set(String(row.id), { ...row, localPreview: false });
      }
    }
    this.stats.localReads += ids.length - missing.length;
    if (this.nativeFallback) this.stats.nativeFallbackReads += missing.length;
    return ids.map(id => found.get(id));
  }
}
