#!/usr/bin/env bats

setup() {
  export LOCKFILE="$BATS_TEST_TMPDIR/meister.lock"
  source "$BATS_TEST_DIRNAME/../lib/core/run_lock.sh"
  log() { :; }
}

@test "read-only cleanup cannot release another process lock" {
  acquire_lock
  owner=$RUN_LOCK_TOKEN
  RUN_LOCK_TOKEN=''
  release_lock
  [ "$(cat "$LOCKFILE.d/owner-$owner")" = "$owner" ]
  [ -f "$LOCKFILE" ]
}

@test "only current ownership token may release the shared lock" {
  acquire_lock
  token=$RUN_LOCK_TOKEN
  RUN_LOCK_TOKEN=wrong
  release_lock
  [ -d "$LOCKFILE.d" ]
  RUN_LOCK_TOKEN=$token
  release_lock
  [ ! -d "$LOCKFILE.d" ] && [ ! -f "$LOCKFILE" ]
}

@test "atomic acquisition refuses a live concurrent owner" {
  acquire_lock
  run acquire_lock
  [ "$status" -ne 0 ]
  release_lock
  acquire_lock
  release_lock
}

@test "legacy active lock remains protected" {
  printf '%s\n' "$$" > "$LOCKFILE"
  run acquire_lock
  [ "$status" -ne 0 ]
  [ -f "$LOCKFILE" ]
}

@test "dead-owner and abandoned empty locks recover without a persistent reaper" {
  mkdir "$LOCKFILE.d"
  printf '999999999:old\n' > "$LOCKFILE.d/owner"
  acquire_lock
  release_lock
  mkdir "$LOCKFILE.d" "$LOCKFILE.d.reap"
  acquire_lock
  [ -f "$LOCKFILE.d/owner-$RUN_LOCK_TOKEN" ]
  [ ! -d "$LOCKFILE.d.reap" ]
  release_lock
}

@test "SIGKILL before publish after publish and during release never strands a lock" {
  python3 - "$BATS_TEST_DIRNAME/../lib/core/run_lock.sh" "$BATS_TEST_TMPDIR" <<'PY'
import os,pathlib,subprocess,sys
library=pathlib.Path(sys.argv[1]).resolve(); root=pathlib.Path(sys.argv[2])
for stage in ['before','after','release']:
 lock=root/f'{stage}.lock'
 common='source "$LOCK_LIBRARY"; log() { :; }; '
 if stage=='before':
  action='meister_lock_publish() { kill -KILL "$$"; }; acquire_lock'
 elif stage=='after':
  action='meister_lock_publish() { /usr/bin/perl -e \'exit(rename($ARGV[0], $ARGV[1]) ? 0 : 1)\' "$1" "$2" || return; kill -KILL "$$"; }; acquire_lock'
 else:
  action='acquire_lock || exit; rm -f "$LOCKFILE" "$LOCKFILE.d/owner-$RUN_LOCK_TOKEN"; kill -KILL "$$"'
 env={**os.environ,'LOCKFILE':str(lock),'LOCK_LIBRARY':str(library)}
 result=subprocess.run(['/bin/bash','-c',common+action],env=env,capture_output=True,timeout=5)
 assert result.returncode==-9,(stage,result.returncode,result.stderr)
 recovered=subprocess.run(['/bin/bash','-c',common+'acquire_lock || exit 1; release_lock'],env=env,capture_output=True,timeout=5)
 assert recovered.returncode==0,(stage,recovered.stderr)
 assert not pathlib.Path(f'{lock}.d').exists()
PY
}

@test "concurrent stale recovery never removes a newly published live owner" {
  python3 - "$BATS_TEST_DIRNAME/../lib/core/run_lock.sh" "$BATS_TEST_TMPDIR" <<'PY'
import os,pathlib,subprocess,sys
library=pathlib.Path(sys.argv[1]).resolve(); root=pathlib.Path(sys.argv[2]); lock=root/'race.lock'
lockdir=pathlib.Path(f'{lock}.d'); lockdir.mkdir(); (lockdir/'owner-999999999:stale').write_text('999999999:stale\n')
env={**os.environ,'LOCKFILE':str(lock),'LOCK_LIBRARY':str(library),'CRITICAL_DIR':str(root/'critical'),'VIOLATIONS':str(root/'violations')}
script='''source "$LOCK_LIBRARY"; log() { :; }
for iteration in 1 2 3 4 5; do
 if acquire_lock; then
  if ! mkdir "$CRITICAL_DIR"; then printf 'overlap\n' >> "$VIOLATIONS"; exit 5; fi
  sleep 0.03
  if [ ! -f "$LOCKFILE.d/owner-$RUN_LOCK_TOKEN" ]; then printf 'lost-owner\n' >> "$VIOLATIONS"; fi
  rmdir "$CRITICAL_DIR"
  release_lock
 fi
 sleep 0.01
done
'''
workers=[subprocess.Popen(['/bin/bash','-c',script],env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE) for _ in range(6)]
for worker in workers:
 _,error=worker.communicate(timeout=15)
 assert worker.returncode==0,error
assert not (root/'violations').exists(),(root/'violations').read_text()
assert not lockdir.exists()
PY
}
