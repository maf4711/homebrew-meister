#!/usr/bin/env bats
setup() {
  export MEISTER_DIR="$BATS_TEST_TMPDIR/meister"
  mkdir -p "$MEISTER_DIR"
  LOGFILE="$MEISTER_DIR/meister.log"
  printf 'run\nrun\nrun\n' > "$MEISTER_DIR/history.log"
  periodic() { :; }
  DRY_RUN=false
  log() { printf '%s %s\n' "$1" "$2"; }
  bw_phase() { :; }
  report_add() { printf '%s %s\n' "$1" "$2"; }
  for fn in log_analysis module_sleep_blockers module_system_maintenance; do
    eval "$(awk -v name="$fn" '$0==name"() {" {on=1} on {print} on && /^}$/ {exit}' "$BATS_TEST_DIRNAME/../MeisterAI.sh")"
  done
}
write_run() {
  printf '%s 10:00:00 - INFO - MeisterAI v6.25 started (test)\n' "$(date +%F)" >> "$LOGFILE"
  for msg in "$@"; do
    printf '%s 10:00:01 - WARN - %s\n' "$(date +%F)" "$msg" >> "$LOGFILE"
  done
}
@test "repeated lines within one run are not recurring runs" {
  write_run noisy noisy noisy
  run log_analysis
  [[ "$output" != *' - noisy'* ]]
}
@test "only latest five runs contribute recurring warnings" {
  write_run obsolete; write_run obsolete; write_run obsolete
  for i in 1 2 3 4 5; do write_run; done
  run log_analysis
  [[ "$output" != *' - obsolete'* ]]
}
@test "three distinct recent runs produce one recurring entry" {
  write_run ongoing; write_run ongoing; write_run ongoing
  run log_analysis
  [[ "$output" == *' - ongoing'* ]]
}
@test "old timestamps are excluded even if log was recently modified" {
  for i in 1 2 3; do
    printf '2020-01-01 10:00:00 - INFO - MeisterAI v6.25 started (test)\n2020-01-01 10:00:01 - WARN - obsolete\n' >> "$LOGFILE"
  done
  run log_analysis
  [[ "$output" != *' - obsolete'* ]]
}
@test "sleep assertions deduplicate process names after first entry" {
  pmset() {
    printf ' pid 1(first): PreventUserIdleSystemSleep\n pid 2(second): PreventSystemSleep\n pid 2(second): PreventUserIdleSystemSleep\n'
  }
  run module_sleep_blockers
  [[ "$output" == *'2 sleep blocker(s) active: first, second'* ]]
}
@test "sudo unavailable skips system tasks without claiming fixes" {
  sudo_has_ticket() { return 1; }
  sudo() { echo MUTATION; }
  run module_system_maintenance
  [ "$status" = 0 ]
  [[ "$output" == *WARN* ]]
  [[ "$output" != *FIX* && "$output" != *MUTATION* ]]
}
@test "failed privileged command produces error and no success summary" {
  sudo_has_ticket() { return 0; }
  sudo() { return 1; }
  run module_system_maintenance
  [ "$status" != 0 ]
  [[ "$output" == *ERROR* && "$output" != *FIX* ]]
}
@test "successful privileged commands report completion" {
  sudo_has_ticket() { return 0; }
  sudo() { echo "$*" >> "$MEISTER_DIR/calls"; }
  run module_system_maintenance
  [ "$status" = 0 ]
  [[ "$output" == *'FIX Ran periodic scripts & DNS flush'* ]]
  [ "$(wc -l < "$MEISTER_DIR/calls" | tr -d ' ')" = 4 ]
}
@test "system maintenance preview invokes no sudo" {
  DRY_RUN=true
  sudo_has_ticket() { echo MUTATION; return 0; }
  sudo() { echo MUTATION; }
  run module_system_maintenance
  [ "$status" = 0 ]
  [[ "$output" == *WOULD* && "$output" != *MUTATION* ]]
}

load_security_helpers() {
  for fn in firewall_state xprotect_recent_activity; do
    eval "$(awk -v name="$fn" '$0==name"() {" {on=1} on {print} on && /^}$/ {exit}' "$BATS_TEST_DIRNAME/../MeisterAI.sh")"
  done
}
@test "firewall distinguishes unreadable from disabled without sudo" {
  load_security_helpers
  timeout() { return 1; }
  run firewall_state
  [ "$output" = unknown ]
  timeout() { printf 'Firewall is disabled. (State = 0)\n'; }
  run firewall_state
  [ "$output" = disabled ]
  timeout() { printf 'Firewall is enabled. (State = 1)\n'; }
  run firewall_state
  [ "$output" = enabled ]
}
@test "XProtect headers do not count as activity and query bypasses log function" {
  load_security_helpers
  timeout() {
    [ "$2" = /usr/bin/log ] || return 9
    printf 'Timestamp Thread Type Activity PID TTL\n'
  }
  run xprotect_recent_activity
  [ "$status" = 1 ]
  timeout() { printf '2026-09-17 09:00:00.000 Df XProtect event\n'; }
  run xprotect_recent_activity
  [ "$status" = 0 ]
  timeout() { return 124; }
  run xprotect_recent_activity
  [ "$status" = 2 ]
}

@test "security findings reach report instead of a false OK" {
  load_security_helpers
  local body
  body=$(awk '$0=="module_xprotect() {" {on=1} on {print} on && /^}$/ {exit}' "$BATS_TEST_DIRNAME/../MeisterAI.sh")
  body=${body//\/Library\/Apple\/System\/Library\/CoreServices/$MEISTER_DIR}
  eval "$body"
  mkdir -p "$MEISTER_DIR/XProtect.bundle" "$MEISTER_DIR/XProtect.app"
  DRY_RUN=true
  NEEDS_SUDO=false
  spctl() { echo enabled; }
  csrutil() { echo enabled; }
  stat() { echo "$(( $(date +%s) - 20 * 86400 ))"; }
  timeout() { return 1; }
  sudo() { echo MUTATION; return 1; }
  run module_xprotect
  [[ "$output" == *'WARN XProtect signatures: 20 days old'* ]]
  [[ "$output" == *'WARN macOS Firewall state could not be checked'* ]]
  [[ "$output" == *'WARN XProtect Remediator activity could not be checked'* ]]
  [[ "$output" != *'SUCCESS macOS Security'* && "$output" != *MUTATION* ]]
}

@test "missing periodic skips scripts and truthfully reports only DNS" {
  unset -f periodic
  command() { [ "$*" = '-v periodic' ] && return 1; builtin command "$@"; }
  sudo_has_ticket() { return 0; }
  sudo() { echo "$*" >> "$MEISTER_DIR/calls"; }
  run module_system_maintenance
  [ "$status" = 0 ]
  [[ "$output" == *'FIX DNS cache flushed'* ]]
  [[ "$output" != *'Ran periodic'* ]]
  [ "$(cat "$MEISTER_DIR/calls")" = '-n dscacheutil -flushcache' ]
}

@test "missing periodic preview never promises scripts or invokes sudo" {
  unset -f periodic
  command() { [ "$*" = '-v periodic' ] && return 1; builtin command "$@"; }
  DRY_RUN=true
  sudo() { echo MUTATION; }
  run module_system_maintenance
  [ "$status" = 0 ]
  [[ "$output" == *'WOULD Flush DNS cache'* ]]
  [[ "$output" != *'periodic scripts'* && "$output" != *MUTATION* ]]
}

load_preference_inspector() {
  eval "$(awk '$0=="inspect_preference_plist() {" {on=1} on {print} on && /^}$/ {exit}' "$BATS_TEST_DIRNAME/../MeisterAI.sh")"
}

@test "invalid and inaccessible preferences remain byte-identical without repair claims" {
  load_preference_inspector
  local plist="$MEISTER_DIR/example.plist"
  printf 'invalid settings\n' > "$plist"
  cp "$plist" "$MEISTER_DIR/original"
  plutil() { echo 'Unexpected character at line 1'; return 1; }
  run inspect_preference_plist "$plist"
  [[ "$output" == *'validation failed'* && "$output" != *FIX* ]]
  cmp "$plist" "$MEISTER_DIR/original"
  plutil() { echo 'Operation not permitted'; return 1; }
  run inspect_preference_plist "$plist"
  [[ "$output" == *inaccessible* && "$output" != *FIX* ]]
  cmp "$plist" "$MEISTER_DIR/original"
  [ "$(find "$MEISTER_DIR" -name '*.bad.*' | wc -l | tr -d ' ')" = 0 ]
}

@test "Apple preferences are not probed and valid or vanished files are quiet" {
  load_preference_inspector
  touch "$MEISTER_DIR/com.apple.test.plist"
  plutil() { echo PROBED; return 1; }
  run inspect_preference_plist "$MEISTER_DIR/com.apple.test.plist"
  [ "$output" = '' ]
  run inspect_preference_plist "$MEISTER_DIR/missing.plist"
  [ "$output" = '' ]
  touch "$MEISTER_DIR/example.plist"
  plutil() { return 0; }
  run inspect_preference_plist "$MEISTER_DIR/example.plist"
  [ "$output" = '' ]
}

@test "doctor measures writable data volume when present" {
  source "$BATS_TEST_DIRNAME/../lib/commands/extras.sh"
  df() {
    printf '%s\n' "$*" > "$MEISTER_DIR/df-args"
    printf 'Filesystem Size Used Avail Capacity Mounted\ndisk 100 83 17 83%% /\n'
  }
  run cmd_doctor_json
  [ "$status" = 0 ]
  [[ "$output" == *'"disk_used_pct": 83'* ]]
  if [ -d /System/Volumes/Data ]; then
    [ "$(cat "$MEISTER_DIR/df-args")" = '-P /System/Volumes/Data' ]
  else
    [ "$(cat "$MEISTER_DIR/df-args")" = '-P /' ]
  fi
}
