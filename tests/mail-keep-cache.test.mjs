import test from 'node:test';import assert from 'node:assert/strict';
import {mkdtemp,rm,writeFile,readFile,stat} from 'node:fs/promises';import {tmpdir} from 'node:os';import {join} from 'node:path';
import {KeepCache} from '../lib/mail/keep-cache.mjs';
test('exact-content KEEP reuse avoids model calls but never reuses a move authorization',async t=>{
 const dir=await mkdtemp(join(tmpdir(),'meister-keep-'));t.after(()=>rm(dir,{recursive:true,force:true}));
 const calls=[];const model={async check(){return true;},async classify(rows){calls.push(rows.map(r=>r.id));return rows.map(r=>({id:r.id,category:r.id==='keep'?'personal':'newsletter',safeToTrash:r.id!=='keep',reason:'fixture'}));}};
 const cache=new KeepCache(model,dir);await cache.load();
 const rows=['keep','move'].map(id=>({id,subject:'s',sender:'s',body:'complete '+id}));
 await cache.classify(rows);await cache.classify(rows);
 assert.deepEqual(calls,[['keep','move'],['move']]);
 await cache.classify([{...rows[0],body:'changed'}]);assert.deepEqual(calls[2],['keep']);
 const reloaded=new KeepCache(model,dir);await reloaded.load();const before=calls.length;
 const result=await reloaded.classify([rows[0]]);assert.equal(calls.length,before);assert.equal(result[0].safeToTrash,false);
 cache.close();reloaded.close();
});

const entry = id => ({ id, sender: 's', subject: 's', body: 'entire private body '+id });
const keepModel = { async check() { return true; }, async classify(rows) { return rows.map(r => ({ id:r.id, category:'personal', safeToTrash:false, reason:'private reason' })); } };
test('migration preserves exact KEEP keys and rejects invalid or move entries idempotently', async t => {
 const dir=await mkdtemp(join(tmpdir(),'meister-keep-migrate-'));t.after(()=>rm(dir,{recursive:true,force:true}));
 const calls=[];const model={...keepModel,async classify(rows){calls.push(rows.map(r=>r.id));return keepModel.classify(rows);}};
 const cache=new KeepCache(model,dir); const keys=['keep','move','invalid-category','invalid-boolean'].map(id=>cache.key(entry(id)));
 const entries={ [keys[0]]:{category:'financial',safeToTrash:false},[keys[1]]:{category:'newsletter',safeToTrash:true},
  [keys[2]]:{category:'unknown',safeToTrash:false},[keys[3]]:{category:'personal',safeToTrash:'false'}, bad:{category:'personal',safeToTrash:false} };
 const source=JSON.stringify({version:1,entries});await writeFile(cache.path,source);
 await cache.load(); await cache.load();
 const result=await cache.classify(['keep','move','invalid-category','invalid-boolean'].map(entry));
 assert.deepEqual(calls,[['move','invalid-category','invalid-boolean']]);assert.equal(result[0].category,'financial');
 assert.equal(await readFile(cache.path,'utf8'),source);cache.close();cache.close();
 // A migration marker prevents a changed legacy JSON file from being imported again.
 await writeFile(cache.path,JSON.stringify({version:1,entries:{[cache.key(entry('later'))]:{category:'personal',safeToTrash:false}}}));
 await cache.load();await cache.classify([entry('keep'),entry('later')]);assert.deepEqual(calls.at(-1),['later']);cache.close();
});
test('database and directory remain private and no bodies or reasons are persisted', async t=>{
 const dir=await mkdtemp(join(tmpdir(),'meister-keep-private-'));t.after(()=>rm(dir,{recursive:true,force:true}));
 const cache=new KeepCache(keepModel,dir);await Promise.all([cache.load(),cache.load()]);await cache.classify([entry('one')]);cache.close();
 assert.equal((await stat(dir)).mode&0o777,0o700);assert.equal((await stat(cache.databasePath)).mode&0o777,0o600);
 const data=await readFile(cache.databasePath);assert.equal(data.includes(Buffer.from('entire private body')),false);assert.equal(data.includes(Buffer.from('private reason')),false);
 await cache.load();const value=await cache.classify([entry('one')]);assert.equal(value[0].safeToTrash,false);assert.equal(cache.hits,1);cache.close();
});
test('invalid model result leaves no partial page in the persistent cache', async t=>{
 const dir=await mkdtemp(join(tmpdir(),'meister-keep-invalid-'));t.after(()=>rm(dir,{recursive:true,force:true}));
 const cache=new KeepCache({...keepModel,async classify(){return[{id:'foreign',category:'personal',safeToTrash:false}];}},dir);
 await assert.rejects(cache.classify([entry('one')]),/Incomplete/);cache.close();
 let calls=0;const clean=new KeepCache({...keepModel,async classify(rows){calls++;return keepModel.classify(rows);}},dir);
 await clean.classify([entry('one')]);assert.equal(calls,1);clean.close();
});

test('identical contents reuse only KEEP across message IDs and restarts', async t => {
 const dir=await mkdtemp(join(tmpdir(),'meister-keep-content-'));t.after(()=>rm(dir,{recursive:true,force:true}));
 let calls=0;const model={...keepModel,async classify(rows){calls+=rows.length;return keepModel.classify(rows);}};
 const original=entry('original');const cache=new KeepCache(model,dir);
 await cache.classify([original]);cache.close();
 const reopened=new KeepCache(model,dir);
 const result=await reopened.classify([{...original,id:'duplicate'}]);
 assert.equal(calls,1);assert.equal(result[0].id,'duplicate');assert.equal(result[0].safeToTrash,false);
 for (const field of ['subject','sender','body']) await reopened.classify([{...original,id:field,[field]:original[field]+' changed'}]);
 assert.equal(calls,4);reopened.close();
});
test('newsletter move decisions never cross message IDs or enter the content cache', async t => {
 const dir=await mkdtemp(join(tmpdir(),'meister-keep-move-'));t.after(()=>rm(dir,{recursive:true,force:true}));
 let calls=0;const cache=new KeepCache({async classify(rows){calls+=rows.length;return rows.map(r=>({id:r.id,category:'newsletter',safeToTrash:true,reason:'fixture'}));}},dir);
 const row=entry('first');await cache.classify([row]);await cache.classify([{...row,id:'second'}]);await cache.classify([row]);
 assert.equal(calls,3);assert.equal(cache.hits,0);cache.close();
});

test('classifier policy change bypasses old KEEP without deleting previous cache',async t=>{
 const dir=await mkdtemp(join(tmpdir(),'meister-keep-policy-'));t.after(()=>rm(dir,{recursive:true,force:true}));
 const row=entry('one');const legacy=new KeepCache(keepModel,dir);await legacy.classify([row]);legacy.close();
 let calls=0;const next=new KeepCache({...keepModel,cacheNamespace:'meister.mail/v2',async classify(rows){calls++;return keepModel.classify(rows);}},dir);
 await next.classify([row]);await next.classify([row]);assert.equal(calls,1);next.close();
 const changed=new KeepCache({...keepModel,cacheNamespace:'meister.mail/v3',async classify(rows){calls++;return keepModel.classify(rows);}},dir);
 await changed.classify([row]);assert.equal(calls,2);changed.close();
});
test('uncertain and transient generation failures are re-evaluated on subsequent runs',async t=>{
 const dir=await mkdtemp(join(tmpdir(),'meister-keep-uncertain-'));t.after(()=>rm(dir,{recursive:true,force:true}));
 let calls=0;const model={cacheNamespace:'meister.mail/v2',async classify(rows){calls++;return rows.map(r=>({id:r.id,category:'uncertain',safeToTrash:false,reason:'Model could not classify'}));}};
 const first=new KeepCache(model,dir);await first.classify([entry('one')]);first.close();
 const second=new KeepCache(model,dir);await second.classify([entry('one')]);assert.equal(calls,2);assert.equal(second.hits,0);second.close();
});

test('existing uncertain content row upgrades to definitive KEEP and then hits',async t=>{
 const dir=await mkdtemp(join(tmpdir(),'meister-keep-upgrade-'));t.after(()=>rm(dir,{recursive:true,force:true}));
 let calls=0;const cache=new KeepCache({...keepModel,cacheNamespace:'meister.mail/v2',async classify(rows){calls++;return keepModel.classify(rows);}},dir);
 await cache.load();const row=entry('one');cache.insert.run(cache.contentKey(row),'uncertain');
 await cache.classify([row]);await cache.classify([row]);assert.equal(calls,1);assert.equal(cache.hits,1);cache.close();
});


test('fresh count spans pages while cached KEEP bypasses exhausted limits', async t => {
 const dir=await mkdtemp(join(tmpdir(),'meister-keep-budget-'));t.after(()=>rm(dir,{recursive:true,force:true}));
 const seed=new KeepCache(keepModel,dir);await seed.classify([entry('cached')]);seed.close();
 const calls=[],events=[];const cache=new KeepCache({...keepModel,async classify(rows){calls.push(rows.map(r=>r.id));return keepModel.classify(rows);}},dir,{maxFresh:3,onProgress:event=>events.push(event)});
 const first=await cache.classify(['a','b','c','d'].map(entry));
 assert.deepEqual(calls,[['a','b'],['c']]);assert.equal(first[0].attempted,true);assert.equal(first[3].deferred,true);assert.equal(first[3].safeToTrash,false);
 const second=await cache.classify(['cached','e'].map(entry));assert.equal(second[0].cached,true);assert.equal(second[1].deferred,true);
 assert.deepEqual(cache.stats,{fresh:3,completed:3,deferred:2,cacheHits:1});assert.equal(events.at(-1).type,'deferred');cache.close();
 const reopened=new KeepCache(keepModel,dir,{maxFresh:2});await reopened.classify(['d','e'].map(entry));assert.equal(reopened.stats.fresh,2);reopened.close();
});
test('soft time budget drains one pair and starts no new calls after expiry', async t => {
 const dir=await mkdtemp(join(tmpdir(),'meister-keep-time-'));t.after(()=>rm(dir,{recursive:true,force:true}));
 let clock=10;const calls=[];
 const cache=new KeepCache({...keepModel,async classify(rows){calls.push(rows.map(r=>r.id));clock+=90;return keepModel.classify(rows);}},dir,{budgetMs:50,now:()=>clock});
 const result=await cache.classify(['a','b','c'].map(entry));assert.deepEqual(calls,[['a','b']]);assert.equal(result[2].deferred,true);
 const next=await cache.classify(['a','d'].map(entry));assert.equal(next[0].cached,true);assert.equal(next[1].deferred,true);assert.equal(calls.length,1);cache.close();
});
test('zero time budget never calls model and errors propagate without caching', async t => {
 const dir=await mkdtemp(join(tmpdir(),'meister-keep-errors-'));t.after(()=>rm(dir,{recursive:true,force:true}));
 const failure=new Error('real model failure');let calls=0;
 const model={async classify(){calls++;throw failure;}};
 const skipped=new KeepCache(model,dir,{budgetMs:0,now:()=>0});assert.equal((await skipped.classify([entry('one')]))[0].deferred,true);assert.equal(calls,0);skipped.close();
 const failing=new KeepCache(model,dir,{maxFresh:2});await assert.rejects(failing.classify([entry('one')]),error=>error===failure);assert.equal(failing.stats.fresh,1);assert.equal(failing.stats.completed,0);failing.close();
 const retry=new KeepCache(keepModel,dir);await retry.classify([entry('one')]);assert.equal(retry.stats.fresh,1);retry.close();
});
test('invalid later chunk leaves the entire page uncached and ignores model markers', async t => {
 const dir=await mkdtemp(join(tmpdir(),'meister-keep-chunk-'));t.after(()=>rm(dir,{recursive:true,force:true}));
 let calls=0;const cache=new KeepCache({async classify(rows){calls++;return calls===1?keepModel.classify(rows):[{id:'foreign',category:'personal',safeToTrash:false}];}},dir,{maxFresh:3});
 await assert.rejects(cache.classify(['a','b','c'].map(entry)),/Incomplete/);cache.close();
 const retry=new KeepCache({async classify(rows){return (await keepModel.classify(rows)).map(row=>({...row,cached:true,deferred:true,attempted:false}));}},dir,{maxFresh:3});
 const result=await retry.classify(['a','b','c'].map(entry));assert.equal(retry.stats.fresh,3);assert.equal(result[0].attempted,true);assert.equal(result[0].cached,undefined);assert.equal(result[0].deferred,undefined);retry.close();
});
