#!/usr/bin/env bats
# Report-only load / process-swarm / fsmonitor checks (lib/core/process_swarm.sh).

setup() {
  log() { printf '%s %s\n' "$1" "$2"; }
  report_add() { printf '%s %s\n' "$1" "$2" >> "$BATS_TEST_TMPDIR/report"; }
  STUB="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$STUB"
  PATH="$STUB:$PATH"
  # ps answers the fsmonitor query from a fixture file (pid command).
  cat > "$STUB/ps" <<'EOF'
#!/bin/sh
cat "$PS_FIXTURE" 2>/dev/null
EOF
  # lsof prints a fixture in -Fpn format, or fails when LSOF_FAIL=1.
  cat > "$STUB/lsof" <<'EOF'
#!/bin/sh
[ "${LSOF_FAIL:-0}" = 1 ] && exit 1
cat "$LSOF_FIXTURE" 2>/dev/null
EOF
  chmod +x "$STUB/ps" "$STUB/lsof"
  PS_FIXTURE="$BATS_TEST_TMPDIR/ps.txt"
  LSOF_FIXTURE="$BATS_TEST_TMPDIR/lsof.txt"
  export PS_FIXTURE LSOF_FIXTURE
  : > "$PS_FIXTURE"
  : > "$LSOF_FIXTURE"
  source "$BATS_TEST_DIRNAME/../lib/core/process_swarm.sh"
}

# n lines of "pid uid stat comm" starting at pid base.
snapshot() {
  local n="$1" stat="$2" comm="$3" base="${4:-1000}" i=0
  while [ "$i" -lt "$n" ]; do
    printf '%s 501 %s %s\n' "$((base + i))" "$stat" "$comm"
    i=$((i + 1))
  done
}

# n fsmonitor daemons in `ps -axo pid=,command=` form.
fsmonitor_ps() {
  local n="$1" i=0
  while [ "$i" -lt "$n" ]; do
    printf '%s /opt/homebrew/opt/git/libexec/git-core/git fsmonitor--daemon run --detach --ipc-threads=8\n' "$((5000 + i))"
    i=$((i + 1))
  done
  printf '4999 /usr/bin/git status\n'
}

@test "load above twice the cores: WARN with ratio and grouped runnable commands" {
  input="$(snapshot 29 R /opt/homebrew/opt/git/libexec/git-core/git; snapshot 3 R+ /System/Library/Frameworks/CGPDFService 2000; snapshot 40 S /usr/libexec/mdworker_shared 3000)"
  run meister_load_check 172.91 14 <<<"$input"
  [ "$status" -eq 0 ]
  [[ "$output" == WARN* ]]
  [[ "$output" == *"172.91"* ]]
  [[ "$output" == *"14 cores"* ]]
  [[ "$output" == *"12.4x"* ]]
  [[ "$output" == *"git (29)"* ]]
  [[ "$output" == *"CGPDFService (3)"* ]]
  [[ "$output" != *"mdworker_shared"* ]]
  [ "$(grep -c . <<<"$output")" -eq 1 ]
}

@test "load above twice the cores: lists at most the top 5 runnable commands" {
  input="$(snapshot 6 R a 100; snapshot 5 R b 200; snapshot 4 R c 300; snapshot 3 R d 400; snapshot 2 R e 500; snapshot 1 R f 600)"
  run meister_load_check 40 4 <<<"$input"
  [ "$status" -eq 0 ]
  [[ "$output" == *"a (6), b (5), c (4), d (3), e (2)"* ]]
  [[ "$output" != *"f (1)"* ]]
}

@test "load above twice the cores: no WARN at or below the threshold" {
  run meister_load_check 28 14 <<<"$(snapshot 29 R git)"
  [ "$status" -eq 0 ]
  [[ "$output" != *WARN* ]]
}

@test "instance threshold: 20 instances give one swarm line, 19 none" {
  run meister_proc_swarm_counts 20 <<<"$(snapshot 19 S /usr/libexec/mdworker_shared)"
  [ "$status" -eq 0 ]
  [[ "$output" != *"Process swarm"* ]]

  run meister_proc_swarm_counts 20 <<<"$(snapshot 20 S /usr/libexec/mdworker_shared; snapshot 25 S '/Applications/Some App.app/Contents/MacOS/Some Helper' 3000; snapshot 2 S launchd 4000)"
  [ "$status" -eq 0 ]
  [ "$(grep -c 'Process swarm' <<<"$output")" -eq 1 ]
  [[ "$output" == WARN* ]]
  [[ "$output" == *"Some Helper (25), mdworker_shared (20)"* ]]
  [[ "$output" != *launchd* ]]
}

@test "instance threshold: defaults to 20 when the threshold is not numeric" {
  run meister_proc_swarm_counts abc <<<"$(snapshot 20 S git)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"git (20)"* ]]
}

@test "fsmonitor fleet: WARN splits daemons by socket path kind" {
  fsmonitor_ps 21 > "$PS_FIXTURE"
  {
    i=0
    while [ "$i" -lt 14 ]; do
      printf 'p%s\nn/Users/u/Developer/repo%s/.git/fsmonitor--daemon.ipc\n' "$((5000 + i))" "$i"
      i=$((i + 1))
    done
    printf 'p5014\nn/Users/u/Developer/repo with space/.git/fsmonitor--daemon.ipc\n'
    for i in 15 16 17 18; do
      printf 'p%s\nn/Users/u/Developer/repo/.git/worktrees/wt%s/fsmonitor--daemon.ipc\n' "$((5000 + i))" "$i"
    done
    printf 'p5019\nn/Users/u/Developer/repo/.git/modules/sub/fsmonitor--daemon.ipc\n'
    printf 'p5020\nn.git/fsmonitor--daemon.ipc\n'
  } > "$LSOF_FIXTURE"
  run meister_fsmonitor_report 20
  [ "$status" -eq 0 ]
  [ "$(grep -c 'git fsmonitor' <<<"$output")" -eq 1 ]
  [[ "$output" == WARN* ]]
  [[ "$output" == *"21 daemons"* ]]
  [[ "$output" == *"15/4/1/1"* ]]
  [[ "$output" == *"core.fsmonitor=false for batch git runs"* ]]
}

@test "fsmonitor fleet: below the threshold stays silent" {
  fsmonitor_ps 19 > "$PS_FIXTURE"
  run meister_fsmonitor_report 20
  [ "$status" -eq 0 ]
  [[ "$output" != *WARN* ]]
}

@test "degraded input: empty snapshot gives no output" {
  run meister_load_check 3.0 14 <<<""
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run meister_proc_swarm_counts 20 <<<""
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run meister_fsmonitor_report 20
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "degraded input: non-numeric load and empty ncpu" {
  run meister_load_check abc "" <<<"$(snapshot 29 R git)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"load unavailable"* ]]
  [[ "$output" != *FIX* ]]
  run meister_load_check "" 0 <<<"$(snapshot 29 R git)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"load unavailable"* ]]
}

@test "degraded input: zero ncpu is treated as one core" {
  run meister_load_check 2.5 0 <<<"$(snapshot 3 R git)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"1 cores (2.5x)"* ]]
  [[ "$output" != *FIX* ]]
}

@test "degraded input: failing lsof counts every daemon as unresolved" {
  fsmonitor_ps 21 > "$PS_FIXTURE"
  LSOF_FAIL=1 run meister_fsmonitor_report 20
  [ "$status" -eq 0 ]
  [[ "$output" == *"21 daemons"* ]]
  [[ "$output" == *"0/0/0/21"* ]]
  [[ "$output" != *FIX* ]]
}

@test "degraded input: missing lsof counts every daemon as unresolved" {
  fsmonitor_ps 21 > "$PS_FIXTURE"
  rm -f "$STUB/lsof"
  PATH="$STUB:/bin:/usr/bin" run meister_fsmonitor_report 20
  [ "$status" -eq 0 ]
  [[ "$output" == *"0/0/0/21"* ]]
}

@test "never signals: full run over the 260-daemon fixture records 0 calls" {
  rec="$BATS_TEST_TMPDIR/calls"
  : > "$rec"
  for cmd in kill pkill killall git launchctl; do
    printf '#!/bin/sh\necho "%s $*" >> "%s"\n' "$cmd" "$rec" > "$STUB/$cmd"
    chmod +x "$STUB/$cmd"
  done
  kill() { echo "kill $*" >> "$rec"; }
  fsmonitor_ps 260 > "$PS_FIXTURE"
  i=0
  while [ "$i" -lt 260 ]; do
    printf 'p%s\nn/Users/u/r%s/.git/fsmonitor--daemon.ipc\n' "$((5000 + i))" "$i"
    i=$((i + 1))
  done > "$LSOF_FIXTURE"
  snap="$(snapshot 260 R /opt/homebrew/opt/git/libexec/git-core/git 5000; snapshot 103 S SetStoreUpdateService 9000; snapshot 33 R mdworker_shared 12000)"
  run meister_load_check 172.91 14 <<<"$snap"
  [ "$status" -eq 0 ]
  run meister_proc_swarm_counts 20 <<<"$snap"
  [ "$status" -eq 0 ]
  [[ "$output" == *"git (260), SetStoreUpdateService (103), mdworker_shared (33)"* ]]
  run meister_fsmonitor_report 20
  [ "$status" -eq 0 ]
  [[ "$output" == *"260 daemons (260/0/0/0"* ]]
  unset -f kill
  [ ! -s "$rec" ]
}
