import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { homedir } from 'node:os';
import { join } from 'node:path';
const run = promisify(execFile);

// Read-only candidate discovery. Never writes Mail's private database and never
// treats an index row as authorization to move: the engine reads Mail's message.
export async function localNewsletterHeaders(account, mailbox, before, allOlder = false) {
  if (!/^(inbox|posteingang)$/i.test(mailbox)) throw new Error('Local index requires an explicit inbox');
  let stdout;
  try {
    ({ stdout } = await run('/usr/bin/osascript', ['-e', `on run argv
    with timeout of 5 seconds
      tell application "Mail" to return id of account (item 1 of argv)
    end timeout
  end run`, account], { timeout: 7000, maxBuffer: 4096 }));
  } catch {
    throw new Error('Apple Mail did not answer in time while confirming the local account');
  }
  const accountID = stdout.trim();
  if (!/^[a-f0-9-]{36}$/i.test(accountID)) throw new Error('Unsupported local Mail account identity');
  return readNewsletterIndex(join(homedir(), 'Library/Mail/V10/MailData/Envelope Index'), accountID, account, mailbox, before, allOlder);
}

export async function readNewsletterIndex(path, accountID, account, mailbox, before, allOlder = false) {
  if (!Number.isFinite(Date.parse(before))) throw new Error('Invalid index cutoff');
  const { DatabaseSync } = await import('node:sqlite');
  let db;
  try { db = new DatabaseSync(path, { readOnly: true }); } catch {
    throw new Error('Der lokale Apple-Mail-Index ist nicht lesbar. Erlaube dem Terminal bzw. ausführenden Programm Festplattenvollzugriff unter Systemeinstellungen → Datenschutz & Sicherheit und starte es danach neu.');
  }
  try {
    db.exec('PRAGMA query_only=ON; PRAGMA busy_timeout=2000; BEGIN');
    const boxes = db.prepare('SELECT ROWID AS id, url FROM mailboxes WHERE lower(url)=lower(?)').all(`imap://${accountID}/${mailbox}`);
    if (boxes.length !== 1) throw new Error('Local inbox mapping is ambiguous or missing');
    const rows = db.prepare(`SELECT m.ROWID AS id, COALESCE(m.subject_prefix,'') || COALESCE(s.subject,'') AS subject,
      a.address, a.comment, m.date_received AS received, m.flagged, g.message_id_header AS rfc
      FROM messages m LEFT JOIN subjects s ON s.ROWID=m.subject LEFT JOIN addresses a ON a.ROWID=m.sender
      LEFT JOIN message_global_data g ON g.ROWID=m.global_message_id
      WHERE m.mailbox=? AND m.deleted=0 ORDER BY m.ROWID`).all(boxes[0].id);
    const messages = rows.filter(r => Number.isFinite(r.received) && r.received * 1000 < Date.parse(before) &&
      (allOlder || /\b(newsletter|digest|weekly roundup|wochenrückblick)\b/i.test(`${r.subject}\n${r.address}\n${r.comment}`)))
      .map(r => ({ id: String(r.id), subject: r.subject, sender: r.comment ? `${r.comment} <${r.address}>` : r.address,
        dateReceived: new Date(r.received * 1000).toISOString(), isFlagged: r.flagged !== 0, account, mailbox,
        indexRfcMessageId: typeof r.rfc === 'string' ? r.rfc.trim().replace(/^<|>$/g, '') : '' }));
    if (messages.some(r => typeof r.sender !== 'string')) throw new Error('Incomplete local Mail header');
    return { messages, hasMore: false, source: 'local-mail-index', headersScanned: rows.length, localAccountID: accountID };
  } finally { db.close(); }
}
