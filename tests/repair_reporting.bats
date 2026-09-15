#!/usr/bin/env bats

setup() {
  export MEISTER_DIR="$BATS_TEST_TMPDIR/meister"
  mkdir -p "$MEISTER_DIR"
  DRY_RUN=false
  REPORT_FIXED=(); REPORT_SUCCESS=(); REPORT_WARNINGS=(); REPORT_ERRORS=(); REPORT_WOULD_FIX=()
  MODULE_TIMINGS=(); MODULE_LEDGER=()
  VERIFIED_REPAIR_COUNT=0
  SCRIPT_START_TIME=$(date +%s)
  RUN_REPORT_STARTED=true
  RUN_REPORT_SAVED=false
  RUN_STATUS=completed
  log() { :; }
  log_heal_event() { :; }
  ai_heal_emit() { :; }
  command_exists() { return 1; }
  sleep() { :; }
  source "$BATS_TEST_DIRNAME/../lib/core/last_json.sh"
  source "$BATS_TEST_DIRNAME/../lib/core/heal_guards.sh"
  source "$BATS_TEST_DIRNAME/../lib/core/run_lock.sh"
  source "$BATS_TEST_DIRNAME/../lib/core/learned_fixes.sh"
  for fn in report_add known_fix selfheal_preflight run_or_dry compute_score save_history heal_verify_module run_module_safe; do
    eval "$(awk -v name="$fn" '$0==name"() {" {on=1} on {print} on && /^}$/ {exit}' "$BATS_TEST_DIRNAME/../meisterSiri.sh")"
  done
}

@test "preview known repairs never invoke DNS disk brew or sudo mutators" {
  DRY_RUN=true
  sudo() { echo sudo >> "$MEISTER_DIR/mutators"; }
  brew() { echo brew >> "$MEISTER_DIR/mutators"; }
  rm() { echo rm >> "$MEISTER_DIR/mutators"; }
  for failure in 'Could not resolve host' 'No space left on device' 'Error: Your CLT'; do
    known_fix Test "$failure" || true
  done
  [ ! -e "$MEISTER_DIR/mutators" ]
  [ "${#REPORT_WOULD_FIX[@]}" = 3 ]
}

@test "preview DNS and critical-disk preflight never executes mutators" {
  DRY_RUN=true
  DISK_CRITICAL_THRESHOLD=95
  DISK_USAGE_THRESHOLD=90
  dscacheutil() { return 1; }
  sudo() { echo sudo >> "$MEISTER_DIR/mutators"; }
  rm() { echo rm >> "$MEISTER_DIR/mutators"; }
  df() { printf 'Filesystem Size Used Avail Use%% Mounted\ndisk 100 99 1 99%% /\n'; }
  selfheal_preflight
  [ ! -e "$MEISTER_DIR/mutators" ]
  [ "${#REPORT_FIXED[@]}" = 0 ]
  [ "${#REPORT_WOULD_FIX[@]}" = 2 ]
}

@test "verify counts only completed real module retests and records failed context" {
  AI_HEAL_EXECUTE=true
  MEISTER_OS_VERSION=testOS
  heal_context_begin Module 'test failure'
  healthy_module() { return 0; }
  unhealthy_module() { return 1; }
  heal_verify_module Module healthy_module ai-heal 'killall Dock'
  [ "$VERIFIED_REPAIR_COUNT" = 1 ]
  [ "$(learned_fix_lookup Module)" = 'killall Dock' ]
  heal_verify_module Module unhealthy_module ai-heal 'killall Dock' || true
  [ "$(cut -f5-6 "$MEISTER_DIR/learned_fixes.v2.tsv")" = $'1\t1' ]
  DRY_RUN=true
  healthy_module() { echo invalid > "$MEISTER_DIR/retest"; }
  heal_verify_module Module healthy_module ai-heal 'killall Dock' || true
  [ ! -f "$MEISTER_DIR/retest" ]
  [ "$VERIFIED_REPAIR_COUNT" = 1 ]
}

@test "preview and interrupted archives never poison completed real history" {
  DRY_RUN=false
  RUN_ID=real-run
  save_history
  cp "$MEISTER_DIR/history.log" "$MEISTER_DIR/before"
  DRY_RUN=true
  RUN_REPORT_SAVED=false
  RUN_ID=preview-run
  save_history
  DRY_RUN=false
  RUN_REPORT_SAVED=false
  RUN_STATUS=interrupted
  RUN_ID=interrupted-run
  save_history
  cmp "$MEISTER_DIR/history.log" "$MEISTER_DIR/before"
  [ -f "$MEISTER_DIR/runs/real-run.json" ]
  [ -f "$MEISTER_DIR/runs/preview-run.json" ]
  [ -f "$MEISTER_DIR/runs/interrupted-run.json" ]
  save_history
  [ "$(wc -l < "$MEISTER_DIR/history.log" | tr -d ' ')" = 1 ]
}

teardown() { unset -f rm; }

@test "known repair changing failure A to B learns AI success only for B" {
  LOGFILE="$MEISTER_DIR/retry.log"
  : > "$LOGFILE"
  LOG_CAPTURE_LINES=50
  AI_HEAL_EXECUTE=true
  FM_ENABLED=true
  MEISTER_OS_VERSION=testOS
  section_header() { :; }; module_timer_start() { :; }; module_timer_stop() { :; }; ledger_add() { :; }
  log() { printf '%s\n' "$*" >> "$LOGFILE"; }
  stage=A
  changing_module() { [ "$stage" = fixed ] && return 0; printf 'Failure %s\n' "$stage" >> "$LOGFILE"; return 1; }
  known_fix() { stage=B; return 0; }
  ai_usage_record() { :; }
  ai_heal() {
    [ "$2" = 'Exit: 1. Failure B' ] || return 1
    AI_LAST_CMD='killall Dock'
    stage=fixed
  }
  run_module_safe Changing changing_module || { echo "unexpected unresolved failure"; return 1; }
  [ "$VERIFIED_REPAIR_COUNT" = 1 ]
  heal_context_begin Changing 'Exit: 1. Failure B'
  [ "$(learned_fix_lookup Changing)" = 'killall Dock' ]
  heal_context_begin Changing 'Exit: 1. Failure A'
  run learned_fix_lookup Changing
  [ "$status" -ne 0 ]
}

@test "AI retry failure evidence stays bound to A while successful next candidate binds to B" {
  LOGFILE="$MEISTER_DIR/retry.log"
  : > "$LOGFILE"
  LOG_CAPTURE_LINES=50
  AI_HEAL_EXECUTE=true
  FM_ENABLED=true
  MEISTER_OS_VERSION=testOS
  section_header() { :; }; module_timer_start() { :; }; module_timer_stop() { :; }; ledger_add() { :; }
  log() { printf '%s\n' "$*" >> "$LOGFILE"; }
  stage=A
  changing_module() { [ "$stage" = fixed ] && return 0; printf 'Failure %s\n' "$stage" >> "$LOGFILE"; return 1; }
  known_fix() { return 1; }
  ai_usage_record() { :; }
  ai_heal() {
    if [ "$stage" = A ]; then AI_LAST_CMD='killall Dock'; stage=B
    else [ "$2" = 'Exit: 1. Failure B' ] || return 1; AI_LAST_CMD='killall Finder'; stage=fixed; fi
  }
  run_module_safe Changing changing_module || { echo "unexpected unresolved failure"; return 1; }
  fp_a=$(heal_failure_fingerprint 'Exit: 1. Failure A')
  awk -F'\t' -v f="$fp_a" '$2==f && $4=="killall Dock" {if ($5==0 && $6==1) ok=1} END {exit !ok}' "$MEISTER_DIR/learned_fixes.v2.tsv"
  heal_context_begin Changing 'Exit: 1. Failure B'
  [ "$(learned_fix_lookup Changing)" = 'killall Finder' ]
  heal_context_begin Changing 'Exit: 1. Failure A'
  run learned_fix_lookup Changing
  [ "$status" -ne 0 ]
}

@test "nested retest helpers cannot rebind the candidate's recorded context" {
  AI_HEAL_EXECUTE=true
  MEISTER_OS_VERSION=testOS
  heal_context_begin Outer 'original failure'
  fp_original=$HEAL_FAILURE_FINGERPRINT
  nested_module() { heal_context_begin Nested 'unrelated nested context'; return 0; }
  heal_verify_module Outer nested_module ai-heal 'killall Dock'
  [ "$HEAL_CONTEXT_MODULE" = Outer ]
  [ "$HEAL_FAILURE_FINGERPRINT" = "$fp_original" ]
  [ "$(learned_fix_lookup Outer)" = 'killall Dock' ]
}
