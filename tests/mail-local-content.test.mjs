import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, writeFile, rm, realpath, symlink } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { LocalContentReader, runLocalContent } from '../lib/mail/local-content.mjs';
const accountID = '12345678-abcd-abcd-abcd-123456789abc';
const header = (id, extra = '') => `Subject: Weekly news\r\nMessage-ID: <mail${id}@example.test>\r\n${extra}`;
const simple = id => header(id, 'Content-Type: text/plain; charset=utf-8\r\nContent-Transfer-Encoding: 8bit\r\n\r\n') + 'Complete news ä end';
const row = id => ({ id, subject: 'Weekly news', sender: 'news@example.test', dateReceived: '2026-01-01T00:00:00Z', isFlagged: false, indexRfcMessageId: `mail${id}@example.test` });
async function fixture(t, ids = ['1']) {
  const directory = await realpath(await mkdtemp(join(tmpdir(), 'meister-local-content-')));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const root = join(directory, accountID, 'INBOX.mbox'); await mkdir(root, { recursive: true });
  const calls = [];
  const reader = new LocalContentReader({ nativeFallback: true, mailRoot: directory, nativeMail: { readMessages: async (a, m, selected) => {
    calls.push(selected); return selected.map(id => ({ ...row(id), body: 'Native fallback', rfcMessageId: `mail${id}@example.test` }));
  } } });
  const listing = { localAccountID: accountID, messages: ids.map(row) };
  const write = async (id, payload, suffix = '', name = `${id}.emlx`) => {
    const data = Buffer.from(payload); await writeFile(join(root, name), Buffer.concat([Buffer.from(`${data.length}\n`), data, Buffer.from(suffix)]));
  };
  return { directory, root, calls, reader, listing, write, configure: () => reader.configure('iCloud', 'INBOX', listing) };
}
test('complete UTF8 content uses local reader, preserves order and reports source', async t => {
  const f = await fixture(t, ['1', '2']); await f.write('1', simple('1')); await f.write('2', simple('2')); await f.configure();
  const rows = await f.reader.readMessages('iCloud', 'INBOX', ['2', '1']);
  assert.deepEqual(rows.map(r => r.id), ['2', '1']); assert.ok(rows.every(r => r.localPreview && r.body === 'Complete news ä end'));
  assert.equal(f.calls.length, 0); assert.deepEqual(f.reader.stats, { localReads: 2, nativeFallbackReads: 0, unavailableReads: 0 });
});
test('multipart retains every alternative and decodes charset and transfer encoding', async t => {
  const f = await fixture(t);
  const mime = header('1', 'MIME-Version: 1.0\r\nContent-Type: multipart/alternative; boundary="x"\r\n\r\n') +
    '--x\r\nContent-Type: text/plain; charset=iso-8859-1\r\nContent-Transfer-Encoding: quoted-printable\r\n\r\nGr=FC=DFe\r\n' +
    '--x\r\nContent-Type: text/html; charset=utf-8\r\nContent-Transfer-Encoding: base64\r\n\r\n' + Buffer.from('<p>Payment required</p><img alt="Invoice">').toString('base64') + '\r\n--x--\r\n';
  await f.write('1', mime); await f.configure(); const [result] = await f.reader.readMessages('iCloud', 'INBOX', ['1']);
  assert.equal(result.localPreview, true); assert.match(result.body, /Grüße/); assert.match(result.body, /Payment required/); assert.match(result.body, /Invoice/);
});
test('missing partial ambiguous duplicate and symlink files fall back natively', async t => {
  const f = await fixture(t, ['1', '2', '3', '4']);
  await f.write('1', simple('1'), '', '1.partial.emlx');
  await f.write('2', simple('2')); await mkdir(join(f.root, 'nested')); await writeFile(join(f.root, 'nested', '2.emlx'), 'duplicate');
  await symlink(join(f.root, '2.emlx'), join(f.root, '3.emlx'));
  await f.configure(); const results = await f.reader.readMessages('iCloud', 'INBOX', ['4', '3', '2', '1']);
  assert.deepEqual(f.calls, [['4', '3', '2', '1']]); assert.ok(results.every(r => !r.localPreview));
});
test('bad MIME and byte bounds never produce trusted local content', async t => {
  const f = await fixture(t, ['1','2','3','4','5','6','7','8']);
  await writeFile(join(f.root, '1.emlx'), '9999\n' + simple('1'));
  await f.write('2', header('2', 'Content-Type: text/plain; charset=unknown-xyz\r\n\r\n') + 'text');
  await f.write('3', header('3', 'Content-Type: multipart/mixed; boundary="missing"\r\n\r\n') + 'text');
  await f.write('4', header('4', 'Content-Type: text/plain\r\nContent-Transfer-Encoding: magic\r\n\r\n') + 'text');
  await f.write('5', header('5', 'Content-Type: text/plain\r\nContent-Disposition: attachment\r\n\r\n') + 'text');
  await f.write('6', simple('6'), 'not a metadata plist');
  await f.write('7', header('7', 'Content-Type: text/plain\r\nContent-Transfer-Encoding: quoted-printable\r\n\r\n') + 'bad=ZZ');
  await f.write('8', header('8', '\r\n') + 'a'.repeat(1000001));
  await f.configure(); await f.reader.readMessages('iCloud', 'INBOX', f.listing.messages.map(r => r.id)); assert.equal(f.calls[0].length, 8);
});
test('RFC and decoded subject must both match the index; scope mismatch falls back', async t => {
  const f = await fixture(t, ['1','2','3']); await f.write('1', simple('1').replace('Weekly news', 'Other subject'));
  await f.write('2', simple('2').replace('mail2@', 'other@')); await f.write('3', simple('3')); await f.configure();
  const result = await f.reader.readMessages('iCloud', 'INBOX', ['1','2','3']); assert.equal(result[2].localPreview, true); assert.deepEqual(f.calls, [['1','2']]);
  await f.reader.readMessages('Other account', 'INBOX', ['3']); assert.deepEqual(f.calls[1], ['3']);
  await f.reader.configure('iCloud', 'INBOX', { ...f.listing, localAccountID: '../escape' });
  await f.reader.readMessages('iCloud', 'INBOX', ['3']); assert.deepEqual(f.calls[2], ['3']);
});
test('Python independently rejects escaped paths and ID/path mismatches', async t => {
  const f = await fixture(t); await f.write('1', simple('1'));
  const script = new URL('../lib/mail/local-content.py', import.meta.url).pathname;
  for (const path of [join(f.directory, 'elsewhere', '1.emlx'), join(f.root, 'nested', '..', '1.emlx'), join(f.root, '2.emlx')]) {
    const input = JSON.stringify({ accountID, mailRoot: f.directory, rows: [{ id: '1', path }] });
    const response = JSON.parse((await runLocalContent('/usr/bin/python3', [script], { input })).stdout);
    // join normalizes traversal; use an explicit raw traversal in the next check.
    if (path !== join(f.root, '1.emlx')) assert.equal(response.rows[0].value, null);
  }
  const input = JSON.stringify({ accountID, mailRoot: f.directory, rows: [{ id: '1', path: f.root + '/nested/../1.emlx' }] });
  assert.equal(JSON.parse((await runLocalContent('/usr/bin/python3', [script], { input })).stdout).rows[0].value, null);
});
test('encoded subject and valid plist suffix decode without including metadata', async t => {
  const f = await fixture(t); f.listing.messages[0].subject = 'Grüße';
  await f.write('1', simple('1').replace('Weekly news', '=?UTF-8?B?R3LDvMOfZQ==?='), '\n<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>flags</key><integer>1</integer></dict></plist>');
  await f.configure(); const [result] = await f.reader.readMessages('iCloud', 'INBOX', ['1']); assert.equal(result.localPreview, true); assert.doesNotMatch(result.body, /flags|plist/);
});
test('missing root and failed reader fall back to native without aborting the run', async t => {
  const f = await fixture(t); await f.configure(); await f.reader.readMessages('iCloud', 'INBOX', ['1']);
  assert.deepEqual(f.calls, [['1']]);
  await f.write('1', simple('1')); await f.configure(); f.reader.runner = async () => { throw new Error('reader failed'); };
  await f.reader.readMessages('iCloud', 'INBOX', ['1']); assert.equal(f.calls.length, 2);
  await f.reader.configure('iCloud', 'INBOX', { ...f.listing, localAccountID: 'aaaaaaaa-abcd-abcd-abcd-123456789abc' });
  await f.reader.readMessages('iCloud', 'INBOX', ['1']); assert.equal(f.calls.length, 3);
});

test('Apple Mail padded decimal byte counts are accepted without changing byte slicing',async t=>{
 const f=await fixture(t);const payload=Buffer.from(simple('1'));
 await writeFile(join(f.root,'1.emlx'),Buffer.concat([Buffer.from(String(payload.length).padEnd(10,' ')+'\n'),payload]));
 await f.configure();const result=await f.reader.readMessages('iCloud','INBOX',['1']);
 assert.equal(result[0].localPreview,true);assert.equal(f.calls.length,0);
});

test('HTML extraction drops rendering code but retains all message and hidden text',async t=>{
 const f=await fixture(t);
 await f.write('1',header('1','Content-Type: text/html; charset=utf-8\r\n\r\n')+'<style>.unused { color: red }</style><p>Payment required</p><script>ignoredCode()</script><div hidden>Important invoice</div>');
 await f.configure();const [r]=await f.reader.readMessages('iCloud','INBOX',['1']);
 assert.equal(r.localPreview,true);assert.match(r.body,/Payment required/);assert.match(r.body,/Important invoice/);assert.doesNotMatch(r.body,/ignoredCode|color: red/);
});

test('strict local preview never fetches missing or partial contents through Apple Mail',async t=>{
 const f=await fixture(t,['1','2']);f.reader.nativeFallback=false;
 await f.write('1',simple('1'));await f.write('2',simple('2'),'','2.partial.emlx');await f.configure();
 const rows=await f.reader.readMessages('iCloud','INBOX',['1','2']);
 assert.equal(rows[0].localPreview,true);assert.equal(rows[1].localUnavailable,true);
 assert.equal(rows[1].body,'');assert.equal(rows[1].rfcMessageId,'');assert.equal(f.calls.length,0);
 assert.deepEqual(f.reader.stats,{localReads:1,nativeFallbackReads:0,unavailableReads:1});
});
