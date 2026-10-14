import { spawn } from 'node:child_process';
import { createHash, randomUUID } from 'node:crypto';
import { readFile, mkdir, access, rename, rm, chmod } from 'node:fs/promises';
import { homedir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

export const mailPolicyVersion = 'meister.mail/v3';
const policyVersion = mailPolicyVersion;
const model = 'apple-on-device';
const categories = new Set(['newsletter', 'personal', 'financial', 'security', 'other', 'uncertain']);

/** Email content travels only through stdin, never argv, environment or logs. */
export function runClassifierProcess(file, args, { input = '', timeout = 45000, maxBuffer = 65536 } = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(file, args, { stdio: ['pipe', 'pipe', 'pipe'], shell: false });
    let stdout = ''; let size = 0; let settled = false; let terminationError;
    const finish = (error) => {
      if (settled) return;
      settled = true; clearTimeout(timer);
      error ? reject(error) : resolve({ stdout });
    };
    const terminate = error => {
      terminationError ??= error;
      child.kill('SIGKILL');
      // Reject only after close: the caller's worker slot still owns this process.
    };
    const timer = setTimeout(() => terminate(new Error('Local mail classifier timed out; nothing is authorized')), timeout);
    child.stdout.on('data', chunk => {
      size += chunk.length;
      if (size > maxBuffer) terminate(new Error('Invalid local classifier output'));
      else stdout += chunk;
    });
    // Compiler/model diagnostics may contain input; do not retain or print them.
    child.stderr.on('data', () => {});
    child.on('error', () => finish(new Error('Local mail classifier or compiler could not start')));
    child.on('close', code => finish(terminationError ?? (code === 0 ? null : new Error('Local Foundation Models unavailable or classifier failed; enable Apple Intelligence and install a compatible Xcode SDK'))));
    child.stdin.on('error', () => {});
    child.stdin.end(input);
  });
}

export class MailClassifier {
  constructor({ runner = runClassifierProcess, cacheDir = join(homedir(), 'Library/Caches/MeisterAI/MailClassifier'), helperPath, concurrency = 2 } = {}) {
    if (!Number.isInteger(concurrency) || concurrency < 1 || concurrency > 4) throw new Error('Mail classifier concurrency must be an integer from 1 to 4');
    this.cacheNamespace = policyVersion;
    this.concurrency = concurrency;
    this.runner = runner; this.cacheDir = cacheDir; this.helperPath = helperPath;
  }
  async executable() {
    if (this.helperPath) return this.helperPath;
    if (this.compiling) return this.compiling;
    this.compiling = this.compile();
    try { return await this.compiling; } catch (error) { this.compiling = null; throw error; }
  }
  async compile() {
    const source = join(dirname(fileURLToPath(import.meta.url)), 'MailClassifier.swift');
    const sourceData = await readFile(source);
    const sdk = (await this.runner('/usr/bin/xcrun', ['--sdk', 'macosx', '--show-sdk-path'], { timeout: 15000 })).stdout.trim();
    const version = (await this.runner('/usr/bin/xcrun', ['--sdk', 'macosx', '--show-sdk-version'], { timeout: 15000 })).stdout.trim();
    const compiler = (await this.runner('/usr/bin/xcrun', ['--find', 'swiftc'], { timeout: 15000 })).stdout.trim();
    if (!sdk.startsWith('/') || !compiler.startsWith('/') || Number.parseInt(version, 10) < 27) {
      throw new Error('Mail classification requires the local Xcode macOS 27 SDK; no cloud fallback is used');
    }
    const toolchain = (await this.runner(compiler, ['--version'], { timeout: 15000 })).stdout;
    const hash = createHash('sha256').update(sourceData).update(JSON.stringify([sdk, version, compiler, toolchain, process.arch, policyVersion])).digest('hex');
    await mkdir(this.cacheDir, { recursive: true, mode: 0o700 });
    const binary = join(this.cacheDir, `classifier-${hash}`);
    try { await access(binary); return binary; } catch { }
    const temporary = `${binary}.${randomUUID()}.tmp`;
    try {
      await this.runner(compiler, ['-parse-as-library', '-O', '-sdk', sdk, source, '-o', temporary], { timeout: 120000 });
      await chmod(temporary, 0o700); await rename(temporary, binary);
    } finally { await rm(temporary, { force: true }); }
    return binary;
  }
  async check() {
    const executable = await this.executable();
    let value;
    try { value = JSON.parse((await this.runner(executable, ['--check'], { timeout: 15000 })).stdout); }
    catch { throw new Error('Local Apple Foundation Models are unavailable; no heuristic or cloud fallback is used'); }
    if (!['true', true].includes(value.available) || value.model !== model || value.policyVersion !== policyVersion) {
      throw new Error('Local Apple Foundation Models are unavailable or incompatible');
    }
    this.availableChecked = true;
    return { available: true, model, policyVersion };
  }
  async classify(rows) {
    if (!Array.isArray(rows) || rows.some(row => !row || typeof row !== 'object' ||
      ['id', 'subject', 'sender', 'body'].some(key => typeof row[key] !== 'string') ||
      !row.id || row.id.length > 512 || !row.body.trim() || Buffer.byteLength(JSON.stringify({ rows: [row] })) > 1000000) ||
      new Set(rows.map(row => row.id)).size !== rows.length) throw new Error('Invalid mail classification input');
    if (!rows.length) return [];
    // CLI checks once per run; each Swift batch independently checks availability
    // again. Avoid an extra helper launch for every 25-message page.
    if (!this.availableChecked) await this.check();
    const executable = await this.executable(); const batches = [];
    // One process handles up to four isolated model sessions. Mail bodies never
    // share model context, but compiler/model startup is amortized per batch.
    // Small pages must use both workers too: four rows previously occupied
    // one serial helper while the second worker remained idle.
    const batchSize = Math.min(4, Math.ceil(rows.length / this.concurrency));
    for (let offset = 0; offset < rows.length;) {
      const batch = [];
      while (offset < rows.length && batch.length < batchSize) {
        const { id, subject, sender, body } = rows[offset];
        const candidate = { id, subject, sender, body };
        if (batch.length && Buffer.byteLength(JSON.stringify({ rows: [...batch, candidate] })) > 1000000) break;
        batch.push(candidate); offset++;
      }
      batches.push(batch);
    }
    const results = new Array(batches.length);
    let cursor = 0; let failure;
    const classifyBatch = async batch => {
      const decisions = [];
      let response;
      try {
        response = JSON.parse((await this.runner(executable, [], {
          input: JSON.stringify({ rows: batch }), timeout: 45000 * batch.length,
        })).stdout);
      } catch { throw new Error('Local mail classification failed; keep messages unchanged'); }
      const values = response?.results;
      if (response?.model !== model || response?.policyVersion !== policyVersion || !Array.isArray(values) || values.length !== batch.length ||
          new Set(values.map(v => v?.id)).size !== batch.length) throw new Error('Invalid local mail classification result; keep messages unchanged');
      for (const row of batch) {
        const value = values.find(v => v?.id === row.id);
        if (!value || !categories.has(value.category) || typeof value.safeToTrash !== 'boolean' ||
            typeof value.reason !== 'string' || !value.reason.trim() || value.reason.length > 2048 ||
            (value.safeToTrash && value.category !== 'newsletter')) throw new Error('Invalid local mail classification result; keep messages unchanged');
        decisions.push({ id: row.id, category: value.category, safeToTrash: value.safeToTrash, reason: value.reason });
      }
      return decisions;
    };
    // Bounded workers preserve source order and stop scheduling after the first
    // failure. Drain already-started work before returning any error so callers
    // never overlap retries with still-running classifier requests.
    const worker = async () => {
      while (!failure && cursor < batches.length) {
        const index = cursor++;
        try { results[index] = await classifyBatch(batches[index]); }
        catch (error) { failure ??= error; }
      }
    };
    await Promise.all(Array.from({ length: Math.min(this.concurrency, batches.length) }, worker));
    if (failure) throw failure;
    return results.flat();
  }
}
