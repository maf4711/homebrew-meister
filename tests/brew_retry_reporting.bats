#!/usr/bin/env bats

setup() {
  MEISTER_DIR="$BATS_TEST_TMPDIR/meister"
  mkdir -p "$MEISTER_DIR"
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
