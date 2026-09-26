import { createHash } from 'node:crypto';
import { readFile, mkdir, chmod, open, lstat } from 'node:fs/promises';
import { join } from 'node:path';
import { DatabaseSync } from 'node:sqlite';
const categories = new Set(['newsletter', 'personal', 'financial', 'security', 'other', 'uncertain']);
const validKey = key => /^[a-f0-9]{64}$/.test(key);
// Persist only content hashes and KEEP categories. No message contents, model
// explanations or move approvals enter this database.
export class KeepCache {
  constructor(classifier, directory, { maxFresh = Infinity, budgetMs = Infinity, now = () => performance.now(), onProgress = () => {} } = {}) {
    if (!(maxFresh === Infinity || Number.isInteger(maxFresh) && maxFresh >= 0)) throw new Error('Invalid fresh classification limit');
    if (!(budgetMs >= 0)) throw new Error('Invalid classification time budget');
    this.maxFresh = maxFresh; this.budgetMs = budgetMs; this.now = now; this.onProgress = onProgress;
    this.startedAt = null;
    this.stats = { fresh: 0, completed: 0, deferred: 0, cacheHits: 0 };
    this.classifier = classifier; this.directory = directory;
    this.namespace = classifier.cacheNamespace ?? null;
    this.path = join(directory, 'fm-keep-cache.json');
    this.databasePath = join(directory, 'fm-keep-cache.sqlite');
    this.hits = 0; this.db = null; this.loading = null;
  }
  async check() { return this.classifier.check(); }
  async load() {
    if (this.loading) return this.loading;
    if (this.db) return;
    this.loading = this.initialize();
    try { await this.loading; } finally { this.loading = null; }
  }
  async initialize() {
    await mkdir(this.directory, { recursive: true, mode: 0o700 });
    if (!(await lstat(this.directory)).isDirectory()) throw new Error('Invalid private cache directory');
    await chmod(this.directory, 0o700);
    try { const file = await open(this.databasePath, 'wx', 0o600); await file.close(); }
    catch (error) { if (error.code !== 'EEXIST') throw error; }
    if (!(await lstat(this.databasePath)).isFile()) throw new Error('Invalid private cache file');
    await chmod(this.databasePath, 0o600);
    const db = new DatabaseSync(this.databasePath);
    try {
      db.exec(`PRAGMA busy_timeout=5000; PRAGMA journal_mode=DELETE; PRAGMA synchronous=FULL;
        CREATE TABLE IF NOT EXISTS keep_entries (
          key TEXT PRIMARY KEY CHECK(length(key)=64),
          category TEXT NOT NULL CHECK(category IN ('newsletter','personal','financial','security','other','uncertain')),
          safe_to_trash INTEGER NOT NULL DEFAULT 0 CHECK(safe_to_trash=0)
        ) WITHOUT ROWID;
        CREATE TABLE IF NOT EXISTS metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL) WITHOUT ROWID;`);
      if (!db.prepare("SELECT value FROM metadata WHERE key='json-v1-migrated'").get()) {
        let entries = {};
        try {
          const data = JSON.parse(await readFile(this.path, 'utf8'));
          if (data?.version === 1 && data.entries && typeof data.entries === 'object' && !Array.isArray(data.entries)) entries = data.entries;
        } catch (error) { if (error.code !== 'ENOENT') throw error; }
        db.exec('BEGIN IMMEDIATE');
        try {
          const insert = db.prepare('INSERT OR IGNORE INTO keep_entries (key,category) VALUES (?,?)');
          for (const [key, value] of Object.entries(entries)) {
            if (validKey(key) && value?.safeToTrash === false && categories.has(value.category)) insert.run(key, value.category);
          }
          db.prepare("INSERT OR IGNORE INTO metadata (key,value) VALUES ('json-v1-migrated','1')").run();
          db.exec('COMMIT');
        } catch (error) { db.exec('ROLLBACK'); throw error; }
      }
      this.lookup = db.prepare('SELECT category,safe_to_trash FROM keep_entries WHERE key=?');
      this.insert = db.prepare("INSERT INTO keep_entries (key,category) VALUES (?,?) ON CONFLICT(key) DO UPDATE SET category=excluded.category WHERE keep_entries.category='uncertain'");
      this.db = db;
    } catch (error) { db.close(); throw error; }
  }
  close() {
    if (this.loading) throw new Error('Wait for cache loading before closing');
    this.db?.close(); this.db = null; this.lookup = null; this.insert = null;
  }
  key(row) { return createHash('sha256').update(JSON.stringify(['meister.mail.keep/v1', ...(this.namespace ? [this.namespace] : []), row.id, row.sender, row.subject, row.body])).digest('hex'); }
  contentKey(row) { return createHash('sha256').update(JSON.stringify(['meister.mail.keep-content/v1', ...(this.namespace ? [this.namespace] : []), row.sender, row.subject, row.body])).digest('hex'); }
  progress(type) { this.onProgress({ type, ...this.stats }); }
  async classify(rows) {
    if (this.startedAt === null) this.startedAt = this.now();
    await this.load();
    const output = new Map(), fresh = [], keys = new Map(), kept = [];
    for (const row of rows) {
      if (keys.has(row.id)) throw new Error('Duplicate Apple FM cache input');
      const identityKey = this.key(row), contentKey = this.contentKey(row);
      keys.set(row.id, [identityKey, contentKey]);
      const contentSaved = this.lookup.get(contentKey);
      const saved = contentSaved ?? this.lookup.get(identityKey);
      if (saved?.safe_to_trash === 0 && saved.category !== 'uncertain' && categories.has(saved.category)) {
        output.set(row.id, { id: row.id, category: saved.category, safeToTrash: false, reason: 'Apple FM: unchanged content retains previous keep decision', cached: true });
        this.hits++; this.stats.cacheHits++;
        this.progress('cache-hit');
        // Promote legacy identity-bound KEEP decisions only when their exact
        // contents are available again. Never infer contents from old hashes.
        if (!contentSaved) kept.push([contentKey, saved.category]);
      } else fresh.push(row);
    }
    const bounded = this.maxFresh !== Infinity || this.budgetMs !== Infinity;
    for (let offset = 0; offset < fresh.length;) {
      if (this.stats.fresh >= this.maxFresh || this.now() - this.startedAt >= this.budgetMs) {
        for (const row of fresh.slice(offset)) {
          output.set(row.id, { id: row.id, category: 'uncertain', safeToTrash: false,
            reason: 'Apple FM: deferred until a later run because the fresh classification budget is exhausted', deferred: true });
          this.stats.deferred++;
        }
        this.progress('deferred');
        break;
      }
      // Drain each pair before admitting more work. The model's two workers
      // may exceed the soft deadline by one chunk; no work is abandoned.
      const size = bounded ? Math.min(2, this.maxFresh - this.stats.fresh) : fresh.length;
      const chunk = fresh.slice(offset, offset + size);
      this.stats.fresh += chunk.length;
      this.progress('fresh-start');
      const results = await this.classifier.classify(chunk);
      const freshIDs = new Set(chunk.map(row => row.id));
      if (!Array.isArray(results) || results.length !== chunk.length || new Set(results.map(r => r?.id)).size !== chunk.length || results.some(r => !freshIDs.has(r?.id))) throw new Error('Incomplete Apple FM cache input');
      for (const value of results) {
        const { attempted, cached, deferred, ...decision } = value;
        output.set(value.id, { ...decision, attempted: true });
        if (!value.deferred && value.safeToTrash === false && value.category !== 'uncertain' && categories.has(value.category)) kept.push([keys.get(value.id)[1], value.category]);
      }
      this.stats.completed += results.length;
      this.progress('fresh-complete');
      offset += chunk.length;
    }
    if (kept.length) {
      this.db.exec('BEGIN IMMEDIATE');
      try {
        for (const [key, category] of kept) this.insert.run(key, category);
        this.db.exec('COMMIT');
      } catch (error) { this.db.exec('ROLLBACK'); throw error; }
    }
    return rows.map(row => output.get(row.id));
  }
}
