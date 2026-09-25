import { mkdir, open, readFile, unlink, readdir } from 'node:fs/promises';
import { join } from 'node:path';
import { homedir } from 'node:os';
async function acquirePIDLock(directory, name) {
  await mkdir(directory, { recursive: true, mode: 0o700 });
  const path = join(directory, name);
  let fd;
  try { fd = await open(path, 'wx', 0o600); }
  catch (error) {
    if (error.code !== 'EEXIST') throw error;
    const recoveryPath = join(directory, name === 'bridge.lock' ? 'bridge-recovery.lock' : 'run-recovery.lock');
    const recovery = await open(recoveryPath, 'wx', 0o600);
    try {
      const owner = Number(await readFile(path, 'utf8'));
      if (!Number.isSafeInteger(owner) || owner <= 0) throw new Error(`Ungültiger ${name}; Zustand zuerst prüfen`);
      let dead = false;
      try { process.kill(owner, 0); } catch (e) { if (e.code === 'ESRCH') dead = true; }
      if (!dead) throw new Error(`Ein aktiver Prozess besitzt ${name}`);
      await unlink(path); fd = await open(path, 'wx', 0o600);
    } finally { await recovery.close(); await unlink(recoveryPath); }
  }
  await fd.writeFile(String(process.pid)); await fd.sync(); await fd.close();
  return async () => { if (await readFile(path, 'utf8') === String(process.pid)) await unlink(path); };
}
export async function lockState(directory) { return acquirePIDLock(directory, 'run.lock'); }
export async function jobs(directory) {
  let names;
  try { names = await readdir(directory); } catch (e) { if (e.code === 'ENOENT') return []; throw e; }
  return Promise.all(names.filter(n => /^job-[a-f0-9-]+\.json$/.test(n)).map(n => readFile(join(directory, n), 'utf8').then(JSON.parse)));
}
export async function desktopFence() {
  const dir = join(homedir(), 'Library/Containers/com.merados.aufraum/Data/Library/Application Support/AufRaum/Megasmart');
  for (const job of await jobs(dir)) {
    if (job.status === 'applying' || job.items?.some(i => i.status === 'moving')) throw new Error('AufRaum hat einen laufenden oder ungeklärten Move. Dort zuerst prüfen; kein paralleler CLI-Lauf.');
  }
  let pid;
  try { pid = Number(await readFile(join(dir, 'bridge.lock'), 'utf8')); } catch (e) { if (e.code === 'ENOENT') return; throw e; }
  if (!Number.isSafeInteger(pid) || pid <= 0) throw new Error('Ungültiger AufRaum-Lock');
  if (pid === process.pid) return;
  try { process.kill(pid, 0); } catch (e) { if (e.code === 'ESRCH') return; throw e; }
  throw new Error('Der AufRaum-Mail-Helfer läuft noch. Vor CLI-Verschiebungen beenden, damit nicht zwei Aufräumer gleichzeitig arbeiten. scan und preview bleiben lesend verfügbar.');
}
export async function savedKeepDecisions() {
  const file = join(homedir(), 'Library/Containers/com.merados.aufraum/Data/Library/Application Support/AufRaum/Megasmart/decisions.json');
  try { return Object.fromEntries(Object.entries(JSON.parse(await readFile(file, 'utf8'))).filter(([, d]) => d.action === 'keep')); }
  catch (e) { if (e.code === 'ENOENT') return {}; throw e; }
}

// Use the desktop bridge's actual exclusive resource, not a check-then-act race.
export async function lockDesktop() {
  await desktopFence();
  const dir = join(homedir(), 'Library/Containers/com.merados.aufraum/Data/Library/Application Support/AufRaum/Megasmart');
  return acquirePIDLock(dir, 'bridge.lock');
}
