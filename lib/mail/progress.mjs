// Keep terminal output bounded while long Mail/FM requests are in flight.
export function createProgressReporter({ stream = process.stderr, now = () => performance.now(),
  schedule = setInterval, unschedule = clearInterval } = {}) {
  let latest, receivedAt = 0, lastWritten = -Infinity, lastPhase, lastCompleted = false, timer, closed = false;
  const render = (force = false) => {
    if (!latest || closed) return;
    const time = now();
    if (!force && time - lastWritten < (stream.isTTY ? 1000 : 10000)) return;
    const count = latest.checked ?? latest.moved ?? 0;
    const elapsed = latest.elapsedMs === undefined ? '' : ` · ${Math.floor((latest.elapsedMs + time - receivedAt) / 1000)}s`;
    const percent = latest.total ? Math.floor(count / latest.total * 100) : 100;
    const stats = latest.modelStats;
    const activity = stats ? ` · FM ${stats.completed}/${stats.fresh} · Cache ${stats.cacheHits} · später ${stats.deferred}`
      : latest.activity ? ` · ${latest.activity}` : '';
    const local = latest.localReads === undefined ? '' : ` · lokal ${latest.localReads} · unvollständig ${latest.unavailableReads ?? 0}`;
    let line = `${latest.phase}: ${count}/${latest.total} (${percent}%)${elapsed}${activity}${local}`;
    if (stream.isTTY) {
      const width = stream.columns || 120;
      if (line.length >= width) line = line.slice(0, Math.max(0, width - 2)) + '…';
      stream.write(`\r\x1b[2K${line}`);
    } else stream.write(line + '\n');
    lastWritten = time;
  };
  return {
    update(progress) {
      if (closed) return;
      const count = progress.checked ?? progress.moved ?? 0;
      const complete = count === progress.total;
      const force = progress.phase !== lastPhase || (complete && !lastCompleted);
      latest = progress; receivedAt = now();
      lastPhase = progress.phase; lastCompleted = complete;
      render(force);
      if (!timer) { timer = schedule(() => render(), 1000); timer.unref?.(); }
    },
    close() {
      if (closed) return;
      if (timer) unschedule(timer);
      if (latest && stream.isTTY) stream.write('\n');
      closed = true;
    },
  };
}
