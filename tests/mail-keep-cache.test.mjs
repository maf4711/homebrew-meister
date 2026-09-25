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
