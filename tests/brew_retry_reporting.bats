#!/usr/bin/env bats

setup() {
  MEISTER_DIR="$BATS_TEST_TMPDIR/meister"
  mkdir -p "$MEISTER_DIR"
  : > "$MEISTER_DIR/report"
  DRY_RUN=false
  RUN_PROFILE=auto
  BREW_CASK_SKIP=""
  log() { printf '%s %s\n' "$1" "$2"; }
  report_add() { printf '%s %s\n' "$1" "$2" >> "$MEISTER_DIR/report"; }
  command_exists() { return 1; }
  ensure_brew() { :; }
  ensure_brew_quiet() { :; }
  ensure_sudo() { :; }
  ai_brew_metadata_current() { return 0; }
  run_or_dry() { "$@"; }
  run_verbose() { "$@"; }
  source "$BATS_TEST_DIRNAME/../lib/core/brew_upgrade.sh"
  for fn in brew_upgrade_each module_homebrew autofix_known_issues; do
    eval "$(awk -v name="$fn" '$0==name"() {" {on=1} on {print} on && /^}$/ {exit}' "$BATS_TEST_DIRNAME/../MeisterAI.sh")"
  done
  brew() {
    printf '%s\n' "$*" >> "$MEISTER_DIR/brew-calls"
    case "$*" in
      --version) echo 'Homebrew fixture' ;;
      'outdated --cask'*)
        if [ "${FAIL_POST_PROBE:-false}" = true ] && [ -f "$MEISTER_DIR/probed" ]; then return 2; fi
        touch "$MEISTER_DIR/probed"
        echo libreoffice ;;
      doctor) echo 'Your system is ready to brew.' ;;
    esac
    return 0
  }
  run_verbose_live() {
    RUN_VERBOSE_OUT=$(mktemp)
    printf 'Error: libreoffice: duplicate application blocks upgrade\n' > "$RUN_VERBOSE_OUT"
    return 1
  }
}

@test "failed package update is reported and its evidence survives temporary cleanup" {
  run brew_upgrade_each cask 180 libreoffice
  [ "$status" = 1 ]
  grep -q 'WARN.*libreoffice.*failed' "$MEISTER_DIR/report"
  evidence=$(find "$MEISTER_DIR/update-failures" -type f)
  [ -n "$evidence" ]
  grep -q 'duplicate application blocks upgrade' "$evidence"
  python3 - "$evidence" <<'PY'
import os,stat,sys
assert stat.S_IMODE(os.stat(sys.argv[1]).st_mode)==0o600
PY
}

@test "cask failure cannot become a clean report or scrub the retry download" {
  run module_homebrew
  [ "$status" = 0 ]
  grep -q 'WARN.*libreoffice.*failed' "$MEISTER_DIR/report"
  grep -q 'WARN.*casks still outdated' "$MEISTER_DIR/report"
  [[ "$output" != *'auto-update apps, normal'* ]]
  ! grep -qE '^cleanup .*\-s|^cleanup .*--prune' "$MEISTER_DIR/brew-calls"
}

@test "autofix preserves current package downloads and preview describes the same policy" {
  AUTOFIX_FIREWALL=false
  AUTOFIX_OLD_BOTTLES=true
  AUTOFIX_ORPHAN_LAUNCHD=false
  command_exists() { [ "$1" = brew ]; }
  git_push_enabled() { return 1; }
  run autofix_known_issues
  [ "$status" = 0 ]
  [ "$(cat "$MEISTER_DIR/brew-calls")" = cleanup ]
  DRY_RUN=true
  run autofix_known_issues
  [ "$status" = 0 ]
  [[ "$output" != *'--prune=all'* && "$output" != *'cleanup -s'* ]]
}

@test "failed post-upgrade query stays visible in the report" {
  FAIL_POST_PROBE=true
  run module_homebrew
  [ "$status" = 0 ]
  grep -q 'WARN Homebrew: cask update verification failed (exit 2)' "$MEISTER_DIR/report"
}

stale_conflict_live() {
  RUN_VERBOSE_OUT=$(mktemp)
  case "$*" in
    *hp-easy-start) printf "\033[31mError:\033[0m hp-easy-start: It seems there is already an App at '%s'.\r\n" "${STALE_APP_PATH:-$T/Caskroom/hp-easy-start/2.16.7,260722/HP Easy Start.app}" ;;
    *antigravity-cli) printf "Error: antigravity-cli: It seems there is already a Command Wrapper at '%s'.\n" "$T/bin/agy" ;;
    *tool-x) printf "Error: tool-x: It seems there is already a Binary at '%s'.\n" "$T/bin/tool-x" ;;
    *) printf "Error: %s: It seems there is already an App at '/nonexistent/%s.app'.\n" "${*##* }" "${*##* }" ;;
  esac > "$RUN_VERBOSE_OUT"
  return 1
}

@test "stale artifact failures trigger one forced reinstall" {
  export T="$BATS_TEST_TMPDIR"
  stale="$T/Caskroom/hp-easy-start/2.16.7,260722/HP Easy Start.app"
  mkdir -p "$stale" "$T/bin/agy"
  brew() {
    printf '%s\n' "$*" >> "$MEISTER_DIR/brew-calls"
    case "$*" in
      --prefix) echo "$T" ;;
      'outdated --cask') printf 'hp-easy-start\nantigravity-cli\ntool-x\n' ;;
      'outdated --cask '*) echo "${*##* }"; return 1 ;;
    esac
    return 0
  }
  run_verbose_live() { stale_conflict_live "$@"; }
  run module_homebrew
  [ "$status" = 0 ]
  [ "$(grep -c '^reinstall --cask --force ' "$MEISTER_DIR/brew-calls")" = 3 ]
  for c in hp-easy-start antigravity-cli tool-x; do
    [ "$(grep -cx "reinstall --cask --force $c" "$MEISTER_DIR/brew-calls")" = 1 ]
  done
  [ ! -e "$stale" ]
  [ -e "$T/bin/agy" ]
}

@test "verified cask repair retracts its failure warning" {
  export T="$BATS_TEST_TMPDIR"
  export STALE_APP_PATH="$T/outside/HP Easy Start.app"
  mkdir -p "$STALE_APP_PATH"
  brew() {
    printf '%s\n' "$*" >> "$MEISTER_DIR/brew-calls"
    case "$*" in
      --prefix) echo "$T" ;;
      'reinstall --cask --force hp-easy-start') touch "$MEISTER_DIR/reinstalled" ;;
      'outdated --cask --greedy'*) [ "${GREEDY_LISTS:-false}" = true ] && echo hp-easy-start ;;
      'outdated --cask hp-easy-start')
        [ -f "$MEISTER_DIR/reinstalled" ] || { echo hp-easy-start; return 1; } ;;
      'outdated --cask') [ -f "$MEISTER_DIR/reinstalled" ] || echo hp-easy-start ;;
    esac
    return 0
  }
  run_verbose_live() { stale_conflict_live "$@"; }
  run module_homebrew
  [ "$status" = 0 ]
  [ "$(grep -cx 'FIX Homebrew: repaired cask hp-easy-start (stale artifact; reinstalled and verified current)' "$MEISTER_DIR/report")" = 1 ]
  [ "$(grep -c 'WARN.*hp-easy-start.*failed' "$MEISTER_DIR/report")" = 0 ]
  [ -d "$STALE_APP_PATH" ]

  # Greedy upgrade needs a greedy readback: auto-updating casks stay listed there.
  : > "$MEISTER_DIR/report"; rm -f "$MEISTER_DIR/reinstalled"
  GREEDY_LISTS=true BREW_UPGRADE_GREEDY=true run brew_upgrade_each cask 180 hp-easy-start
  [ "$status" -ne 0 ]
  [ "$(grep -c '^FIX' "$MEISTER_DIR/report")" = 0 ]
  grep -qx 'outdated --cask --greedy hp-easy-start' "$MEISTER_DIR/brew-calls"

  # Preview never reinstalls or removes anything.
  : > "$MEISTER_DIR/brew-calls"
  capture="$T/capture"
  stale_conflict_live brew upgrade --cask hp-easy-start || cp "$RUN_VERBOSE_OUT" "$capture"
  DRY_RUN=true
  run brew_cask_repair hp-easy-start "$capture" false
  [ "$status" -ne 0 ]
  run module_homebrew
  [ "$(grep -c 'reinstall' "$MEISTER_DIR/brew-calls")" = 0 ]
  [ -d "$STALE_APP_PATH" ]
}

@test "failed cask repair keeps the warning and runs once" {
  export T="$BATS_TEST_TMPDIR"
  brew() {
    printf '%s\n' "$*" >> "$MEISTER_DIR/brew-calls"
    case "$*" in
      --prefix) echo "$T" ;;
      'reinstall --cask --force cask-a') return 1 ;;
      'outdated --cask') printf 'cask-a\ncask-b\n' ;;
      'outdated --cask '*)
        [ "${READBACK_FAILS:-false}" = true ] && return 2
        echo "${*##* }"; return 1 ;;
    esac
    return 0
  }
  run_verbose_live() { stale_conflict_live "$@"; }
  for READBACK_FAILS in false true; do
    : > "$MEISTER_DIR/report"; rm -f "$MEISTER_DIR/brew-calls"
    run module_homebrew
    [ "$status" = 0 ]
    [ "$(grep -cE '^WARN Homebrew: (cask-a|cask-b) upgrade failed' "$MEISTER_DIR/report")" = 2 ]
    [ "$(grep -c '^FIX Homebrew: repaired cask' "$MEISTER_DIR/report")" = 0 ]
    [ "$(grep -cx 'reinstall --cask --force cask-a' "$MEISTER_DIR/brew-calls")" = 1 ]
    [ "$(grep -cx 'reinstall --cask --force cask-b' "$MEISTER_DIR/brew-calls")" = 1 ]
  done
}

@test "upgraded formula with failing post-step is not reported failed" {
  brew() {
    printf '%s\n' "$*" >> "$MEISTER_DIR/brew-calls"
    case "$*" in
      'outdated --formula')
        if [ -f "$MEISTER_DIR/formula-listed" ]; then return "${READBACK_RC:-0}"; fi
        touch "$MEISTER_DIR/formula-listed"
        echo ada-url ;;
    esac
    return 0
  }
  run_verbose_live() {
    RUN_VERBOSE_OUT=$(mktemp)
    printf 'Error: The `brew link` step did not complete successfully\n' > "$RUN_VERBOSE_OUT"
    return 1
  }
  run module_homebrew
  [ "$status" = 0 ]
  [ "$(grep -c 'WARN.*ada-url.*failed' "$MEISTER_DIR/report")" = 0 ]

  : > "$MEISTER_DIR/report"; rm -f "$MEISTER_DIR/formula-listed"
  READBACK_RC=2 run module_homebrew
  [ "$(grep -c 'WARN.*ada-url.*failed' "$MEISTER_DIR/report")" = 1 ]
}
