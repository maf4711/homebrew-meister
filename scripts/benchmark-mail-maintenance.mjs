#!/usr/bin/env node
// Offline work comparison. Does not access Apple Mail or a real model.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve, dirname } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const candidateRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const baselineRoot = process.argv[2] ? resolve(process.argv[2]) : null;
if (!baselineRoot) throw new Error('Usage: node scripts/benchmark-mail-maintenance.mjs BASELINE_CHECKOUT');
const files = ['lib/mail/engine.mjs', 'lib/mail/state.mjs', 'lib/mail/keep-cache.mjs', 'lib/mail/pipeline.mjs',
  'lib/mail/progress.mjs', 'scripts/megasmart.mjs', 'scripts/homebrew-launcher.sh',
  'lib/core/ai_updates.sh', 'MeisterAI.sh', 'meister.sh'];
async function receipt(root) {
  return Object.fromEntries(await Promise.all(files.map(async file => [file,
    createHash('sha256').update(await readFile(join(root, file))).digest('hex')])));
}

async function run(root, bounded, unavailableOnly) {
  const { MegasmartEngine } = await import(pathToFileURL(join(root, 'lib/mail/engine.mjs')));
  const { KeepCache } = await import(pathToFileURL(join(root, 'lib/mail/keep-cache.mjs')));
  const directory = await mkdtemp(join(tmpdir(), 'meister-offline-benchmark-'));
  let readRows = 0, readBatches = 0, nativeReads = 0, modelRows = 0;
  const rows = Array.from({ length: 13424 }, (_, n) => ({ id: String(n + 1), subject: 'Weekly newsletter',
    sender: 'news@example.test', dateReceived: '2020-01-01T00:00:00Z', isFlagged: false }));
  const classifier = new KeepCache({ cacheNamespace: 'offline-fixture', async classify(batch) {
    modelRows += batch.length;
    return batch.map(row => ({ id: row.id, category: 'other', safeToTrash: false, reason: 'fixture' }));
  } }, directory, { maxFresh: 32, budgetMs: 60000 });
  try {
    const engine = new MegasmartEngine({
      call: async () => ({ mailboxes: [{ name: 'Trash' }] }),
      readMessages: async () => { nativeReads++; assert.fail('Fixture never authorizes a move'); },
    }, directory, {
      classifier, rotatePreview: true, persist: async () => {},
      ...(bounded ? { previewRowLimit: 500, previewBudgetMs: 60000 } : {}),
      localHeaders: async () => ({ messages: rows, hasMore: false, headersScanned: rows.length }),
      previewReader: { async readMessages(a, b, ids) {
        readRows += ids.length; readBatches++;
        return ids.map(id => {
          const n = Number(id), available = !unavailableOnly && n % 5 === 0;
          return { ...rows[n - 1], body: available ? n % 25 === 0 ? 'Weekly roundup ' + id : 'Your invoice payment' : '',
            rfcMessageId: available ? id + '@example.test' : '', localPreview: true,
            ...(!available ? { localUnavailable: true } : {}) };
        });
      } },
    });
    const started = performance.now();
    const job = await engine.preview('Fixture', 'INBOX', undefined, 'Trash');
    assert.ok(job.items.every(item => item.action === 'keep' && !item.fingerprint));
    return { headers: rows.length, scanned: job.scanned, unscanned: job.unscanned ?? 0,
      readRows, readBatches, nativeReads, modelRows,
      fixtureWallMs: Math.round((performance.now() - started) * 100) / 100,
      nextMessageID: job.nextPreviewMessageID,
      decisions: job.items.map(({ messageID, action, protected: protectedMail, localUnavailable, classification }) =>
        ({ messageID, action, protectedMail, localUnavailable, classification })) };
  } finally { classifier.close(); await rm(directory, { recursive: true, force: true }); }
}

const results = {};
for (const [name, unavailableOnly] of [['unavailable', true], ['mixed', false]]) {
  const baseline = await run(baselineRoot, false, unavailableOnly);
  const candidate = await run(candidateRoot, true, unavailableOnly);
  assert.deepEqual(candidate.decisions, baseline.decisions.slice(0, candidate.scanned));
  delete baseline.decisions; delete candidate.decisions;
  results[name] = { baseline, candidate,
    bodyWorkReductionPercent: Math.round((1 - candidate.readRows / baseline.readRows) * 10000) / 100 };
}
console.log(JSON.stringify({ fixtureOnly: true,
  note: 'Work counts and stub timing only; real Mail/FM end-to-end latency is unmeasured.',
  sourceHashes: { baseline: await receipt(baselineRoot), candidate: await receipt(candidateRoot) }, results }, null, 2));
