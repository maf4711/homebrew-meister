import test from 'node:test';
import assert from 'node:assert/strict';
import { MailClassifier, runClassifierProcess } from '../lib/mail/fm-classifier.mjs';
const row = { id: 'm1', subject: 'News', sender: 'news@example.test', body: 'Complete mail body' };
const envelope = results => ({ model: 'apple-on-device', policyVersion: 'meister.mail/v3', results });
const decision = { id: 'm1', category: 'newsletter', safeToTrash: true, reason: 'Bulk informational newsletter.' };
test('one successful runtime preflight is reused while every classification still invokes the guarded helper', async () => {
  const { classifier, calls } = fixture();
  await classifier.check();
  await classifier.classify([row]); await classifier.classify([row]);
  assert.equal(calls.filter(c => c.args[0] === '--check').length, 1);
  assert.equal(calls.filter(c => c.args.length === 0).length, 2);
});
function fixture(output = envelope([decision])) {
  const calls = [];
  const runner = async (file, args, options) => {
    calls.push({ file, args, options });
    if (args[0] === '--check') return { stdout: JSON.stringify({ available: 'true', model: 'apple-on-device', policyVersion: 'meister.mail/v3' }) };
    return { stdout: typeof output === 'string' ? output : JSON.stringify(output) };
  };
  return { classifier: new MailClassifier({ runner, helperPath: '/test/classifier' }), calls };
}
test('classification uses full content on stdin only and returns exact IDs', async () => {
  const { classifier, calls } = fixture();
  assert.deepEqual(await classifier.classify([row]), [decision]);
  assert.equal(calls.length, 2);
  assert.deepEqual(calls[1].args, []);
  assert.deepEqual(JSON.parse(calls[1].options.input), { rows: [row] });
  assert.equal(calls[1].options.timeout, 45000);
});
test('invalid input never invokes model or compiler', async () => {
  for (const rows of [null, {}, [row, row], [{ ...row, body: '' }], [{ ...row, sender: null }], [{ ...row, body: 'x'.repeat(1000001) }]]) {
    const { classifier, calls } = fixture();
    await assert.rejects(classifier.classify(rows), /Invalid/);
    assert.equal(calls.length, 0);
  }
  const { classifier, calls } = fixture(); assert.deepEqual(await classifier.classify([]), []); assert.equal(calls.length, 0);
});
test('malformed, missing, duplicate and invented result IDs all fail closed', async () => {
  for (const response of ['broken JSON', envelope([]), envelope([decision, decision]), envelope([{ ...decision, id: 'other' }]),
    envelope([{ ...decision, safeToTrash: 'true' }]), envelope([{ ...decision, category: 'personal' }]),
    envelope([{ ...decision, category: 'invented' }]), envelope([{ ...decision, reason: '' }])]) {
    await assert.rejects(fixture(response).classifier.classify([row]));
  }
});
test('unavailable model has no fallback or classification call', async () => {
  let calls = 0;
  const classifier = new MailClassifier({ helperPath: '/test/classifier', runner: async () => {
    calls++; return { stdout: JSON.stringify({ available: false, model: 'apple-on-device', policyVersion: 'meister.mail/v3' }) };
  } });
  await assert.rejects(classifier.classify([row]), /unavailable/); assert.equal(calls, 1);
});
test('25 complete bodies are handled independently without truncation or shared sessions', async () => {
  const rows = Array.from({ length: 25 }, (_, i) => ({ ...row, id: String(i), body: 'body '.repeat(1000) }));
  let checks = 0, classifications = 0;
  const classifier = new MailClassifier({ helperPath: '/test/classifier', runner: async (file, args, options) => {
    if (args[0] === '--check') { checks++; return { stdout: JSON.stringify({ available: true, model: 'apple-on-device', policyVersion: 'meister.mail/v3' }) }; }
    const input = JSON.parse(options.input); assert.ok(input.rows.length <= 4);
    assert.ok(input.rows.every(r => r.body === rows[0].body)); classifications++;
    return { stdout: JSON.stringify(envelope(input.rows.map(r => ({ ...decision, id: r.id })))) };
  } });
  assert.equal((await classifier.classify(rows)).length, 25); assert.equal(checks, 1); assert.equal(classifications, 7);
});
test('uncertain context failure is returned only as keep', async () => {
  const output = { ...decision, category: 'uncertain', safeToTrash: false, reason: 'Complete email exceeds local model context; keep.' };
  assert.deepEqual(await fixture(envelope([output])).classifier.classify([row]), [output]);
  await assert.rejects(fixture(envelope([{ ...output, safeToTrash: true }])).classifier.classify([row]));
});

const available = { stdout: JSON.stringify({ available: true, model: 'apple-on-device', policyVersion: 'meister.mail/v3' }) };
const manyRows = count => Array.from({ length: count }, (_, i) => ({ ...row, id: String(i) }));
const responseFor = input => ({ stdout: JSON.stringify(envelope(JSON.parse(input).rows.map(r => ({ ...decision, id: r.id })))) });
const tick = () => new Promise(resolve => setImmediate(resolve));

test('bounded worker pool defaults to two and preserves input order across reversed completion', async () => {
  for (const concurrency of [undefined, 1, 2, 4]) {
    const limit = concurrency ?? 2;
    const pending = []; let active = 0, peak = 0;
    const classifier = new MailClassifier({ helperPath: '/test/classifier', concurrency, runner: async (file, args, options) => {
      if (args[0] === '--check') return available;
      active++; peak = Math.max(peak, active);
      return new Promise(resolve => pending.push(() => { active--; resolve(responseFor(options.input)); }));
    } });
    const rows = manyRows(33); const result = classifier.classify(rows);
    await tick(); assert.equal(active, limit);
    while (pending.length) { pending.pop()(); await tick(); }
    assert.deepEqual((await result).map(r => r.id), rows.map(r => r.id));
    assert.equal(peak, limit); assert.equal(active, 0);
  }
});

test('failed worker stops scheduling and waits for in-flight workers before rejecting', async () => {
  for (const malformed of [false, true]) {
    const pending = []; let started = 0, settled = false;
    const classifier = new MailClassifier({ helperPath: '/test/classifier', runner: async (file, args, options) => {
      if (args[0] === '--check') return available;
      started++;
      return new Promise((resolve, reject) => pending.push({ resolve, reject, input: options.input }));
    } });
    const result = classifier.classify(manyRows(20));
    const checked = assert.rejects(result, /classification/).then(() => { settled = true; });
    await tick(); assert.equal(started, 2);
    if (malformed) pending[0].resolve({ stdout: JSON.stringify(envelope([])) });
    else pending[0].reject(new Error('worker failed'));
    await tick(); assert.equal(settled, false); assert.equal(started, 2);
    // A second rejection must also be consumed, never leak as unhandled.
    pending[1].reject(new Error('second worker failed'));
    await checked; assert.equal(settled, true); assert.equal(started, 2);
  }
});

test('concurrency rejects unbounded, fractional and nonnumeric values', () => {
  for (const concurrency of [0, 5, -1, 1.5, '2', null, Infinity, NaN]) {
    assert.throws(() => new MailClassifier({ concurrency }), /concurrency/);
  }
});

test('large full bodies split requests under one megabyte including JSON envelope', async () => {
  const inputs = [];
  const classifier = new MailClassifier({ helperPath: '/test/classifier', runner: async (file, args, options) => {
    if (args[0] === '--check') return available;
    inputs.push(options.input); assert.ok(Buffer.byteLength(options.input) <= 1000000);
    return responseFor(options.input);
  } });
  const rows = manyRows(5).map(r => ({ ...r, body: 'x'.repeat(600000) }));
  assert.equal((await classifier.classify(rows)).length, 5);
  assert.equal(inputs.length, 5);
  assert.ok(inputs.every(input => JSON.parse(input).rows[0].body === rows[0].body));
  const base = { ...row, body: '' };
  const boundary = { ...base, body: 'x'.repeat(1000000 - Buffer.byteLength(JSON.stringify(base))) };
  await assert.rejects(classifier.classify([boundary]), /Invalid/);
});

 test('timed-out classifier subprocess has exited before rejection reaches caller', async () => {
  // The subprocess writes its PID to a private temporary file, never mail data.
  const { mkdtemp, readFile, rm } = await import('node:fs/promises');
  const { tmpdir } = await import('node:os');
  const { join } = await import('node:path');
  const directory = await mkdtemp(join(tmpdir(), 'meister-classifier-timeout-'));
  const pidPath = join(directory, 'pid');
  try {
    await assert.rejects(runClassifierProcess(process.execPath, ['-e',
      "require('node:fs').writeFileSync(process.argv[1], String(process.pid)); setInterval(() => {}, 1000)", pidPath], { timeout: 1000 }), /timed out/);
    const pid = Number(await readFile(pidPath, 'utf8'));
    assert.throws(() => process.kill(pid, 0), { code: 'ESRCH' });
  } finally { await rm(directory, { recursive: true, force: true }); }
});

 test('small pages distribute full independent inputs across both workers', async () => {
  for (const count of [2,3,4,5,6,7,8]) {
    const batches=[];
    const classifier=new MailClassifier({helperPath:'/test/classifier',runner:async(file,args,options)=>{
      if(args[0]==='--check')return available;
      batches.push(JSON.parse(options.input).rows);
      return responseFor(options.input);
    }});
    const rows=manyRows(count);const result=await classifier.classify(rows);
    assert.equal(batches.length,2);
    assert.ok(Math.abs(batches[0].length-batches[1].length)<=1);
    assert.deepEqual(batches.flat(),rows);
    assert.deepEqual(result.map(r=>r.id),rows.map(r=>r.id));
  }
});
