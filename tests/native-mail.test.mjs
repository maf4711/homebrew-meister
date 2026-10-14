import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { NativeMail } from '../lib/mail/native-mail.mjs';
const message = id => ({ id, subject: 'Newsletter', sender: 'News <news@example.test>', dateReceived: '2026-09-01T12:00:00Z', isFlagged: false, body: 'Complete body', rfcMessageId: `<${id}@example.test>` });
test('shared native lane serializes concurrent fallback and confirmation and survives read failure', async () => {
  let release; const gate = new Promise(r => { release = r; });
  const started = []; let active = 0, peak = 0;
  const mail = new NativeMail({ runner: async payload => {
    started.push(payload.ids[0]); peak = Math.max(peak, ++active);
    if (payload.ids[0] === '1') { await gate; active--; throw new Error('failed read'); }
    active--; return { ok: true, messages: [message(payload.ids[0])] };
  } });
  const first = assert.rejects(mail.readMessages('A', 'INBOX', ['1']), /failed read/);
  const second = mail.readMessages('A', 'INBOX', ['2']);
  await Promise.resolve(); assert.deepEqual(started, ['1']); release();
  await first; assert.equal((await second)[0].id, '2'); assert.equal(peak, 1);
});
test('transient connection failures retry reads with a strict bound, never moves', async () => {
  const waits = []; let calls = 0;
  const transient = { ok: false, errorCode: -609, error: 'connection lost' };
  const mail = new NativeMail({ sleep: async ms => waits.push(ms), runner: async () => ++calls < 3 ? transient : { ok: true, messages: [message('1')] } });
  assert.equal((await mail.readMessages('A', 'INBOX', ['1'])).length, 1);
  assert.deepEqual(waits, [500, 1500]); assert.equal(calls, 3);
  for (const operation of ['read', 'move']) {
    calls = 0;
    const failed = new NativeMail({ sleep: async () => {}, runner: async () => { calls++; return transient; } });
    await assert.rejects(failed.invoke({ operation }), /connection lost/);
    assert.equal(calls, operation === 'read' ? 3 : 1);
  }
  calls = 0;
  const semantic = new NativeMail({ runner: async () => { calls++; return { ok: false, errorCode: -1, error: 'missing scope' }; } });
  await assert.rejects(semantic.invoke({ operation: 'read' }), /missing scope/); assert.equal(calls, 1);
});
test('one structured invocation reads a scoped batch in requested order', async () => {
  const calls = [];
  const mail = new NativeMail({ runner: async p => { calls.push(p); return { ok: true, messages: [message('2'), message('1')] }; } });
  const rows = await mail.readMessages('Personal "name"', 'INBOX', ['1', '2']);
  assert.deepEqual(rows.map(r => r.id), ['1', '2']);
  assert.equal(rows[0].rfcMessageId, '1@example.test');
  assert.equal(calls.length, 1);
  assert.equal(calls[0].account, 'Personal "name"');
});
test('invalid IDs, missing scope and unsupported mutations never invoke native code', async () => {
  let calls = 0;
  const mail = new NativeMail({ runner: async () => { calls++; } });
  for (const ids of [[], ['1', '1'], ['imap:foo'], ['1; do shell script'], Array.from({length:101}, (_,i)=>String(i+1))]) await assert.rejects(mail.readMessages('A', 'INBOX', ids));
  await assert.rejects(mail.readMessages('', 'INBOX', ['1']));
  await assert.rejects(mail.call('create-mailbox', { account: 'A', name: 'Trash' }));
  await assert.rejects(mail.call('batch-move-messages', { account: 'B', sourceAccount: 'A', sourceMailbox: 'INBOX', mailbox: 'Trash', ids: ['1'] }));
  assert.equal(calls, 0);
});
test('missing, duplicated, malformed and incomplete body metadata fail closed', async () => {
  for (const messages of [[], [message('2')], [{ ...message('1'), isFlagged: undefined }], [{ ...message('1'), body: undefined }], [{ ...message('1'), rfcMessageId: null }], [{ ...message('1'), dateReceived: 'invalid' }]]) {
    const mail = new NativeMail({ runner: async () => ({ ok: true, messages }) });
    await assert.rejects(mail.readMessages('A', 'INBOX', ['1']));
  }
});
test('identity snapshot requires explicit completeness, exact count and unique IDs', async () => {
  const complete = { ok: true, complete: true, count: 1, ids: [1], rfcs: ['<one@example.test>'] };
  const mail = new NativeMail({ runner: async () => complete });
  assert.deepEqual(await mail.identityRows('A', 'INBOX'), [{ row: { id: '1' }, rfc: 'one@example.test' }]);
  for (const result of [{ ...complete, complete: false }, { ...complete, count: 2 }, { ...complete, count: 2, ids: [1,1], rfcs: [...complete.rfcs, ...complete.rfcs] }, { ...complete, ids: [1], rfcs: [null] }]) {
    await assert.rejects(new NativeMail({runner:async()=>result}).identityRows('A','INBOX'));
  }
});
test('mutations report exact batch outcomes and never retry failures', async () => {
  const args = {account:'A', sourceAccount:'A', sourceMailbox:'INBOX', mailbox:'Deleted Messages', ids:['1','2']};
  for (const result of [{ok:false,error:'timeout'}, {ok:true,success:1,failed:1}, {ok:true,success:2,failed:0}]) {
    let calls = 0;
    const mail = new NativeMail({runner:async()=>{calls++; return result;}});
    if (result.failed === 0) assert.equal((await mail.call('batch-move-messages',args)).success,2);
    else await assert.rejects(mail.call('batch-move-messages',args));
    assert.equal(calls,1);
  }
});
test('helper checks running app before tell, uses native bulk projections and no GUI commands', async () => {
  const script = await readFile(new URL('../lib/mail/native-mail.applescript', import.meta.url), 'utf8');
  const main = script.slice(script.indexOf('on perform(p)'));
  assert.ok(main.indexOf('runningApplicationsWithBundleIdentifier') < main.indexOf('tell application "Mail"'));
  assert.match(script,/id of messages of box/);
  assert.match(script,/message id of messages of box/);
  assert.match(script,/Incomplete identity page/);
  assert.match(script,/Mailbox changed during identity projection/);
  assert.doesNotMatch(script,/\bactivate\b|\blaunch\b|do shell script/);
});
test('Objective-C argument lookups are grouped before coercion and native errors omit raw text', async () => {
  const script = await readFile(new URL('../lib/mail/native-mail.applescript', import.meta.url), 'utf8');
  assert.match(script, /set operation to \(p's objectForKey:"operation"\) as text/);
  assert.doesNotMatch(script, /p's objectForKey:"[^"]+" as (text|list|integer)/);
  assert.match(script, /"Native Mail operation failed \(" & n & "\)"/);
  assert.match(script, /if msg is in safeErrors then/);
  assert.doesNotMatch(script.slice(script.indexOf('on canonical'), script.indexOf('end canonical')), /\bresult\b/);
});

test('explicit empty RFC values preserve every ID but malformed nonempty identities fail', async () => {
  const result = {ok:true,complete:true,count:2,ids:[1,2],rfcs:['one@example.test','']};
  const rows=await new NativeMail({runner:async()=>result}).identityRows('A','INBOX');
  assert.equal(rows.length,2); assert.deepEqual(rows[1],{row:{id:'2'},rfc:''});
  const missing=await new NativeMail({runner:async()=>({ok:true,messages:[{...message('1'),rfcMessageId:''}]})}).readMessages('A','INBOX',['1']);
  assert.equal(missing[0].rfcMessageId,'');
  for(const invalid of [null,1,'bad id','<>','\n']) await assert.rejects(new NativeMail({runner:async()=>({...result,rfcs:['one@example.test',invalid]})}).identityRows('A','INBOX'));
});

test('background recovery is bounded and only ever used for reads',async()=>{
 const stopped={ok:false,errorCode:-2700,error:'Native Mail operation failed (-2700): Apple Mail must already be running'};
 let recovered=0,calls=0;
 const mail=new NativeMail({sleep:async()=>{},recover:async()=>{recovered++;},runner:async()=>++calls===1?stopped:{ok:true,messages:[message('1')]}});
 await mail.readMessages('A','INBOX',['1']);assert.equal(recovered,1);
 const broken=new NativeMail({sleep:async()=>{},recover:async()=>{recovered++;},runner:async()=>stopped});
 await assert.rejects(broken.invoke({operation:'move'}));assert.equal(recovered,1);
 await assert.rejects(broken.invoke({operation:'read'}));assert.equal(recovered,3);
 await assert.rejects(broken.invoke({operation:'read'}));assert.equal(recovered,3);
});

test('only native content read process timeouts are tagged as skippable',async()=>{
 const {defaultRunner}=await import('../lib/mail/native-mail.mjs');
 const timeout=async()=>{throw Object.assign(new Error('private command'),{killed:true,signal:'SIGTERM',code:null});};
 await assert.rejects(defaultRunner({operation:'read'},timeout),e=>e.code==='MAIL_READ_TIMEOUT'&&!e.message.includes('private'));
 for(const operation of ['move','identities','accounts']) await assert.rejects(defaultRunner({operation},timeout),e=>e.code!=='MAIL_READ_TIMEOUT');
 await assert.rejects(defaultRunner({operation:'read'},async()=>{throw Error('other failure');}),e=>e.code!=='MAIL_READ_TIMEOUT');
});

test('max-buffer and cancellation failures cannot be mistaken for read timeouts',async()=>{
 const {defaultRunner}=await import('../lib/mail/native-mail.mjs');
 for(const code of ['ERR_CHILD_PROCESS_STDIO_MAXBUFFER','ABORT_ERR','ENOENT']){
  await assert.rejects(defaultRunner({operation:'read'},async()=>{throw Object.assign(Error('failure'),{killed:true,signal:'SIGTERM',code});}),e=>e.code!=='MAIL_READ_TIMEOUT');
 }
});
