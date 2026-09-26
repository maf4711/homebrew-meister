import test from 'node:test';
import assert from 'node:assert/strict';
import { MegasmartEngine } from '../lib/mail/engine.mjs';
import { MailClassifier } from '../lib/mail/fm-classifier.mjs';
import { createProgressReporter } from '../lib/mail/progress.mjs';

function output(tty = false) {
  let clock = 0, tick, stopped = 0;
  const writes = [];
  const reporter = createProgressReporter({
    stream: { isTTY: tty, columns: 200, write: s => writes.push(s) },
    now: () => clock,
    schedule: fn => { tick = fn; return { unref() {} }; },
    unschedule: () => stopped++,
  });
  return { reporter, writes, advance(ms) { clock += ms; tick(); }, get stopped() { return stopped; } };
}
test('rapid updates are bounded; completion and phase transitions always print', () => {
  const { reporter, writes } = output();
  for (let checked = 0; checked <= 13258; checked++) reporter.update({ phase: 'preview', checked, total: 13258 });
  assert.equal(writes.length, 2);
  assert.match(writes[1], /13258\/13258 \(100%\)/);
  reporter.update({ phase: 'apply', moved: 0, total: 10 });
  assert.equal(writes.length, 3);
  reporter.close();
});
test('FM waits remain visible without inventing completed work', () => {
  const o = output();
  o.reporter.update({ phase: 'preview', activity: 'FM prüft 4', checked: 2975, total: 13258, elapsedMs: 7000 });
  o.advance(15000);
  assert.match(o.writes[1], /2975\/13258.*22s · FM prüft 4/);
  assert.ok(o.writes.every(s => !s.includes('\x1b')));
  o.reporter.close(); o.reporter.close();
  assert.equal(o.stopped, 1);
  o.advance(15000);
  assert.equal(o.writes.length, 2);
});
test('TTY rewrites one line and closes it once', () => {
  const o = output(true);
  o.reporter.update({ phase: 'preview', checked: 0, total: 100 });
  o.advance(1000);
  assert.ok(o.writes.every(s => s.startsWith('\r\x1b[2K') && !s.includes('\n')));
  o.reporter.close(); o.reporter.close();
  assert.equal(o.writes.at(-1), '\n');
  assert.equal(o.writes.length, 3);
});

async function preview({ pageSize = 100, unavailable = false, move = false, foreign = false } = {}) {
  const rows = Array.from({ length: 100 }, (_, n) => ({ id: String(n + 1), subject: 'Weekly newsletter',
    sender: 'News <news@example.test>', dateReceived: '2020-01-01T00:00:00Z', isFlagged: n % 25 !== 0 }));
  let launches = 0, nativeReads = 0, largestRead = 0;
  const phases = [];
  const detail = (id, local) => ({ ...rows[Number(id) - 1], body: unavailable ? '' : 'Weekly newsletter roundup',
    rfcMessageId: unavailable ? '' : `${id}@example.test`, localPreview: local, ...(unavailable ? { localUnavailable: true } : {}) });
  const classifier = new MailClassifier({ helperPath: '/fake', runner: async (file, args, { input }) => {
    launches++;
    const batch = JSON.parse(input).rows;
    return { stdout: JSON.stringify({ model: 'apple-on-device', policyVersion: 'meister.mail/v3',
      results: batch.map(row => ({ id: foreign ? 'wrong' : row.id, category: move ? 'newsletter' : 'other', safeToTrash: move, reason: 'fixture' })) }) };
  } });
  classifier.availableChecked = true;
  const mail = { call: async name => {
    assert.equal(name, 'list-mailboxes'); return { mailboxes: [{ name: 'Trash' }] };
  }, readMessages: async (account, mailbox, ids) => { nativeReads += ids.length; return ids.map(id => detail(id, false)); } };
  const previewReader = { readMessages: async (account, mailbox, ids) => {
    largestRead = Math.max(largestRead, ids.length); assert.ok(ids.length <= 25);
    return ids.map(id => detail(id, true));
  } };
  const engine = new MegasmartEngine(mail, '/unused', { previewPageSize: pageSize, classifier, previewReader,
    persist: async () => {}, localHeaders: async () => ({ messages: rows, hasMore: false, source: 'local-mail-index' }),
    onProgress: p => phases.push(p.activity) });
  const job = await engine.preview('Fixture', 'INBOX', undefined, 'Trash');
  return { job, launches, nativeReads, largestRead, phases };
}
test('sparse FM candidates use half as many helper launches with identical decisions', async () => {
  const old = await preview({ pageSize: 25 }), next = await preview();
  assert.equal(old.launches, 4); assert.equal(next.launches, 2);
  const decisions = job => job.items.map(({ id, ...item }) => item);
  assert.deepEqual(decisions(old.job), decisions(next.job));
  assert.equal(next.nativeReads, 0);
  assert.ok(next.phases.includes('FM prüft 4'));
});
test('unavailable content stays protected without FM or native fetch', async () => {
  const { job, launches, nativeReads } = await preview({ unavailable: true });
  assert.equal(launches, 0); assert.equal(nativeReads, 0);
  assert.ok(job.items.every(i => i.action === 'keep' && i.protected));
  assert.equal(job.items.filter(i => i.localUnavailable).length, 4);
});
test('every local move candidate still receives native identity confirmation', async () => {
  const { job, nativeReads } = await preview({ move: true });
  assert.equal(nativeReads, 4);
  const moves = job.items.filter(i => i.action === 'move');
  assert.equal(moves.length, 4);
  assert.ok(moves.every(i => i.fingerprint && i.rfcMessageId));
});
test('foreign model identities abort the preview', async () => {
  await assert.rejects(preview({ foreign: true }), /Invalid local mail classification result/);
});
test('page size stays bounded', () => {
  for (const size of [0, -1, 101, Infinity, 1.5]) assert.throws(() => new MegasmartEngine({}, '', { previewPageSize: size }), /page size/);
});

test('engine independently rejects a classifier returning foreign IDs', async () => {
  const row = { id: '1', subject: 'Weekly newsletter', sender: 'News <news@example.test>',
    dateReceived: '2020-01-01T00:00:00Z', isFlagged: false };
  const engine = new MegasmartEngine({ call: async () => ({ mailboxes: [{ name: 'Trash' }] }) }, '/unused', {
    persist: async () => assert.fail('Invalid result must not be saved'),
    localHeaders: async () => ({ messages: [row], hasMore: false }),
    previewReader: { readMessages: async () => [{ ...row, body: 'newsletter', rfcMessageId: '1@example.test', localPreview: true }] },
    classifier: { classify: async () => [{ id: 'foreign', category: 'other', safeToTrash: false }] },
  });
  await assert.rejects(engine.preview('Fixture', 'INBOX', undefined, 'Trash'), /Incomplete Apple FM classification/);
});

import { KeepCache } from '../lib/mail/keep-cache.mjs';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
test('bounded maintenance defers safely, rotates attempted work and respects policy scope', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'meister-budget-engine-'));
  t.after(() => rm(directory, { recursive:true, force:true }));
  const rows = Array.from({length:6}, (_,n) => ({id:String(n+1), subject:'Weekly newsletter', sender:'News <news@example.test>',
    dateReceived:'2020-01-01T00:00:00Z', isFlagged:false}));
  const attempted = [];
  const model = {cacheNamespace:'fixture/v1', async classify(batch) {
    attempted.push(...batch.map(r=>r.id));
    return batch.map(r=>({id:r.id,category:'uncertain',safeToTrash:false,reason:'retain'}));
  }};
  const mail = {call:async()=>({mailboxes:[{name:'Trash'}]}),readMessages:async()=>assert.fail('No deferred or uncertain move can reach Mail')};
  const previewReader = {readMessages:async(a,b,ids)=>ids.map(id=>({...rows[Number(id)-1],body:'Weekly roundup',rfcMessageId:id+'@example.test',localPreview:true}))};
  const engine = new MegasmartEngine(mail,directory,{rotatePreview:true, previewReader,
    localHeaders:async()=>({messages:rows,hasMore:false})});
  await engine.initialize();
  for (let run=0;run<3;run++) {
    const cache = new KeepCache(model,directory,{maxFresh:2}); engine.classifier=cache;
    const job = await engine.preview('Fixture','INBOX',undefined,'Trash'); cache.close();
    assert.equal(job.items.filter(i=>i.deferred).length,4);
    assert.ok(job.items.every(i=>i.action==='keep'&&i.protected&&!i.fingerprint));
    assert.equal(job.nextPreviewOffset, (run*2+2)%6);
  }
  assert.deepEqual(attempted,['1','2','3','4','5','6']);
  const changed = new KeepCache({...model,cacheNamespace:'fixture/v2'},directory,{maxFresh:2});engine.classifier=changed;
  await engine.preview('Fixture','INBOX',undefined,'Trash');changed.close();
  assert.deepEqual(attempted.slice(-2),['1','2']);
});
test('progress separates actual FM work, cached KEEP and deferred work', () => {
  const o=output();
  o.reporter.update({phase:'preview',checked:100,total:1000,modelStats:{fresh:4,completed:2,cacheHits:50,deferred:30}});
  assert.match(o.writes[0],/FM 2\/4 · Cache 50 · später 30/);
  o.reporter.close();
});

test('continuation follows the next message when earlier inbox rows disappear', async t => {
  const directory=await mkdtemp(join(tmpdir(),'meister-cursor-'));t.after(()=>rm(directory,{recursive:true,force:true}));
  let rows=Array.from({length:5},(_,n)=>({id:String(n+1),subject:'Weekly newsletter',sender:'news@example.test',dateReceived:'2020-01-01T00:00:00Z',isFlagged:false}));
  const attempted=[];
  const model={cacheNamespace:'fixture/v1',async classify(batch){attempted.push(...batch.map(r=>r.id));return batch.map(r=>({id:r.id,category:'uncertain',safeToTrash:false,reason:'retain'}));}};
  const engine=new MegasmartEngine({call:async()=>({mailboxes:[{name:'Trash'}]})},directory,{rotatePreview:true,
    localHeaders:async()=>({messages:rows,hasMore:false}),previewReader:{readMessages:async(a,b,ids)=>ids.map(id=>({...rows.find(r=>r.id===id),body:'Roundup',rfcMessageId:id+'@example.test',localPreview:true}))}});
  await engine.initialize();
  engine.classifier=new KeepCache(model,directory,{maxFresh:2});
  const first=await engine.preview('Fixture','INBOX',undefined,'Trash');engine.classifier.close();
  assert.equal(first.nextPreviewMessageID,'3');rows=rows.slice(2);
  engine.classifier=new KeepCache(model,directory,{maxFresh:2});
  await engine.preview('Fixture','INBOX',undefined,'Trash');engine.classifier.close();
  assert.deepEqual(attempted,['1','2','3','4']);
});
