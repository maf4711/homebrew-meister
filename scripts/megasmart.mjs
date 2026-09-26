#!/usr/bin/env node
import { createProgressReporter } from '../lib/mail/progress.mjs';
import { homedir } from 'node:os';
import { join, isAbsolute } from 'node:path';
import { pathToFileURL } from 'node:url';
import { localNewsletterHeaders } from '../lib/mail/local-index.mjs';
import { mailPolicyVersion } from '../lib/mail/fm-classifier.mjs';
import { KeepCache } from '../lib/mail/keep-cache.mjs';
import { MegasmartEngine } from '../lib/mail/engine.mjs';
import { lockState, jobs, desktopFence, lockDesktop, savedKeepDecisions } from '../lib/mail/state.mjs';

export function parse(args) {
  const options = { command: 'run', mailbox: 'INBOX', json: false };
  const input = [...args];
  if (input[0] && !input[0].startsWith('-')) options.command = input.shift();
  if (['apply', 'reconcile', 'status'].includes(options.command) && input[0] && !input[0].startsWith('-')) options.job = input.shift();
  while (input.length) {
    const key = input.shift();
    if (['--help', '-h'].includes(key)) options.command = 'help';
    else if (key === '--maintenance') options.maintenance = true;
    else if (key === '--full') options.full = true;
    else if (key === '--json') options.json = true;
    else if (['--dry-run', '-n'].includes(key)) options.dry = true;
    else if (['--account', '--mailbox', '--trash'].includes(key)) {
      if (!input[0] || input[0].startsWith('-') || /[\x00-\x1f]/.test(input[0])) throw new Error(`Wert fehlt: ${key}`);
      options[key.slice(2)] = input.shift();
    } else throw new Error(`Unbekanntes Argument: ${key}`);
  }
  if (!['scan', 'preview', 'run', 'apply', 'reconcile', 'status', 'help'].includes(options.command)) throw new Error('Unbekannter Mail-Befehl');
  if (['apply', 'reconcile'].includes(options.command) && !options.job) throw new Error('Job-ID erforderlich');
  if (options.job && !/^[a-f0-9-]{36}$/.test(options.job)) throw new Error('Ungültige Job-ID');
  if (!/^(inbox|posteingang)$/i.test(options.mailbox)) throw new Error('Nur ein ausdrücklich gewählter Posteingang ist erlaubt');
  if (options.dry && ['apply', 'reconcile'].includes(options.command)) options.command = 'status';
  if (options.dry && options.command === 'run') options.command = 'preview';
  return options;
}
const help = `MeisterAI megasmart | smartinbox [Befehl] [Optionen]
  scan                 Schnelle lokale Vorauswahl; keine Verschiebung
  preview              Vollständiger geprüfter Plan; keine Verschiebung
  run                  Standard: Apple FM prüft Inhalte; alte Newsletter in vorhandenen Papierkorb verschieben
  apply JOB            Gespeicherten Plan prüfen und ausführen
  reconcile JOB        Ungewisses Ergebnis lesend prüfen; niemals blind wiederholen
  status [JOB]         Gespeicherten Verlauf lesen; kein Mail-Zugriff
  --maintenance        32 neue FM-Prüfungen / 60s Budget; offene Nachrichten später prüfen
  --full               Vollständige Prüfung ohne Wartungsbudget
  --account NAME --mailbox INBOX --trash NAME --json --dry-run
Vorschau nur aus vollständigen lokalen Inhalten; Unlesbares bleibt ungeklärt erhalten.
Kein direkter IMAP-Zugang, keine AufRaum-GUI, kein Hintergrundzeitplan.
Apple Mail startet bei Bedarf im Hintergrund. Terminal braucht Automation und lokalen Mail-Dateizugriff.
Recap: Newsletter älter als sieben Tage; Wichtiges und Unklares behalten; Papierkorb nie leeren.`;
function summary(job) {
  return { id: job.id, status: job.status, account: job.account, scanned: job.scanned, headersScanned: job.headersScanned ?? job.scanned,
    planned: job.items.filter(i => i.action === 'move').length,
    kept: job.items.filter(i => i.action === 'keep').length,
    unavailable: job.items.filter(i => i.localUnavailable || i.nativeUnverified).length,
    nativeUnverified: job.items.filter(i => i.nativeUnverified).length,
    deferred: job.items.filter(i => i.deferred).length,
    fmClassified: job.items.filter(i => i.classification && !i.deferred).length,
    fmUncertain: job.items.filter(i => i.classification?.category === 'uncertain' && !i.deferred).length,
    moved: job.items.filter(i => i.status === 'moved').length,
    uncertain: job.items.filter(i => i.status === 'moving').length, hasMore: job.hasMore, error: job.error };
}
export async function main(args = process.argv.slice(2)) {
  const o = parse(args);
  if (o.command === 'help') { console.log(help); return; }
  const stateRoot = process.env.MEISTER_DIR || join(homedir(), '.meister');
  if (!isAbsolute(stateRoot) || stateRoot.split('/').includes('..') || stateRoot === '/') throw new Error('Ungültiger MEISTER_DIR');
  const directory = join(stateRoot, 'mail');
  const emit = value => {
    console.log(JSON.stringify(value, null, o.json ? 0 : 2));
    if (!o.json) console.log('Recap: ' + (value.status === 'completed' ? `Lauf abgeschlossen; ${value.deferred ?? 0} zur späteren Modellprüfung zurückgestellt; ${value.unavailable ?? 0} nicht lokal lesbare Inhalte bleiben ungeklärt erhalten.` : 'Nur bestätigte Verschiebungen zählen; keine wiederkehrende Automatik.'));
  };
  if (o.command === 'status') {
    const records = await jobs(directory);
    const selected = o.job ? records.filter(j => j.id === o.job) : records;
    if (o.job && !selected.length) throw new Error('Job nicht gefunden');
    emit({ jobs: selected.map(summary) }); return;
  }
  const { NativeMail, recoverMailInBackground } = await import('../lib/mail/native-mail.mjs');
  const mail = new NativeMail({ recover: recoverMailInBackground });
  const mutating = ['run', 'apply'].includes(o.command);
  if (mutating) await desktopFence();
  const release = await lockState(directory);
  let releaseDesktop;
  let engine; let classifier; let interrupted = false;
  let latestProgress; let latestProgressAt = 0;
  const bounded = o.maintenance && !o.full;
  const progressReporter = createProgressReporter();
  const interrupt = () => { interrupted = true; if (engine?.running) engine.cancellations.add(engine.running); };
  process.on('SIGINT', interrupt); process.on('SIGTERM', interrupt);
  try {
    if (mutating) releaseDesktop = await lockDesktop();
    const onProgress = progress => {
      if (interrupted) throw new Error('Abgebrochen; gespeicherten Jobstatus prüfen.');
      latestProgress = progress; latestProgressAt = performance.now();
      progressReporter.update(progress);
    };
    if (['preview', 'run'].includes(o.command)) {
      const { MailClassifier } = await import('../lib/mail/fm-classifier.mjs');
      classifier = new KeepCache(new MailClassifier({ cacheDir: join(directory, 'fm') }), directory, {
        ...(bounded ? { maxFresh: 32, budgetMs: 60000 } : {}),
        onProgress: stats => {
          if (interrupted) throw new Error('Abgebrochen; gespeicherten Jobstatus prüfen.');
          if (latestProgress) progressReporter.update({ ...latestProgress, elapsedMs: latestProgress.elapsedMs === undefined ? undefined : latestProgress.elapsedMs + performance.now() - latestProgressAt, modelStats: stats });
        },
      });
      await classifier.check(); await classifier.load();
    }
    let previewReader;
    if (classifier) {
      const { LocalContentReader } = await import('../lib/mail/local-content.mjs');
      previewReader = new LocalContentReader({ nativeMail: mail });
    }
    const localHeaders = async (account, mailbox, before) => {
      const listing = await localNewsletterHeaders(account, mailbox, before, true);
      if (previewReader) await previewReader.configure(account, mailbox, listing);
      return listing;
    };
    engine = new MegasmartEngine(mail, directory, { localHeaders, classifier, previewReader, onProgress, rotatePreview: bounded });
    await engine.initialize();
    engine.decisions = { ...await savedKeepDecisions(), ...engine.decisions };
    if (o.command === 'reconcile') { emit(summary(await engine.reconcile(o.job))); return; }
    let job;
    if (o.command === 'apply') job = engine.job(o.job);
    else {
      const { accounts } = await mail.call('list-accounts', {});
      const matches = accounts.filter(a => o.account ? a.name === o.account : a.emailAddresses?.some(e => e.toLowerCase() === 'foellmer@mac.com'));
      if (matches.length !== 1) throw new Error('Konto nicht eindeutig: --account NAME angeben');
      const account = matches[0].name;
      if (o.command === 'scan') {
        const start = Date.now();
        const result = await localNewsletterHeaders(account, o.mailbox, new Date(Date.now() - 7 * 86400000).toISOString(), true);
        emit({ status: 'candidates-only', account, headersScanned: result.headersScanned, candidates: result.messages.length, elapsedMs: Date.now() - start, moved: 0 }); return;
      }
      const { mailboxes } = await mail.call('list-mailboxes', { account });
      const trash = o.trash ?? (matches[0].emailAddresses?.some(e => e.toLowerCase() === 'foellmer@mac.com') && mailboxes.some(b => b.name === 'Deleted Messages') ? 'Deleted Messages' : undefined);
      if (!trash) throw new Error('Vorhandenen Papierkorb mit --trash NAME angeben');
      job = await engine.preview(account, o.mailbox, undefined, trash);
    }
    if (mutating) {
      if (interrupted || job.hasMore) throw new Error('Unvollständiger oder abgebrochener Plan wird nicht angewendet');
      if (job.policy?.classifier !== 'apple-fm' || job.policy.classifierVersion !== mailPolicyVersion) throw new Error('Alter Plan ohne aktuelle Apple-FM-Prüfung; eine neue preview erstellen');
      await desktopFence();
      await engine.apply(job.id); await engine.task;
    }
    emit({ ...summary(job), modelKeepCacheHits: classifier?.hits ?? 0, modelWork: classifier?.stats, localContent: previewReader?.stats });
    if (mutating && job.status !== 'completed') process.exitCode = 1;
  } finally {
    progressReporter.close();
    process.off('SIGINT', interrupt); process.off('SIGTERM', interrupt);
    try { classifier?.close(); }
    finally { try { if (releaseDesktop) await releaseDesktop(); } finally { await release(); } }
  }
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) main().catch(e => {
  console.error(`Megasmart: ${e.message}\nRecap: Kein bestätigter Aufräumabschluss.`); process.exitCode = 1;
});
