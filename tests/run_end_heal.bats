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
  D="$BATS_TEST_TMPDIR"
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
  printf '==> Upgrading docker-desktop\nError: SIGTERM\n' > "$D/cask-docker-desktop.XyZ"
  printf '==> Upgrading ada-url\nError: ada-url: failed to build\n' > "$D/formula-ada-url.WL6"
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
  [[ "$(cat "$MEISTER_DIR/stub-calls")" == "hp-easy-start "* ]]
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
    REPORT_WARNINGS=("Homebrew: hp-easy-start upgrade failed (exit 1); log: $D/cask-hp-easy-start.R$1")
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
