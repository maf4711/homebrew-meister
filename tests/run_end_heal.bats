#!/usr/bin/env bats
# Run-end heal pass (lib/core/run_end_heal.sh). brew is never called: the
# registered repairer brew_cask_repair is replaced by a stub that logs its args.

setup() {
  export MEISTER_DIR="$BATS_TEST_TMPDIR/meister"
  mkdir -p "$MEISTER_DIR"
  LOGFILE="$MEISTER_DIR/meister.log"
  HEAL_LOG="$MEISTER_DIR/heal.log"
  printf '%s\n' '2026-11-15 15:46:02 - INFO - MeisterAI v6.44 started (Sun Nov 15 15:46:02 CET 2026)' > "$LOGFILE"
  log() { local level="$1"; shift; printf '[%s] %s\n' "$level" "$*"; }
  # Same line format as log_heal_event in MeisterAI.sh.
  log_heal_event() { printf '%s | %s | %s | %s | %s\n' now "$1" "$2" "$3" "${4:-}" >> "$HEAL_LOG"; }
  source "$BATS_TEST_DIRNAME/../lib/core/brew_upgrade.sh"
  source "$BATS_TEST_DIRNAME/../lib/core/run_end_heal.sh"
  brew() { echo "real brew must not run: $*" >&2; return 99; }
  brew_cask_repair() {
    printf '%s\n' "$*" >> "$MEISTER_DIR/stub-calls"
    printf 'repair %s\n' "$1" >> "$MEISTER_DIR/order"
    return "${STUB_RC:-0}"
  }
  DRY_RUN=false
  INTERRUPTED=false
  RUN_STATUS=completed
  RUN_END_HEAL=true
  REPORT_WARNINGS=()
  REPORT_ERRORS=()
  REPORT_FIXED=()
  VERIFIED_REPAIR_COUNT=0
  # Evidence captures live where brew_record_upgrade_failure writes them.
  D="$MEISTER_DIR/update-failures"
  mkdir -p "$D"
}

stale_capture() {
  printf "==> Upgrading %s\nError: %s: It seems there is already an App at '/Applications/%s.app'.\n" \
    "$1" "$1" "$1" > "$2"
}

stub_calls() {
  if [ -f "$MEISTER_DIR/stub-calls" ]; then wc -l < "$MEISTER_DIR/stub-calls" | tr -d ' '; else echo 0; fi
}

@test "finding with a repairer gets exactly one attempt" {
  stale_capture hp-easy-start "$D/cask-hp-easy-start.AbC"
  # Both carry a stale-artifact conflict, so only the timeout rule and the
  # cask- evidence rule can be what rejects them.
  stale_capture docker-desktop "$D/cask-docker-desktop.XyZ"
  printf 'Error: SIGTERM\n' >> "$D/cask-docker-desktop.XyZ"
  stale_capture ada-url "$D/formula-ada-url.WL6"
  findings=(
    "Homebrew: hp-easy-start upgrade failed (exit 1); log: $D/cask-hp-easy-start.AbC"
    "Homebrew: hp-easy-start upgrade failed (exit 1); log: $D/cask-hp-easy-start.AbC"
    "Homebrew: docker-desktop upgrade failed (exit 124); log: $D/cask-docker-desktop.XyZ"
    "Homebrew: ada-url upgrade failed (exit 1); log: $D/formula-ada-url.WL6"
    "6 new entries in Documents root"
  )
  REPORT_WARNINGS=("${findings[@]}")
  run_end_heal > "$D/out"
  [ "$(stub_calls)" -eq 1 ]
  [ "$(cat "$MEISTER_DIR/stub-calls")" = "hp-easy-start $D/cask-hp-easy-start.AbC true" ]
  for f in "Homebrew: docker-desktop upgrade failed" "Homebrew: ada-url upgrade failed" "6 new entries in Documents root"; do
    [ "$(grep -cF -- "Run-end heal: no automatic repair — $f" "$D/out")" -eq 1 ]
  done
  [ "$RUN_END_HEAL_UNREPAIRABLE" -eq 3 ]
  [ "$RUN_END_HEAL_ATTEMPTED" -eq 1 ]

  rm -f "$MEISTER_DIR/stub-calls"
  unset -f brew_cask_repair
  REPORT_WARNINGS=("${findings[@]}")
  REPORT_FIXED=()
  run_end_heal > "$D/out2"
  [ "$(stub_calls)" -eq 0 ]
  [ "$RUN_END_HEAL_UNREPAIRABLE" -eq 5 ]
  [ "$RUN_END_HEAL_ATTEMPTED" -eq 0 ]
  [ "${#REPORT_WARNINGS[@]}" -eq 5 ]
}

@test "verified repair retracts the finding and counts once" {
  stale_capture hp-easy-start "$D/cask-hp-easy-start.AbC"
  MODULE_LEDGER=('WARN|Homebrew|42' 'OK|Cleanup|3')
  before=$(printf '%s\n' "${MODULE_LEDGER[@]}")
  REPORT_WARNINGS=(
    "Homebrew: hp-easy-start upgrade failed (exit 1); log: $D/cask-hp-easy-start.AbC"
    "6 new entries in Documents root"
  )
  run_end_heal > "$D/out"
  [ "$(printf '%s\n' "${REPORT_WARNINGS[@]}" | grep -c hp-easy-start)" -eq 0 ]
  [ "${#REPORT_WARNINGS[@]}" -eq 1 ]
  [ "${#REPORT_FIXED[@]}" -eq 1 ]
  [ "${REPORT_FIXED[0]}" = "Run-end heal: verified — Homebrew: hp-easy-start upgrade failed" ]
  [ "$(grep -cxF '[FIX] Run-end heal: verified — Homebrew: hp-easy-start upgrade failed' "$D/out")" -eq 1 ]
  [ "$VERIFIED_REPAIR_COUNT" -eq 1 ]
  [ "$RUN_END_HEAL_VERIFIED" -eq 1 ]
  [ "$RUN_END_HEAL_ATTEMPTED" -eq 1 ]
  [ "$(printf '%s\n' "${MODULE_LEDGER[@]}")" = "$before" ]
  grep -q ' | run-end | hp-easy-start | verified | ' "$HEAL_LOG"
}

@test "unresolved repair keeps the finding and suspends after two runs" {
  STUB_RC=1
  unresolved='Run-end heal: unresolved — Homebrew: hp-easy-start upgrade failed'
  one_run() {
    stale_capture hp-easy-start "$D/cask-hp-easy-start.R$1"
    # The exit code varies between runs; the finding stays the same subject.
    REPORT_WARNINGS=("Homebrew: hp-easy-start upgrade failed (exit $1); log: $D/cask-hp-easy-start.R$1")
    REPORT_FIXED=()
    run_end_heal > "$D/out$1"
  }
  for i in 1 2; do
    one_run "$i"
    [ "$(stub_calls)" -eq "$i" ]
    [ "$(printf '%s\n' "${REPORT_WARNINGS[@]}" | grep -cxF -- "$unresolved")" -eq 1 ]
    [ "$(printf '%s\n' "${REPORT_WARNINGS[@]}" | grep -c "cask-hp-easy-start.R$i")" -eq 1 ]
    [ "${#REPORT_FIXED[@]}" -eq 0 ]
    [ "$(grep -c '^\[FIX\]' "$D/out$i")" -eq 0 ]
    [ "$RUN_END_HEAL_UNRESOLVED" -eq 1 ]
    [ "$VERIFIED_REPAIR_COUNT" -eq 0 ]
  done
  one_run 3
  [ "$(stub_calls)" -eq 2 ]
  [ "$RUN_END_HEAL_SKIPPED" -eq 1 ]
  [ "$RUN_END_HEAL_ATTEMPTED" -eq 0 ]
  [ "${#REPORT_WARNINGS[@]}" -eq 1 ]

  old=$(( $(date +%s) - 8 * 86400 ))
  awk -F'\t' -v OFS='\t' -v t="$old" '{ $3 = t; print }' "$MEISTER_DIR/run_end_heal.tsv" > "$D/state"
  mv "$D/state" "$MEISTER_DIR/run_end_heal.tsv"
  one_run 4
  [ "$(stub_calls)" -eq 3 ]
  [ "$RUN_END_HEAL_ATTEMPTED" -eq 1 ]
}

@test "budget, dry run, opt-out and partial runs stop attempts" {
  four() {
    REPORT_WARNINGS=()
    REPORT_FIXED=()
    local c
    for c in alpha beta gamma delta; do
      stale_capture "$c" "$D/cask-$c.Q1"
      REPORT_WARNINGS+=("Homebrew: $c upgrade failed (exit 1); log: $D/cask-$c.Q1")
    done
  }
  four
  RUN_END_HEAL_MAX_ATTEMPTS=2 run_end_heal > "$D/out"
  [ "$(stub_calls)" -eq 2 ]
  [ "$RUN_END_HEAL_ATTEMPTED" -eq 2 ]
  [ "$RUN_END_HEAL_SKIPPED" -eq 2 ]

  rm -f "$MEISTER_DIR/stub-calls"
  four
  RUN_END_HEAL_MAX_SEC=0 run_end_heal > "$D/out"
  [ "$(stub_calls)" -eq 0 ]
  [ "$RUN_END_HEAL_SKIPPED" -eq 4 ]

  four
  DRY_RUN=true run_end_heal > "$D/out"
  [ "$(stub_calls)" -eq 0 ]
  [ "$RUN_END_HEAL_ATTEMPTED" -eq 0 ]

  four
  RUN_END_HEAL=false run_end_heal > "$D/out"
  [ "$(stub_calls)" -eq 0 ]

  four
  RUN_STATUS=partial run_end_heal > "$D/out"
  [ "$(stub_calls)" -eq 0 ]

  four
  INTERRUPTED=true run_end_heal > "$D/out"
  [ "$(stub_calls)" -eq 0 ]
  [ "${#REPORT_WARNINGS[@]}" -eq 4 ]
}

@test "review counts report findings and log lines of this run" {
  cat > "$LOGFILE" <<'LOG'
2026-11-14 10:00:00 - INFO - MeisterAI v6.43 started (Sat Nov 14 10:00:00 CET 2026)
2026-11-14 10:00:01 - WARN - old warning
2026-11-14 10:00:02 - ERROR - old error
2026-11-15 15:46:02 - INFO - MeisterAI v6.44 started (Sun Nov 15 15:46:02 CET 2026)
2026-11-15 15:46:03 - WARN - Homebrew: hp-easy-start upgrade failed
2026-11-15 15:46:04 - STEP -    WARN inside a step line is not a warning
2026-11-15 15:46:05 - WARN - Slow module: Homebrew took 301s
2026-11-15 15:47:00 - ERROR - Spotlight-Index with errors
2026-11-15 15:48:00 - INFO - Cleanup done
2026-11-15 15:49:00 - WARN - Skill-Suite: 30 uncommitted changes
LOG
  REPORT_WARNINGS=("6 new entries in Documents root" "Skill-Suite: 30 uncommitted changes")
  run_end_heal > "$D/out"
  [ "$(grep -c 'Run-end review: ' "$D/out")" -eq 1 ]
  grep -qxF '[INFO] Run-end review: 2 report findings, 4 WARN/ERROR log lines this run' "$D/out"

  REPORT_WARNINGS=()
  run_end_heal > "$D/out"
  grep -qF 'Run-end review: 0 report findings, 4 WARN/ERROR log lines this run' "$D/out"
  [ "$RUN_END_HEAL_ATTEMPTED" -eq 0 ]

  stale_capture hp-easy-start "$D/cask-hp-easy-start.AbC"
  REPORT_WARNINGS=("Homebrew: hp-easy-start upgrade failed (exit 1); log: $D/cask-hp-easy-start.AbC")
  LOGFILE="$D/absent/meister.log"
  rc=0
  run_end_heal > "$D/out" || rc=$?
  [ "$rc" -eq 0 ]
  [ "$(grep -c '^\[WARN\]' "$D/out")" -eq 1 ]
  [ "$(stub_calls)" -eq 0 ]
  [ "$RUN_END_HEAL_ATTEMPTED" -eq 0 ]
  [ "$RUN_END_HEAL_VERIFIED" -eq 0 ]
  [ "$RUN_END_HEAL_UNRESOLVED" -eq 0 ]
  [ "$RUN_END_HEAL_SKIPPED" -eq 0 ]
  [ "$RUN_END_HEAL_UNREPAIRABLE" -eq 0 ]
}

@test "state rows with leading-zero counts or future timestamps do not stop the pass" {
  STUB_RC=1
  stale_capture hp-easy-start "$D/cask-hp-easy-start.AbC"
  again() {
    REPORT_WARNINGS=("Homebrew: hp-easy-start upgrade failed (exit 1); log: $D/cask-hp-easy-start.AbC")
    run_end_heal > "$D/out"
  }
  set_row() {
    awk -F'\t' -v OFS='\t' -v n="$1" -v t="$2" '{ $2 = n; $3 = t; print }' "$MEISTER_DIR/run_end_heal.tsv" > "$D/state"
    mv "$D/state" "$MEISTER_DIR/run_end_heal.tsv"
  }
  again
  [ "$(stub_calls)" -eq 1 ]
  set_row 08 $(( $(date +%s) - 8 * 86400 ))
  again
  [ "$(stub_calls)" -eq 2 ]
  [ "$RUN_END_HEAL_UNRESOLVED" -eq 1 ]
  [ "$(cut -f2 "$MEISTER_DIR/run_end_heal.tsv")" = 9 ]
  set_row 5 99999999999
  again
  [ "$(stub_calls)" -eq 3 ]
  [ "$RUN_END_HEAL_ATTEMPTED" -eq 1 ]
}

@test "sudo is prepared once before each attempted run-end repair" {
  ensure_sudo() { printf 'sudo %s\n' "$*" >> "$MEISTER_DIR/order"; return 1; }
  two() {
    REPORT_WARNINGS=()
    REPORT_FIXED=()
    local c
    for c in alpha beta; do
      stale_capture "$c" "$D/cask-$c.S1"
      REPORT_WARNINGS+=("Homebrew: $c upgrade failed (exit 1); log: $D/cask-$c.S1")
    done
    REPORT_WARNINGS+=("Homebrew: alpha upgrade failed (exit 1); log: $D/cask-alpha.S1")
  }
  two
  run_end_heal > "$D/out"
  # ensure_sudo failing does not stop the attempt (same as the module call site)
  [ "$(cat "$MEISTER_DIR/order")" = "$(printf '%s\n' 'sudo run-end cask reinstall: alpha' 'repair alpha' 'sudo run-end cask reinstall: beta' 'repair beta')" ]

  for gate in DRY_RUN=true RUN_END_HEAL=false RUN_STATUS=partial INTERRUPTED=true RUN_END_HEAL_MAX_SEC=0 RUN_END_HEAL_MAX_ATTEMPTS=0; do
    rm -f "$MEISTER_DIR/order"
    two
    env_name=${gate%%=*}
    eval "local $gate"
    run_end_heal > "$D/out"
    eval "unset $env_name"
    DRY_RUN=false; RUN_END_HEAL=true; RUN_STATUS=completed; INTERRUPTED=false
    [ ! -e "$MEISTER_DIR/order" ]
  done

  rm -f "$MEISTER_DIR/order"
  two
  RUN_END_HEAL_MAX_ATTEMPTS=1 run_end_heal > "$D/out"
  [ "$(grep -c '^sudo ' "$MEISTER_DIR/order")" -eq 1 ]
}

@test "only regular cask captures inside update-failures are repair evidence" {
  out_dir="$BATS_TEST_TMPDIR/elsewhere"
  mkdir -p "$out_dir" "$D/cask-dir"
  stale_capture link "$out_dir/target"
  ln -s "$out_dir/target" "$D/cask-link.4"
  stale_capture outside "$out_dir/cask-outside.7"
  stale_capture trav "$MEISTER_DIR/cask-trav.1"
  REPORT_WARNINGS=(
    "Homebrew: link upgrade failed (exit 1); log: $D/cask-link.4"
    "Homebrew: outside upgrade failed (exit 1); log: $out_dir/cask-outside.7"
    "Homebrew: trav upgrade failed (exit 1); log: $D/cask-dir/../../cask-trav.1"
  )
  run_end_heal > "$D/../out"
  [ "$(stub_calls)" -eq 0 ]
  [ "$RUN_END_HEAL_UNREPAIRABLE" -eq 3 ]
  for c in link outside trav; do
    [ "$(grep -cF -- "Run-end heal: no automatic repair — Homebrew: $c upgrade failed" "$D/../out")" -eq 1 ]
  done
  [ "$(run_end_heal_repairer "Homebrew: link upgrade failed (exit 1); log: $D/cask-link.4")" = "" ]
}

@test "suspension keys keep the digits of the cask token" {
  STUB_RC=1
  for i in 1 2; do
    stale_capture temurin@17 "$D/cask-temurin@17.T$i"
    REPORT_WARNINGS=("Homebrew: temurin@17 upgrade failed (exit $i); log: $D/cask-temurin@17.T$i")
    run_end_heal > "$D/../out"
  done
  [ "$(stub_calls)" -eq 2 ]
  stale_capture temurin@17 "$D/cask-temurin@17.T3"
  stale_capture temurin@21 "$D/cask-temurin@21.T3"
  REPORT_WARNINGS=(
    "Homebrew: temurin@17 upgrade failed (exit 1); log: $D/cask-temurin@17.T3"
    "Homebrew: temurin@21 upgrade failed (exit 1); log: $D/cask-temurin@21.T3"
  )
  run_end_heal > "$D/../out"
  [ "$(stub_calls)" -eq 3 ]
  [[ "$(tail -1 "$MEISTER_DIR/stub-calls")" == "temurin@21 "* ]]
  [ "$RUN_END_HEAL_SKIPPED" -eq 1 ]
  [ "$RUN_END_HEAL_ATTEMPTED" -eq 1 ]
  [ "$(wc -l < "$MEISTER_DIR/run_end_heal.tsv")" -eq 2 ]
  [ "$(cut -f1 "$MEISTER_DIR/run_end_heal.tsv" | sort -u | wc -l)" -eq 2 ]
}

@test "the report prints the run-end heal summary only after the pass ran" {
  eval "$(awk '$0=="print_report() {" {on=1} on {print} on && /^}$/ {exit}' "$BATS_TEST_DIRNAME/../MeisterAI.sh")"
  RED='' GREEN='' YELLOW='' BLUE='' CYAN='' NC='' AIHEAL_FG=''
  SCRIPT_START_TIME=$(date +%s)
  MAINT_SCORE=90
  MODULE_LEDGER=()
  REPORT_SUCCESS=()
  REPORT_WOULD_FIX=()
  REPORT_AI_DIAGNOSES=()
  HEAL_COUNT=0
  AI_CALLS_THIS_RUN=0
  AI_USAGE_LOG="$MEISTER_DIR/absent-ai-usage.log"
  MEISTER_CONFIG="$MEISTER_DIR/config"
  REPORT_WARNINGS=("6 new entries in Documents root")
  summary='Run-end heal: 1 attempted, 1 verified, 0 unresolved, 0 skipped, 1 without automatic repair'

  unset RUN_END_HEAL_ATTEMPTED RUN_END_HEAL_VERIFIED RUN_END_HEAL_UNRESOLVED RUN_END_HEAL_SKIPPED RUN_END_HEAL_UNREPAIRABLE
  print_report > "$D/../report-none"
  [ "$(grep -c 'Run-end heal:' "$D/../report-none")" -eq 0 ]

  RUN_END_HEAL_ATTEMPTED=1 RUN_END_HEAL_VERIFIED=1 RUN_END_HEAL_UNRESOLVED=0
  RUN_END_HEAL_SKIPPED=0 RUN_END_HEAL_UNREPAIRABLE=1
  print_report > "$D/../report"
  [ "$(grep -cxF -- "$summary" "$D/../report")" -eq 1 ]
}
