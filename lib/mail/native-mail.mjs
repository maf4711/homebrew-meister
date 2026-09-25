import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { fileURLToPath } from 'node:url';
import { setTimeout as delay } from 'node:timers/promises';
const exec = promisify(execFile);
const helper = fileURLToPath(new URL('./native-mail.applescript', import.meta.url));
const text = value => typeof value === 'string' && value.length > 0 && value.length <= 512 && !/[\x00-\x1f]/.test(value);
function scope(account, mailbox) {
  if (!text(account) || !text(mailbox)) throw new Error('Explicit account and mailbox required');
}
function idsCheck(ids) {
  if (!Array.isArray(ids) || !ids.length || ids.length > 100 || ids.some(id => typeof id !== 'string' || !/^[1-9]\d*$/.test(id) || !Number.isSafeInteger(Number(id))) || new Set(ids).size !== ids.length) throw new Error('Expected 1–100 unique numeric Mail IDs');
}
function rfc(value) {
  if (typeof value !== 'string' || /[\x00-\x20\x7f]/.test(value.trim())) throw new Error('Missing or malformed RFC identity');
  if (value === '') return '';
  const result = value.trim().replace(/^<|>$/g, '');
  if (!result || /[<>]/.test(result)) throw new Error('Missing or malformed RFC identity');
  return result;
}
export async function defaultRunner(payload, execute = exec) {
  try {
    const { stdout } = await execute('/usr/bin/osascript', ['-l', 'AppleScript', helper, JSON.stringify(payload)], { timeout: 120000, maxBuffer: 32 * 1024 * 1024 });
    return JSON.parse(stdout);
  } catch (error) {
    if (payload.operation === 'read' && error.killed === true && error.signal === 'SIGTERM' && error.code === null) {
      throw Object.assign(new Error('Native Mail content read timed out; message remains unverified'), { code: 'MAIL_READ_TIMEOUT' });
    }
    throw new Error('Native Mail helper failed; operation outcome must be checked', { cause: error });
  }
}
export async function recoverMailInBackground() {
  try { await exec('/usr/bin/open', ['-gj', '-a', 'Mail'], { timeout: 10000, maxBuffer: 4096 }); }
  catch { throw new Error('Apple Mail could not restart in the background'); }
}
export class NativeMail {
  constructor({ runner = defaultRunner, sleep = delay, recover } = {}) {
    this.runner = runner; this.sleep = sleep; this.recover = recover; this.recoveries = 0; this.tail = Promise.resolve();
  }
  async invoke(payload) {
    // Local-file read-ahead can fall back while the foreground confirms a move
    // candidate. Share one native Apple-event lane across both callers.
    const result = this.tail.then(() => this.perform(payload));
    this.tail = result.catch(() => {});
    return result;
  }
  async perform(payload) {
    const readOnly = ['accounts', 'mailboxes', 'read', 'list', 'identities'].includes(payload.operation);
    for (let attempt = 0; ; attempt++) {
      const result = await this.runner(payload);
      if (result?.ok === true) return result;
      const stopped = result?.errorCode === -2700 && result.error?.endsWith(': Apple Mail must already be running');
      if (readOnly && attempt < 2 && ([-609, -600, -1712].includes(result?.errorCode) || (stopped && this.recover))) {
        if (this.recover && this.recoveries < 2 && (stopped || [-609, -600].includes(result?.errorCode))) {
          this.recoveries++;
          await this.recover();
          await this.sleep(1500);
        }
        await this.sleep(attempt === 0 ? 500 : 1500);
        continue;
      }
      const error = new Error(result?.error || 'Incomplete native Mail operation');
      if (payload.operation === 'read' && result?.errorCode === -1712) error.code = 'MAIL_READ_TIMEOUT';
      throw error;
    }
  }
  async readMessages(account, mailbox, ids) {
    scope(account, mailbox); idsCheck(ids);
    const { messages } = await this.invoke({ operation: 'read', account, mailbox, ids });
    if (!Array.isArray(messages) || messages.length !== ids.length) throw new Error('Incomplete native message batch');
    const seen = new Set();
    for (const item of messages) {
      if (!ids.includes(item.id) || seen.has(item.id) || typeof item.subject !== 'string' || typeof item.sender !== 'string' || !item.sender || typeof item.body !== 'string' || typeof item.isFlagged !== 'boolean' || typeof item.dateReceived !== 'string' || !Number.isFinite(Date.parse(item.dateReceived))) throw new Error('Invalid native message metadata');
      item.rfcMessageId = rfc(item.rfcMessageId); seen.add(item.id);
    }
    return ids.map(id => messages.find(item => item.id === id));
  }
  async identityRows(account, mailbox) {
    scope(account, mailbox);
    const result = await this.invoke({ operation: 'identities', account, mailbox });
    if (!Array.isArray(result.ids) || !Array.isArray(result.rfcs) || result.complete !== true || !Number.isSafeInteger(result.count) || result.count < 0 || result.count > 100000 || result.count !== result.ids.length || result.count !== result.rfcs.length) throw new Error('Incomplete identity snapshot');
    const seen = new Set();
    return result.ids.map((id, index) => {
      if (!Number.isSafeInteger(id) || id < 1 || seen.has(id)) throw new Error('Invalid or duplicate native ID');
      seen.add(id);
      return { row: { id: String(id) }, rfc: rfc(result.rfcs[index]) };
    });
  }

  async call(name, args = {}) {
    if (name === 'list-accounts') return this.invoke({ operation: 'accounts' });
    if (name === 'list-mailboxes') {
      if (!text(args.account)) throw new Error('Explicit account required');
      return this.invoke({ operation: 'mailboxes', account: args.account });
    }
    if (name === 'get-message') return (await this.readMessages(args.account, args.mailbox, [args.id]))[0];
    if (name === 'list-messages') {
      scope(args.account, args.mailbox);
      const offset = args.offset ?? 0, limit = args.limit ?? 500;
      if (!Number.isSafeInteger(offset) || offset < 0 || !Number.isSafeInteger(limit) || limit < 1 || limit > 500 || args.from) throw new Error('Unsupported native list scope or pagination');
      return this.invoke({ operation: 'list', account: args.account, mailbox: args.mailbox, offset, limit });
    }
    if (name === 'batch-move-messages') {
      scope(args.sourceAccount, args.sourceMailbox); idsCheck(args.ids);
      if (args.account !== args.sourceAccount || !text(args.mailbox) || args.mailbox === args.sourceMailbox || !/^(Deleted Messages|Trash|Papierkorb|Gelöschte Elemente)$/iu.test(args.mailbox)) throw new Error('Only existing same-account trash destinations are allowed');
      const result = await this.invoke({ operation: 'move', account: args.account, mailbox: args.sourceMailbox, destination: args.mailbox, ids: args.ids });
      if (result.success !== args.ids.length || result.failed !== 0) throw new Error('Ambiguous native move outcome; do not retry');
      return result;
    }
    throw new Error(`Unsupported native Mail operation: ${name}`);
  }
}
