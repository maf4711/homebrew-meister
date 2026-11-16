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
        if [ -f "$MEISTER_DIR/formula-listed" ]; then
          [ -n "${STILL_LISTED:-}" ] && echo "$STILL_LISTED"
          return "${READBACK_RC:-0}"
        fi
        touch "$MEISTER_DIR/formula-listed"
        echo "${FORMULA:-ada-url}" ;;
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

  # Tap-qualified formula still listed by a successful readback keeps its warning.
  : > "$MEISTER_DIR/report"; rm -f "$MEISTER_DIR/formula-listed"
  FORMULA=example/tap/tool STILL_LISTED=example/tap/tool run module_homebrew
  [ "$(grep -c 'WARN Homebrew: example/tap/tool upgrade failed' "$MEISTER_DIR/report")" = 1 ]
}

@test "stale artifact removal never reaches outside the cask folder" {
  export T="$BATS_TEST_TMPDIR"
  brew() {
    printf '%s\n' "$*" >> "$MEISTER_DIR/brew-calls"
    case "$*" in --prefix) echo "$T" ;; esac
    return 0
  }
  fresh() {
    rm -rf "$T/Caskroom" "$T/victim"; : > "$MEISTER_DIR/brew-calls"
    mkdir -p "$T/Caskroom" "$T/victim"; echo keep > "$T/victim/keep"
  }
  repair_with_path() {
    printf "\033[31mError:\033[0m c: It seems there is already an App at '%s'.\r\n" "$1" > "$T/capture"
    run brew_cask_repair c "$T/capture" false
    [ "$(grep -cx 'reinstall --cask --force c' "$MEISTER_DIR/brew-calls")" = 1 ]
  }
  # 1. symlink leaf named with a trailing slash
  fresh; mkdir -p "$T/Caskroom/c/1.0"; ln -s "$T/victim" "$T/Caskroom/c/1.0/App.app"
  repair_with_path "$T/Caskroom/c/1.0/App.app/"
  [ -f "$T/victim/keep" ]
  # 2. symlinked intermediate directory
  fresh; mkdir -p "$T/Caskroom/c"; ln -s "$T/victim" "$T/Caskroom/c/1.0"
  repair_with_path "$T/Caskroom/c/1.0/keep"
  [ -f "$T/victim/keep" ]
  # 3. Caskroom/<cask> itself a symlink
  fresh; ln -s "$T/victim" "$T/Caskroom/c"
  repair_with_path "$T/Caskroom/c/keep"
  [ -f "$T/victim/keep" ]
  # 4. trailing slashes on the cask folder itself
  fresh; mkdir -p "$T/Caskroom/c/2.0"; echo keep > "$T/Caskroom/c/2.0/keep"
  repair_with_path "$T/Caskroom/c//"
  [ -f "$T/Caskroom/c/2.0/keep" ]
  # 5. a quote inside the path must not truncate it onto another path
  fresh; mkdir -p "$T/Caskroom/c/1.0/Bob's.app"; echo keep > "$T/Caskroom/c/1.0/Bob"
  repair_with_path "$T/Caskroom/c/1.0/Bob's.app"
  [ -f "$T/Caskroom/c/1.0/Bob" ]
  [ ! -e "$T/Caskroom/c/1.0/Bob's.app" ]
}

@test "missing app source heal keeps its own summary" {
  run_verbose_live() {
    RUN_VERBOSE_OUT=$(mktemp)
    printf "libreoffice: It seems the App source '/Applications/LibreOffice.app' is not there.\n" > "$RUN_VERBOSE_OUT"
    return 1
  }
  run module_homebrew
  [ "$status" = 0 ]
  [ "$(grep -cx 'FIX Auto-healed 1 broken cask(s)' "$MEISTER_DIR/report")" = 1 ]
  [ "$(grep -c 'repaired cask' "$MEISTER_DIR/report")" = 0 ]
  [ "$(grep -cx 'reinstall --cask --force libreoffice' "$MEISTER_DIR/brew-calls")" = 1 ]
}

@test "tap-qualified cask with a stale artifact is repaired" {
  brew() {
    printf '%s\n' "$*" >> "$MEISTER_DIR/brew-calls"
    return 0
  }
  run_verbose_live() {
    RUN_VERBOSE_OUT=$(mktemp)
    printf "Error: foo: It seems there is already an App at '/nonexistent/Foo.app'.\n" > "$RUN_VERBOSE_OUT"
    return 1
  }
  run brew_upgrade_each cask 180 user/tap/foo
  [ "$status" = 0 ]
  [ "$(grep -c '^reinstall --cask --force' "$MEISTER_DIR/brew-calls")" = 1 ]
  grep -qx 'FIX Homebrew: repaired cask user/tap/foo (stale artifact; reinstalled and verified current)' "$MEISTER_DIR/report"
  [ "$(grep -c 'WARN' "$MEISTER_DIR/report")" = 0 ]
}

@test "missing app source heal skips a cask already force-reinstalled" {
  export T="$BATS_TEST_TMPDIR"
  mkdir -p "$T/Caskroom/foo/1.0/Foo.app"
  brew() {
    printf '%s\n' "$*" >> "$MEISTER_DIR/brew-calls"
    case "$*" in
      --prefix) echo "$T" ;;
      'outdated --cask') echo foo ;;
    esac
    return 0
  }
  run_verbose_live() {
    RUN_VERBOSE_OUT=$(mktemp)
    printf "Error: foo: It seems there is already an App at '%s'.\nfoo: It seems the App source '%s' is not there.\n" \
      "$T/Caskroom/foo/1.0/Foo.app" "$T/Caskroom/foo/1.0/Foo.app" > "$RUN_VERBOSE_OUT"
    return 1
  }
  run module_homebrew
  [ "$status" = 0 ]
  [ "$(grep -cx 'reinstall --cask --force foo' "$MEISTER_DIR/brew-calls")" = 1 ]
}

# A self-updated CLI replaces its Homebrew link with a real file; Homebrew then
# refuses every upgrade and every forced reinstall until that file is gone.
declared_bin_fixture() {
  export T="$BATS_TEST_TMPDIR"
  mkdir -p "$T/bin" "$T/Caskroom/c/2.0" "$T/elsewhere"
  echo self-updated > "$T/bin/tool"
  printf "Error: c: It seems there is already a Command Wrapper at '%s'.\n" "${1:-$T/bin/tool}" > "$T/capture"
  brew() {
    printf '%s\n' "$*" >> "$MEISTER_DIR/brew-calls"
    case "$*" in
      --prefix) echo "$T" ;;
      'info --cask --json=v2 c') printf '{"casks":[{"artifacts":[{"command_wrapper":["tool"],"target":"%s"}]}]}\n' "${DECLARED:-$T/bin/tool}" ;;
      'reinstall --cask --force c')
        [ "${REINSTALL_OK:-true}" = true ] || { echo 'Error: c: download failed'; return 1; }
        [ -e "$T/bin/tool" ] && { echo "Error: c: It seems there is already a Command Wrapper at '$T/bin/tool'."; return 1; }
        ln -s "$T/Caskroom/c/2.0" "$T/bin/tool" ;;
    esac
    return 0
  }
}

@test "real file at a cask-declared bin target is moved aside and the reinstall verified" {
  declared_bin_fixture
  run brew_cask_repair c "$T/capture" false
  [ "$status" = 0 ]
  [ -L "$T/bin/tool" ]
  [ -z "$(find "$MEISTER_DIR/backups" -type f 2>/dev/null)" ]
}

@test "failed reinstall puts the parked file back and names the Homebrew error" {
  declared_bin_fixture
  REINSTALL_OK=false
  run brew_cask_repair c "$T/capture" false
  [ "$status" = 1 ]
  [ "$(cat "$T/bin/tool")" = self-updated ]
  [ ! -L "$T/bin/tool" ]
  [[ "$output" == *'forced reinstall failed — Error: c: download failed'* ]]
}

@test "bin conflict is left alone unless the cask declares exactly that real file" {
  declared_bin_fixture
  DECLARED="$T/bin/other" run brew_cask_repair c "$T/capture" false
  [ "$(cat "$T/bin/tool")" = self-updated ]
  BREW_CASK_REPAIRED=""
  echo keep > "$T/elsewhere/tool"
  declared_bin_fixture "$T/elsewhere/tool"
  DECLARED="$T/elsewhere/tool" run brew_cask_repair c "$T/capture" false
  [ "$(cat "$T/elsewhere/tool")" = keep ]
  BREW_CASK_REPAIRED=""
  declared_bin_fixture
  rm "$T/bin/tool"; echo target > "$T/elsewhere/real"; ln -s "$T/elsewhere/real" "$T/bin/tool"
  run brew_cask_repair c "$T/capture" false
  [ "$(cat "$T/elsewhere/real")" = target ]
  [ -z "$(find "$MEISTER_DIR/backups" -type f 2>/dev/null)" ]
}
