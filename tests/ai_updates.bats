#!/usr/bin/env bats
setup() {
  source "$BATS_TEST_DIRNAME/../lib/core/ai_updates.sh"
  source "$BATS_TEST_DIRNAME/../lib/core/profiles.sh"
  DRY_RUN=false
  log() { echo "$*"; }
  report_add() { echo "$*"; }
  timeout() { shift; "$@"; }
}
@test "AI Updates runs in every maintenance profile with dev updates disabled" {
  UNIVERSAL_UPDATES=false
  for RUN_PROFILE in quick auto deep all; do module_in_profile 'AI Updates'; done
}
@test "native updater failure is not success and is retried once" {
  export COUNT="$BATS_TEST_TMPDIR/count"
  client() { echo call >> "$COUNT"; return 1; }
  run ai_update_native client client update
  [ "$status" -ne 0 ]
  [ "$(wc -l < "$COUNT" | tr -d ' ')" = 2 ]
  [[ "$output" == *'ERROR'* ]]
  [[ "$output" != *'SUCCESS'* ]]
}
@test "native success requires a readable version after update" {
  client() { [ "$1" = update ]; }
  run ai_update_native client client update
  [ "$status" -ne 0 ]
}
@test "dry run does not invoke native clients" {
  DRY_RUN=true
  client() { echo UNEXPECTED; return 1; }
  run ai_update_native client client update
  [ "$status" = 0 ]
  [[ "$output" == *'DRY-RUN'* ]]
  [[ "$output" != *'UNEXPECTED'* ]]
}
@test "brew catalog excludes unrelated Gemini duplicate finder" {
  run ai_brew_client gemini
  [ "$status" -ne 0 ]
  ai_brew_client codex
  ai_brew_client codex-app
  ai_brew_client jan
}
@test "brew update verifies greedy outdated status and continues after failure" {
  export CALLS="$BATS_TEST_TMPDIR/calls"
  brew() {
    echo "$*" >> "$CALLS"
    case "$*" in
      'list --cask') printf 'codex\njan\ngemini\n' ;;
      'list --formula') : ;;
      'outdated --cask --greedy codex') echo codex ;;
    esac
  }
  run ai_update_brew
  [ "$status" -ne 0 ]
  grep -q 'upgrade --cask --greedy jan' "$CALLS"
  ! grep -q 'upgrade.*gemini' "$CALLS"
  [[ "$output" == *'ERROR'*codex* ]]
}
@test "brew refresh failure cannot claim freshness" {
  brew() { [ "$1" != update ]; }
  run ai_update_brew
  [ "$status" -ne 0 ]
  [[ "$output" != *'SUCCESS'* ]]
}
@test "npm catalog includes AI clients but excludes unrelated globals" {
  ai_npm_client '@google/gemini-cli'
  ai_npm_client '@openai/codex'
  ai_npm_client '@anthropic-ai/claude-code'
  run ai_npm_client npm
  [ "$status" -ne 0 ]
}
@test "npm uses owner prefix, installs latest major and verifies version" {
  export ROOT="$BATS_TEST_TMPDIR/global"
  export CALLS="$BATS_TEST_TMPDIR/calls"
  mkdir -p "$ROOT/@google/gemini-cli" "$BATS_TEST_TMPDIR/bin"
  printf '{"version":"1.0.0"}' > "$ROOT/@google/gemini-cli/package.json"
  cat > "$BATS_TEST_TMPDIR/bin/npm" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >> "$CALLS"
case "$1" in
  root) echo "$ROOT" ;;
  view) echo 2.0.0 ;;
  install) printf '{"version":"2.0.0"}' > "$ROOT/@google/gemini-cli/package.json" ;;
esac
SH
  chmod +x "$BATS_TEST_TMPDIR/bin/npm"
  run ai_update_npm "$BATS_TEST_TMPDIR/bin/npm"
  [ "$status" = 0 ]
  grep -q 'install -g @google/gemini-cli@2.0.0' "$CALLS"
  [[ "$output" == *'2.0.0 verified'* ]]
}
@test "npm exit zero with stale package is an error and report stays in caller" {
  export ROOT="$BATS_TEST_TMPDIR/global"
  mkdir -p "$ROOT/@openai/codex" "$BATS_TEST_TMPDIR/bin"
  printf '{"version":"1.0.0"}' > "$ROOT/@openai/codex/package.json"
  cat > "$BATS_TEST_TMPDIR/bin/npm" <<'SH'
#!/bin/bash
case "$1" in root) echo "$ROOT" ;; view) echo 2.0.0 ;; esac
SH
  chmod +x "$BATS_TEST_TMPDIR/bin/npm"
  REPORTS=""
  report_add() { REPORTS="$REPORTS $*"; }
  rc=0
  ai_update_npm "$BATS_TEST_TMPDIR/bin/npm" || rc=$?
  [ "$rc" = 1 ]
  [[ "$REPORTS" == *'ERROR'*'version mismatch'* ]]
}
@test "npm registry failure does not install anything or claim current" {
  export ROOT="$BATS_TEST_TMPDIR/global"
  export CALLS="$BATS_TEST_TMPDIR/calls"
  mkdir -p "$ROOT/@openai/codex" "$BATS_TEST_TMPDIR/bin"
  printf '{"version":"1.0.0"}' > "$ROOT/@openai/codex/package.json"
  cat > "$BATS_TEST_TMPDIR/bin/npm" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >> "$CALLS"
case "$1" in root) echo "$ROOT" ;; *) exit 1 ;; esac
SH
  chmod +x "$BATS_TEST_TMPDIR/bin/npm"
  run ai_update_npm "$BATS_TEST_TMPDIR/bin/npm"
  [ "$status" = 1 ]
  ! grep -q install "$CALLS"
  [[ "$output" != *'SUCCESS'* ]]
}
@test "brew ownership does not cover a renamed duplicate app" {
  mkdir -p "$BATS_TEST_TMPDIR/Codex.app" "$BATS_TEST_TMPDIR/ChatGPT.app"
  ln -s "$BATS_TEST_TMPDIR/Codex.app" "$BATS_TEST_TMPDIR/Managed.app"
  brew() { echo "$BATS_TEST_TMPDIR/Managed.app"; }
  ai_brew_owns_app codex-app "$BATS_TEST_TMPDIR/Codex.app"
  run ai_brew_owns_app codex-app "$BATS_TEST_TMPDIR/ChatGPT.app"
  [ "$status" = 1 ]
}
@test "AI casks authenticate before upgrading and only once" {
  export CALLS="$BATS_TEST_TMPDIR/calls"
  ensure_sudo() { echo sudo >> "$CALLS"; }
  brew() {
    case "$*" in
      'list --cask') printf 'codex\njan\n' ;;
      upgrade*) echo upgrade >> "$CALLS" ;;
    esac
  }
  ai_update_brew
  [ "$(head -1 "$CALLS")" = sudo ]
  [ "$(grep -c sudo "$CALLS")" = 1 ]
}
