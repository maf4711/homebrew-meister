import test from 'node:test';
import { request } from 'node:http';
import assert from 'node:assert/strict';
import { mkdtemp, rm, readFile, stat } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { MegasmartEngine, classify, destinationName, durableJSON } from '../lib/mail/engine.mjs';


const row = (id, subject = 'Weekly newsletter', sender = 'Garden Weekly <hello@example.com>') => ({ id, subject, sender });
class FakeMail {
  constructor(rows = [row('1')]) { this.boxes = { INBOX: rows }; this.calls = []; this.mode = ''; }
  async call(name, args) {
    this.calls.push({ name, args });
    if (name === 'list-accounts') return { accounts: [{ name: 'Personal', emailAddresses: ['me@example.com'] }] };
    if (name === 'list-mailboxes') return { mailboxes: Object.keys(this.boxes).map(name => ({ name, messageCount: this.boxes[name].length })) };
    if (name === 'list-messages' || name === 'search-messages') return { messages: (this.boxes[args.mailbox] ?? [])
      .filter(r => !args.from || r.sender.toLowerCase().includes(args.from.toLowerCase()))
      .slice(args.offset, args.offset + args.limit), partial: this.mode === 'partial' };
    if (name === 'get-message') {
      const message = this.boxes[args.mailbox].find(r => r.id === args.id);
      return { id: this.mode === 'wrong-id' ? '999' : args.id, subject: message.subject,
        body: message.body ?? 'Newsletter. Unsubscribe.', rfcMessageId: message.rfc ?? `stable-${args.id}` };
    }
    if (name === 'create-mailbox') { this.boxes[args.name] = []; return { ok: true }; }
    if (name === 'batch-move-messages') {
      if (this.mode === 'timeout') throw new Error('MCP timeout; outcome may be uncertain');
      const messages = args.ids.map(id => this.boxes[args.sourceMailbox].find(r => r.id === id));
      this.boxes[args.mailbox].push(...messages);
      if (this.mode !== 'label') this.boxes[args.sourceMailbox] = this.boxes[args.sourceMailbox].filter(r => !args.ids.includes(r.id));
      return { ok: true, success: args.ids.length, failed: this.mode === 'failed' ? 1 : 0 };
    }
    throw new Error(`Unexpected tool ${name}`);
  }
  mutations() { return this.calls.filter(c => ['create-mailbox', 'batch-move-messages'].includes(c.name)); }
}
async function fixture(t, rows, options) {
  const directory = await mkdtemp(join(tmpdir(), 'megasmart-test-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const mail = new FakeMail(rows); const engine = new MegasmartEngine(mail, directory, options);
  await engine.initialize(); return { directory, mail, engine };
}
test('preview is read only, dynamic display name, protected current message overrides same sender', async t => {
  const { engine, mail } = await fixture(t, [row('1'), row('2', 'Newsletter: security login alert'), { ...row('3'), body: 'Your payment is overdue. Newsletter.' }]);
  const job = await engine.preview('Personal', 'INBOX');
  assert.equal(job.items[0].destination, 'Garden Weekly');
  assert.deepEqual(job.items.map(i => i.action), ['move', 'keep', 'keep']);
  assert.equal(mail.mutations().length, 0);
  await assert.rejects(engine.edit(job.id, job.items[1].id, 'move', 'Garden'), /Protected/);
});
test('successful apply journals then verifies exact scoped source and destination', async t => {
  const { engine, mail, directory } = await fixture(t);
  const job = await engine.preview('Personal', 'INBOX'); await engine.apply(job.id); await engine.task;
  assert.equal(job.status, 'completed'); assert.equal(job.items[0].status, 'moved');
  const move = mail.calls.find(c => c.name === 'batch-move-messages');
  assert.deepEqual(move.args, { ids: ['1'], account: 'Personal', mailbox: 'Garden Weekly', sourceAccount: 'Personal', sourceMailbox: 'INBOX' });
  assert.equal(JSON.parse(await readFile(join(directory, `job-${job.id}.json`))).items[0].status, 'moved');
});
test('keep corrections persist and are isolated by account', async t => {
  const { engine, directory, mail } = await fixture(t);
  const job = await engine.preview('Personal', 'INBOX'); await engine.edit(job.id, job.items[0].id, 'keep', '');
  const reloaded = new MegasmartEngine(mail, directory); await reloaded.initialize();
  assert.equal((await reloaded.preview('Personal', 'INBOX')).items[0].action, 'keep');
  assert.equal((await reloaded.preview('Work', 'INBOX')).items[0].action, 'move');
});
for (const mode of ['label', 'failed', 'timeout']) {
  test(`${mode} stops first move, preserves ambiguous state, refuses replay`, async t => {
    const { engine, mail } = await fixture(t, [row('1'), row('2')]);
    const job = await engine.preview('Personal', 'INBOX'); mail.mode = mode;
    await engine.apply(job.id); await engine.task;
    assert.equal(job.status, 'failed'); assert.equal(job.items[0].status, 'moving'); assert.equal(job.items[1].status, 'pending');
    assert.equal(mail.calls.filter(c => c.name === 'batch-move-messages').length, 1);
    await assert.rejects(engine.apply(job.id), /Uncertain/);
  });
}
test('partial listing and wrong detail ID fail closed without mutation', async t => {
  const { engine, mail } = await fixture(t);
  for (const mode of ['partial', 'wrong-id']) { mail.mode = mode; await assert.rejects(engine.preview('Personal', 'INBOX')); }
  assert.equal(mail.mutations().length, 0);
});
test('changed source fingerprint prevents folder creation or move', async t => {
  const { engine, mail } = await fixture(t);
  const job = await engine.preview('Personal', 'INBOX'); mail.boxes.INBOX[0].body = 'New body';
  await engine.apply(job.id); await engine.task;
  assert.equal(job.status, 'failed'); assert.equal(mail.mutations().length, 0);
});
test('durable journal failure blocks all mutation', async t => {
  let fail = false;
  const { engine, mail } = await fixture(t, undefined, { persist: async (path, value) => {
    if (fail && value.items?.some(i => i.status === 'moving')) throw new Error('Disk unavailable');
    await durableJSON(path, value);
  } });
  const job = await engine.preview('Personal', 'INBOX'); fail = true;
  await engine.apply(job.id); await engine.task;
  assert.equal(mail.mutations().length, 0); assert.equal(job.status, 'failed');
});
test('restart marks applying interrupted, does not replay; known pending resumes explicitly', async t => {
  const { engine, mail, directory } = await fixture(t);
  const job = await engine.preview('Personal', 'INBOX'); job.status = 'applying'; await engine.save(job);
  const next = new MegasmartEngine(mail, directory); await next.initialize();
  assert.equal(next.job(job.id).status, 'interrupted'); assert.equal(mail.mutations().length, 0);
  await next.apply(job.id); await next.task; assert.equal(next.job(job.id).status, 'completed');
});
test('cancel retains pending and explicit resume completes', async t => {
  const { engine } = await fixture(t);
  const job = await engine.preview('Personal', 'INBOX'); await engine.cancel(job.id);
  assert.equal(job.status, 'cancelled'); assert.equal(job.items[0].status, 'pending');
  await engine.apply(job.id); await engine.task; assert.equal(job.status, 'completed');
});
test('pagination exposes cap; folder validator blocks path and reserved names', async t => {
  const { engine } = await fixture(t, [row('1'), row('2')], { previewLimit: 1 });
  const job = await engine.preview('Personal', 'INBOX'); assert.equal(job.hasMore, true); assert.equal(job.scanned, 1);
  for (const name of ['../Trash', 'INBOX', 'Trash', 'A/B', 'A\\B', 'A\nB', '']) assert.throws(() => destinationName(name));
  assert.equal(classify(row('1', 'Hello', 'someone@example.com')).action, 'keep');
  assert.equal(classify(row('1', 'Newsletter', 'someone@example.com')).action, 'keep');
});
test('uncertain move fences every job for the same account and source mailbox', async t => {
  const { engine, mail } = await fixture(t);
  const first = await engine.preview('Personal', 'INBOX');
  mail.mode = 'timeout'; await engine.apply(first.id); await engine.task; mail.mode = '';
  const second = await engine.preview('Personal', 'INBOX');
  await assert.rejects(engine.apply(second.id), /Uncertain/);
});
test('existing stable destination identity cannot manufacture a successful move', async t => {
  const { engine, mail } = await fixture(t);
  const job = await engine.preview('Personal', 'INBOX');
  mail.boxes['Garden Weekly'] = [{ ...row('9'), rfc: 'stable-1' }];
  await engine.apply(job.id); await engine.task;
  assert.equal(job.status, 'failed'); assert.match(job.error, /already contains/);
  assert.equal(mail.mutations().length, 0);
});
test('list envelope provides IMAP stable identity without trusting message body', async t => {
  const { engine, mail } = await fixture(t, [{ ...row('1'), messageId: '<stable@example.com>', rfc: '' }]);
  const job = await engine.preview('Personal', 'INBOX');
  assert.equal(job.items[0].rfcMessageId, 'stable@example.com');
  assert.equal(job.items[0].action, 'move');
  await engine.apply(job.id); await engine.task; assert.equal(job.status, 'completed');
  assert.ok(mail.calls.filter(c => c.name === 'list-messages' && c.args.from).every(c => c.args.from === 'hello@example.com'));
});
test('German protected compounds and non-inbox sources cannot be auto moved', async t => {
  for (const word of ['Sicherheitswarnung', 'Zahlungsaufforderung', 'Steuerbescheid', 'Arzttermin', 'Gerichtstermin', 'Schulnachricht']) {
    assert.equal(classify(row('1', `Newsletter: ${word}`)).action, 'keep', word);
  }
  const { engine, mail } = await fixture(t);
  await assert.rejects(engine.preview('Personal', 'Sent'), /inbox/);
  assert.equal(mail.calls.length, 0);
});
test('explicit continuation reaches older mail behind a page of kept messages', async t => {
  const { engine } = await fixture(t, [row('1', 'Personal question'), row('2')], { previewLimit: 1 });
  const first = await engine.preview('Personal', 'INBOX');
  const next = await engine.preview('Personal', 'INBOX', first.id);
  assert.equal(next.offset, 1); assert.equal(next.items[0].messageID, '2');
});
test('read-only reconciliation releases a timed-out move only with unambiguous evidence', async t => {
  const { engine, mail } = await fixture(t);
  const job = await engine.preview('Personal', 'INBOX'); mail.mode = 'timeout';
  await engine.apply(job.id); await engine.task; mail.mode = '';
  const mutations = mail.mutations().length;
  await engine.reconcile(job.id);
  assert.equal(job.status, 'interrupted'); assert.equal(job.items[0].status, 'pending');
  assert.equal(mail.mutations().length, mutations);
  await engine.apply(job.id); await engine.task; assert.equal(job.status, 'completed');
});
test('cancellation during preflight cannot start a new mutation', async t => {
  const { engine, mail } = await fixture(t);
  const job = await engine.preview('Personal', 'INBOX');
  const original = mail.call.bind(mail);
  mail.call = async (name, args) => {
    if (name === 'list-mailboxes') await engine.cancel(job.id);
    return original(name, args);
  };
  await engine.apply(job.id); await engine.task;
  assert.equal(job.status, 'cancelled'); assert.equal(mail.mutations().length, 0);
});
test('one preview reads the entire inbox beyond 5000 without body reads for protected messages', async t => {
  const rows = Array.from({ length: 5501 }, (_, i) => row(String(i + 1), 'Personal question'));
  const { engine, mail } = await fixture(t, rows);
  const job = await engine.preview('Personal', 'INBOX');
  assert.equal(job.scanned, 5501); assert.equal(job.hasMore, false); assert.equal(job.offset, 0);
  assert.equal(mail.calls.filter(c => c.name === 'list-messages').length, 12);
  assert.equal(mail.calls.filter(c => c.name === 'get-message').length, 0);
  assert.equal(mail.mutations().length, 0);
});
test('251 exact messages use one verified probe then 100/100/50 with shared scans and durable batch journal', async t => {
  const rows = Array.from({ length: 251 }, (_, i) => ({ ...row(String(i + 1)), messageId: `stable-${i + 1}` }));
  const snapshots = [];
  const { engine, mail } = await fixture(t, rows, { persist: async (path, value) => {
    if (value.items) snapshots.push(structuredClone(value));
    await durableJSON(path, value);
  } });
  const job = await engine.preview('Personal', 'INBOX');
  const previewCalls = mail.calls.length;
  const original = mail.call.bind(mail);
  mail.call = async (name, args) => {
    if (name === 'batch-move-messages') {
      const durable = snapshots.at(-1);
      assert.ok(args.ids.every(id => durable.items.find(item => item.messageID === id)?.status === 'moving'));
      assert.equal(args.account, 'Personal'); assert.equal(args.sourceAccount, 'Personal');
      assert.equal(args.sourceMailbox, 'INBOX');
    }
    return original(name, args);
  };
  await engine.apply(job.id); await engine.task;
  assert.equal(job.status, 'completed'); assert.ok(job.items.every(i => i.status === 'moved'));
  assert.deepEqual(mail.calls.filter(c => c.name === 'batch-move-messages').map(c => c.args.ids.length), [1, 100, 100, 50]);
  const applyCalls = mail.calls.slice(previewCalls);
  const scans = applyCalls.filter(c => ['list-messages', 'list-mailboxes'].includes(c.name));
  assert.equal(scans.length, 19, '15 header-list calls plus 4 mailbox-list calls, versus 1254 with per-message apply');
  assert.equal(applyCalls.filter(c => c.name === 'get-message').length, 502);
  assert.equal(mail.boxes.INBOX.length, 0); assert.equal(mail.boxes['Garden Weekly'].length, 251);
  t.diagnostic(`251 moves: ${scans.length} apply listing calls; 4 mutation batches; 502 exact-body validation reads`);
});
test('destination grouping combines distinct senders without weakening exact identity checks', async t => {
  const { engine, mail } = await fixture(t, [row('1'), row('2', 'Newsletter', 'Garden Weekly <other@example.com>'), row('3')]);
  const job = await engine.preview('Personal', 'INBOX');
  await engine.apply(job.id); await engine.task;
  assert.equal(job.status, 'completed');
  assert.deepEqual(mail.calls.filter(c => c.name === 'batch-move-messages').map(c => c.args.ids), [['1'], ['2', '3']]);
});
test('bulk partial result retains the whole batch as ambiguous and can reconcile without replay', async t => {
  const { engine, mail } = await fixture(t, [row('1'), row('2'), row('3')]);
  const job = await engine.preview('Personal', 'INBOX');
  const original = mail.call.bind(mail);
  mail.call = async (name, args) => {
    const result = await original(name, args);
    if (name === 'batch-move-messages' && args.ids.length > 1) return { ok: false, success: 1, failed: 1 };
    return result;
  };
  await engine.apply(job.id); await engine.task;
  assert.equal(job.status, 'failed'); assert.deepEqual(job.items.map(i => i.status), ['moved', 'moving', 'moving']);
  const mutations = mail.mutations().length;
  await assert.rejects(engine.apply(job.id), /Uncertain/);
  await engine.reconcile(job.id);
  assert.equal(job.status, 'completed'); assert.equal(mail.mutations().length, mutations);
});
test('freshly flagged member blocks the entire later bulk before its mutation', async t => {
  const { engine, mail } = await fixture(t, [row('1'), row('2'), row('3')]);
  const job = await engine.preview('Personal', 'INBOX');
  mail.boxes.INBOX[2].isFlagged = true;
  await engine.apply(job.id); await engine.task;
  assert.equal(job.status, 'failed'); assert.deepEqual(job.items.map(i => i.status), ['moved', 'pending', 'pending']);
  assert.equal(mail.calls.filter(c => c.name === 'batch-move-messages').length, 1);
});
test('cancellation after folder creation restores all batch items pending before any message move', async t => {
  const { engine, mail } = await fixture(t);
  const job = await engine.preview('Personal', 'INBOX'); const original = mail.call.bind(mail);
  mail.call = async (name, args) => {
    const result = await original(name, args);
    if (name === 'create-mailbox') await engine.cancel(job.id);
    return result;
  };
  await engine.apply(job.id); await engine.task;
  assert.equal(job.status, 'cancelled'); assert.equal(job.items[0].status, 'pending');
  assert.equal(mail.calls.filter(c => c.name === 'batch-move-messages').length, 0);
});
test('changed destination metadata cannot hide a pre-existing RFC identity', async t => {
  const { engine, mail } = await fixture(t);
  const job = await engine.preview('Personal', 'INBOX');
  mail.boxes['Garden Weekly'] = [{ ...row('9', 'Different subject', 'Elsewhere <else@example.com>'), rfc: 'stable-1' }];
  await engine.apply(job.id); await engine.task;
  assert.equal(job.status, 'failed'); assert.match(job.error, /already contains/);
  assert.equal(mail.mutations().length, 0);
});

test('newsletter trash scans all pages, excludes recent, undated, flagged and financial messages', async t => {
  const old = new Date(Date.now() - 9 * 86400000).toISOString();
  const recent = new Date(Date.now() - 6 * 86400000).toISOString();
  const rows = Array.from({ length: 501 }, (_, n) => ({ ...row(String(n), 'Ordinary personal update'), dateReceived: old }));
  rows.push({ ...row('old'), dateReceived: old }, { ...row('recent'), dateReceived: recent },
    row('undated'), { ...row('flagged'), dateReceived: old, isFlagged: true },
    { ...row('invoice', 'Newsletter Rechnung'), dateReceived: old },
    { ...row('sale', 'Big sale'), dateReceived: old },
    { ...row('sender', 'Monthly news', 'Newsletter <news@example.com>'), dateReceived: old });
  const { engine, mail } = await fixture(t, rows);
  mail.boxes['Deleted Messages'] = [];
  const job = await engine.preview('Personal', 'INBOX', undefined, 'Deleted Messages');
  assert.equal(job.hasMore, false); assert.equal(job.scanned, rows.length);
  assert.deepEqual(job.items.filter(i => i.action === 'move').map(i => i.messageID), ['old', 'sender']);
  assert.deepEqual(mail.calls.filter(c => c.name === 'list-messages').map(c => c.args.offset), [0, 500]);
  assert.equal(mail.calls.some(c => c.name === 'search-messages'), false);
  assert.equal(mail.calls.filter(c => c.name === 'get-message').length, 2);
  await engine.apply(job.id); await engine.task;
  assert.equal(job.status, 'completed');
  assert.equal(job.items.filter(i => i.status === 'moved').length, 2);
  assert.equal(mail.boxes['Deleted Messages'].length, 2);
  assert.equal(mail.calls.some(c => /delete/.test(c.name)), false);
});

test('newsletter trash refuses unknown targets and rechecks age before moving', async t => {
  const { engine, mail } = await fixture(t, [{ ...row('old'), dateReceived: new Date(Date.now() - 9 * 86400000).toISOString() }]);
  await assert.rejects(engine.preview('Personal', 'INBOX', undefined, 'Archive'), /Invalid/);
  await assert.rejects(engine.preview('Personal', 'INBOX', undefined, 'Trash'), /already exist/);
  mail.boxes.Trash = [];
  const job = await engine.preview('Personal', 'INBOX', undefined, 'Trash');
  mail.boxes.INBOX[0].dateReceived = new Date().toISOString();
  await engine.apply(job.id); await engine.task;
  assert.equal(job.status, 'failed'); assert.equal(mail.mutations().length, 0);
});

test('newsletter trash honors previously saved keep decisions', async t => {
  const { engine, mail } = await fixture(t, [{ ...row('old'), dateReceived: new Date(Date.now() - 9 * 86400000).toISOString() }]);
  mail.boxes.Trash = [];
  engine.decisions[JSON.stringify(['Personal', 'hello@example.com'])] = { action: 'keep', destination: '' };
  const job = await engine.preview('Personal', 'INBOX', undefined, 'Trash');
  assert.equal(job.items[0].action, 'keep');
  assert.equal(mail.calls.filter(c => c.name === 'get-message').length, 0);
});

test('reconcile refuses a source duplicate whose subject changed after a copy', async t => {
  const { engine, mail } = await fixture(t, [row('1')]);
  const job = await engine.preview('Personal', 'INBOX'); const item = job.items[0];
  mail.boxes[item.destination] = [{ ...mail.boxes.INBOX[0] }];
  mail.boxes.INBOX[0].subject = 'Changed subject';
  item.status = 'moving'; job.status = 'failed';
  await assert.rejects(engine.reconcile(job.id), /ambiguous/);
  assert.equal(item.status, 'moving'); assert.equal(mail.mutations().length, 0);
});

test('local index candidates require live Mail confirmation and avoid mailbox scans', async t => {
  const old = new Date(Date.now() - 9 * 86400000).toISOString();
  const candidate = { ...row('local'), dateReceived: old, isFlagged: false };
  const { engine, mail } = await fixture(t, [candidate], {
    localHeaders: async () => ({ messages: [{ ...candidate }], source: 'local-mail-index', headersScanned: 16000, hasMore: false }),
  });
  mail.boxes.Trash = [];
  const original = mail.call.bind(mail);
  mail.call = async (name, args) => {
    const result = await original(name, args);
    return name === 'get-message' ? { ...result, sender: candidate.sender, dateReceived: old, isFlagged: true } : result;
  };
  const job = await engine.preview('Personal', 'INBOX', undefined, 'Trash');
  assert.equal(job.source, 'local-mail-index'); assert.equal(job.headersScanned, 16000);
  assert.equal(job.items[0].action, 'keep');
  assert.equal(mail.calls.some(c => c.name === 'list-messages' || c.name === 'search-messages'), false);
  assert.equal(mail.mutations().length, 0);
});

test('incomplete live metadata never authorizes a local index candidate', async t => {
  const candidate = { ...row('local'), dateReceived: new Date(Date.now() - 9 * 86400000).toISOString() };
  const { engine, mail } = await fixture(t, [candidate], {
    localHeaders: async () => ({ messages: [candidate], source: 'local-mail-index', hasMore: false }),
  });
  mail.boxes.Trash = [];
  await assert.rejects(engine.preview('Personal', 'INBOX', undefined, 'Trash'), /confirm local index/);
  assert.equal(engine.jobs.size, 0); assert.equal(mail.mutations().length, 0);
});

test('local-index preflight honors a live flag set after the listing', async t => {
  const old = new Date(Date.now() - 9 * 86400000).toISOString();
  const candidate = { ...row('local'), dateReceived: old, isFlagged: false };
  const { engine, mail } = await fixture(t, [candidate], {
    localHeaders: async () => ({ messages: [{ ...candidate }], source: 'local-mail-index', headersScanned: 1, hasMore: false }),
  });
  mail.boxes.Trash = [];
  let liveFlag = false;
  const original = mail.call.bind(mail);
  mail.call = async (name, args) => {
    const result = await original(name, args);
    return name === 'get-message' ? { ...result, sender: candidate.sender, dateReceived: old, isFlagged: liveFlag } : result;
  };
  const job = await engine.preview('Personal', 'INBOX', undefined, 'Trash');
  assert.equal(job.items[0].action, 'move');
  liveFlag = true;
  await engine.apply(job.id); await engine.task;
  assert.equal(job.status, 'failed'); assert.equal(mail.mutations().length, 0);
});

test('Apple FM identifies an old newsletter without newsletter keywords; model keep overrides rules', async t => {
  const old = new Date(Date.now()-9*86400000).toISOString();
  const rows=[{...row('1','September garden notes'),dateReceived:old,isFlagged:false}, {...row('2','September garden notes'),dateReceived:old,isFlagged:false}];
  const seen=[];
  const {engine,mail}=await fixture(t,rows,{classifier:{async classify(input){seen.push(...input);return input.map(r=>({id:r.id,category:r.id==='1'?'newsletter':'personal',safeToTrash:r.id==='1',reason:'fixture'}));}}});
  mail.boxes.Trash=[];
  const job=await engine.preview('Personal','INBOX',undefined,'Trash');
  assert.equal(seen.length,2);assert.ok(seen.every(r=>typeof r.body==='string'));
  assert.equal(job.policy.classifier,'apple-fm');
  assert.deepEqual(job.items.map(i=>i.action),['move','keep']);
});
test('missing model decisions cannot become a move plan', async t=>{
 const {engine,mail}=await fixture(t,[{...row('1'),dateReceived:new Date(Date.now()-9*86400000).toISOString()}],{classifier:{async classify(){return [];}}});
 mail.boxes.Trash=[];await assert.rejects(engine.preview('Personal','INBOX',undefined,'Trash'),/classification/);assert.equal(engine.jobs.size,0);assert.equal(mail.mutations().length,0);
});
test('native detail batches avoid individual reads without weakening preview checks',async t=>{
 const rows=Array.from({length:60},(_,i)=>({...row(String(i+1)),dateReceived:new Date(Date.now()-9*86400000).toISOString(),isFlagged:false}));
 const {engine,mail}=await fixture(t,rows);mail.boxes.Trash=[];let batches=0;
 mail.readMessages=async(a,m,ids)=>{batches++;return ids.map(id=>({...rows.find(r=>r.id===id),body:'Newsletter unsubscribe',rfcMessageId:'stable-'+id}));};
 const job=await engine.preview('Personal','INBOX',undefined,'Trash');
 assert.equal(batches,3);assert.equal(job.items.length,60);assert.equal(mail.calls.filter(c=>c.name==='get-message').length,0);
});

test('native full run uses batched contents and identity-only verification through completion',async t=>{
 const old=new Date(Date.now()-9*86400000).toISOString();
 const rows=Array.from({length:107},(_,n)=>({...row(String(n+1)),dateReceived:old,isFlagged:false}));
 const {engine,mail}=await fixture(t,rows,{localHeaders:async()=>({messages:rows.map(r=>({...r})),source:'local-mail-index',headersScanned:17000,hasMore:false}),classifier:{async classify(input){return input.map(r=>({id:r.id,category:'newsletter',safeToTrash:true,reason:'fixture'}));}}});
 mail.boxes.Trash=[];let batches=0, snapshots=0;
 mail.readMessages=async(a,m,ids)=>{batches++;return ids.map(id=>({...mail.boxes[m].find(r=>r.id===id),body:'Full stable content',rfcMessageId:'stable-'+id}));};
 mail.identityRows=async(a,m)=>{snapshots++;return mail.boxes[m].map(r=>({row:{id:r.id},rfc:'stable-'+r.id}));};
 const job=await engine.preview('Personal','INBOX',undefined,'Trash');await engine.apply(job.id);await engine.task;
 assert.equal(job.status,'completed');assert.equal(job.items.filter(i=>i.status==='moved').length,107);
 assert.equal(mail.boxes.INBOX.length,0);assert.ok(batches<30);assert.equal(snapshots,9);
 assert.equal(mail.calls.some(c=>['get-message','list-messages','search-messages'].includes(c.name)),false);
});

async function localPreviewFixture(t, { nativeBody = 'Native garden news', nativeRFC = 'stable-1', nativeFlag = false, nativeSender, nativeSubject, firstMove = true, secondMove = true } = {}) {
 const current={...row('1','Garden news'),dateReceived:new Date(Date.now()-9*86400000).toISOString(),isFlagged:false};
 const calls=[];
 const classifier={async classify(input){calls.push(input);return input.map(r=>({id:r.id,category:'newsletter',safeToTrash:calls.length===1?firstMove:secondMove,reason:'fixture'}));}};
 const previewReader={async readMessages(){return [{...current,body:'Local garden news',rfcMessageId:'stable-1',localPreview:true}];}};
 const {engine,mail}=await fixture(t,[current],{classifier,previewReader,localHeaders:async()=>({messages:[{...current}],source:'local-mail-index',hasMore:false})});
 mail.boxes.Trash=[];let reads=0;
 mail.readMessages=async()=>{reads++;return [{...current,body:nativeBody,rfcMessageId:nativeRFC,isFlagged:nativeFlag,sender:nativeSender??current.sender,subject:nativeSubject??current.subject}];};
 return {engine,mail,calls,reads:()=>reads};
}
test('local KEEP performs no native read and can never be edited into a move',async t=>{
 const f=await localPreviewFixture(t,{firstMove:false});const job=await f.engine.preview('Personal','INBOX',undefined,'Trash');
 assert.equal(f.reads(),0);assert.equal(job.items[0].action,'keep');assert.equal(job.items[0].protected,true);
 assert.equal(job.items[0].fingerprint,undefined);assert.equal(job.items[0].rfcMessageId,undefined);
 await assert.rejects(f.engine.edit(job.id,job.items[0].id,'move','Trash'),/Protected/);
});
test('local move candidate receives native body classification before any move-capable fingerprint',async t=>{
 const f=await localPreviewFixture(t);const job=await f.engine.preview('Personal','INBOX',undefined,'Trash');
 assert.equal(f.reads(),1);assert.equal(f.calls.length,2);assert.equal(f.calls[1][0].body,'Native garden news');
 assert.equal(job.items[0].action,'move');assert.ok(job.items[0].fingerprint);assert.equal(f.mail.mutations().length,0);
});
test('native FM keep or current protected contents/flags override local move suggestion',async t=>{
 for(const options of [{secondMove:false},{nativeFlag:true},{nativeBody:'Your invoice requires payment'}]){
  const f=await localPreviewFixture(t,options);const job=await f.engine.preview('Personal','INBOX',undefined,'Trash');
  assert.equal(job.items[0].action,'keep');assert.equal(f.mail.mutations().length,0);
  assert.equal(f.calls.length,options.secondMove===false?2:1);
  if(options.secondMove!==false) assert.equal(job.items[0].classification,undefined);
 }
});
test('local/native RFC mismatch aborts instead of transferring an approval to another message',async t=>{
 const f=await localPreviewFixture(t,{nativeRFC:'different'});
 await assert.rejects(f.engine.preview('Personal','INBOX',undefined,'Trash'),/stable message identity/);
 assert.equal(f.mail.mutations().length,0);assert.equal(f.engine.jobs.size,0);
});

test('identical native model inputs reuse the decision but changed sender requires fresh classification',async t=>{
 const same=await localPreviewFixture(t,{nativeBody:'Local garden news'});
 const job=await same.engine.preview('Personal','INBOX',undefined,'Trash');
 assert.equal(same.reads(),1);assert.equal(same.calls.length,1);assert.equal(job.items[0].action,'move');
 const changed=await localPreviewFixture(t,{nativeBody:'Local garden news',nativeSender:'Changed <changed@example.test>'});
 await changed.engine.preview('Personal','INBOX',undefined,'Trash');assert.equal(changed.calls.length,2);
 const subject=await localPreviewFixture(t,{nativeSubject:'Changed subject'});
 await assert.rejects(subject.engine.preview('Personal','INBOX',undefined,'Trash'),/identity mismatch/);
});
test('missing or foreign native confirmation decisions fail closed',async t=>{
 for(const output of [[],[{id:'foreign',category:'newsletter',safeToTrash:true,reason:'fixture'}]]){
  const f=await localPreviewFixture(t);let n=0;const original=f.engine.classifier.classify;
  f.engine.classifier.classify=async rows=>++n===1?original(rows):output;
  await assert.rejects(f.engine.preview('Personal','INBOX',undefined,'Trash'),/native Apple FM confirmation/);
  assert.equal(f.engine.jobs.size,0);assert.equal(f.mail.mutations().length,0);
 }
});

test('unavailable local content is explicitly kept without native reads or model classification',async t=>{
 const f=await localPreviewFixture(t);
 const original=f.engine.previewReader.readMessages;
 f.engine.previewReader.readMessages=async(...args)=>(await original(...args)).map(r=>({...r,body:'',rfcMessageId:'',localUnavailable:true}));
 const job=await f.engine.preview('Personal','INBOX',undefined,'Trash');
 assert.equal(f.reads(),0);assert.equal(f.calls.length,0);assert.equal(job.items[0].localUnavailable,true);
 assert.equal(job.items[0].action,'keep');assert.equal(job.items[0].protected,true);assert.equal(job.items[0].fingerprint,undefined);
});

test('new previews record the classifier policy namespace for later CLI apply',async t=>{
 const f=await localPreviewFixture(t);f.engine.classifier.namespace='meister.mail/v2';
 const job=await f.engine.preview('Personal','INBOX',undefined,'Trash');
 assert.equal(job.policy.classifierVersion,'meister.mail/v2');
});

test('native preview timeout keeps candidate unverified without stopping the preview',async t=>{
 const f=await localPreviewFixture(t);
 f.mail.readMessages=async()=>{throw Object.assign(new Error('timeout'),{code:'MAIL_READ_TIMEOUT'});};
 const job=await f.engine.preview('Personal','INBOX',undefined,'Trash');
 const item=job.items[0];assert.equal(item.action,'keep');assert.equal(item.protected,true);
 assert.equal(item.nativeUnverified,true);assert.equal(item.classification,undefined);
 assert.equal(item.fingerprint,undefined);assert.equal(item.rfcMessageId,undefined);
 await assert.rejects(f.engine.edit(job.id,item.id,'move','Trash'),/Protected/);
 assert.equal(f.mail.mutations().length,0);
});
test('unknown native confirmation failures still stop preview',async t=>{
 const f=await localPreviewFixture(t);f.mail.readMessages=async()=>{throw Error('identity/transport failure');};
 await assert.rejects(f.engine.preview('Personal','INBOX',undefined,'Trash'),/identity\/transport/);
 assert.equal(f.engine.jobs.size,0);assert.equal(f.mail.mutations().length,0);
});

test('failed native confirmation batch does not block successful later pages',async t=>{
 const rows=Array.from({length:30},(_,i)=>({...row(String(i+1)),dateReceived:new Date(Date.now()-9*86400000).toISOString(),isFlagged:false}));
 const classifier={async classify(input){return input.map(r=>({id:r.id,category:'newsletter',safeToTrash:true,reason:'fixture'}));}};
 const previewReader={async readMessages(a,m,ids){return ids.map(id=>({...rows.find(r=>r.id===id),body:'Local content',rfcMessageId:'stable-'+id,localPreview:true}));}};
 const {engine,mail}=await fixture(t,rows,{classifier,previewReader});mail.boxes.Trash=[];let reads=0;
 mail.readMessages=async(a,m,ids)=>{if(++reads===1)throw Object.assign(Error('timeout'),{code:'MAIL_READ_TIMEOUT'});return ids.map(id=>({...rows.find(r=>r.id===id),body:'Native content',rfcMessageId:'stable-'+id}));};
 const job=await engine.preview('Personal','INBOX',undefined,'Trash');
 assert.equal(job.items.length,30);assert.equal(job.items.filter(i=>i.nativeUnverified).length,25);
 assert.ok(job.items.slice(0,25).every(i=>i.action==='keep'&&i.protected&&!i.fingerprint&&!i.classification));
 assert.ok(job.items.slice(25).every(i=>i.action==='move'&&i.fingerprint));assert.equal(reads,2);
});
