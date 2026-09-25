import test from 'node:test';
import assert from 'node:assert/strict';
import {parse} from '../scripts/megasmart.mjs';
import {mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';import {join} from 'node:path';
import {lockState,jobs} from '../lib/mail/state.mjs';
test('explicit commands and dry runs cannot silently mutate',()=>{
 assert.equal(parse([]).command,'run');
 assert.equal(parse(['--dry-run']).command,'preview');
 assert.equal(parse(['apply','a'.repeat(36),'--dry-run']).command,'status');
 assert.throws(()=>parse(['run','--account']),/Wert/);
 assert.throws(()=>parse(['run','--mailbox','Sent']),/Posteingang/);
 assert.throws(()=>parse(['apply','../../elsewhere']),/Job/);
 assert.throws(()=>parse(['--imap']),/Argument/);
});
test('exclusive process lock refuses a second runner and read-only status is independent',async t=>{
 const dir=await mkdtemp(join(tmpdir(),'meister-mail-lock-'));t.after(()=>rm(dir,{recursive:true,force:true}));
 const release=await lockState(dir);await assert.rejects(lockState(dir),/run.lock/);
 assert.deepEqual(await jobs(dir),[]);await release();const again=await lockState(dir);await again();
});
