#!/usr/bin/env bats
setup() {
  source "$BATS_TEST_DIRNAME/../lib/core/ai_updates.sh"
  source "$BATS_TEST_DIRNAME/../lib/core/profiles.sh"
  DRY_RUN=false
  unset MEISTER_BREW_UPDATE_PID MEISTER_BREW_UPDATE_AT MEISTER_BREW_UPDATE_FRESH
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
      'outdated --cask --greedy') printf 'codex\njan\n' ;;
      'outdated --cask --greedy codex') echo codex; return 1 ;;
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
@test "current AI casks and formulae never invoke upgrade or sudo on repeated checks" {
  export CALLS="$BATS_TEST_TMPDIR/calls"
  REPORTS=""
  report_add() { REPORTS="$REPORTS $*"; }
  ensure_sudo() { echo sudo >> "$CALLS"; }
  brew() {
    echo "$*" >> "$CALLS"
    case "$*" in
      'list --cask') echo codex ;;
      'list --formula') echo ollama ;;
    esac
  }
  ai_update_brew
  ai_update_brew
  ! grep -Eq '^(upgrade|sudo)' "$CALLS"
  [[ "$REPORTS" == *'SUCCESS AI Updates: codex current in Homebrew'* ]]
  [[ "$REPORTS" == *'SUCCESS AI Updates: ollama current in Homebrew'* ]]
  [ "$(grep -c '^outdated --cask --greedy$' "$CALLS")" = 2 ]
  [ "$(grep -c '^outdated --formula$' "$CALLS")" = 2 ]
}
@test "outdated AI packages upgrade once then are only checked on the next run" {
  export CALLS="$BATS_TEST_TMPDIR/calls"
  brew() {
    echo "$*" >> "$CALLS"
    case "$*" in
      'list --cask') echo codex ;;
      'list --formula') echo ollama ;;
      'outdated --cask --greedy')
        if ! grep -q '^upgrade --cask --greedy codex$' "$CALLS"; then echo codex; fi ;;
      'outdated --formula')
        if ! grep -q '^upgrade --formula ollama$' "$CALLS"; then echo example/ai/ollama; fi ;;
    esac
  }
  ai_update_brew
  ai_update_brew
  [ "$(grep -c '^upgrade --cask --greedy codex$' "$CALLS")" = 1 ]
  [ "$(grep -c '^upgrade --formula ollama$' "$CALLS")" = 1 ]
  [ "$(grep -c '^outdated --cask --greedy codex$' "$CALLS")" = 1 ]
  [ "$(grep -c '^outdated --formula ollama$' "$CALLS")" = 1 ]
}
@test "failed outdated probes never upgrade or report current even with partial output" {
  export CALLS="$BATS_TEST_TMPDIR/calls"
  ensure_sudo() { echo sudo >> "$CALLS"; }
  brew() {
    echo "$*" >> "$CALLS"
    case "$*" in
      'list --cask') echo codex ;;
      'list --formula') echo ollama ;;
      'outdated --cask --greedy') echo codex; return 1 ;;
      'outdated --formula') echo ollama; return 1 ;;
    esac
  }
  run ai_update_brew
  [ "$status" = 1 ]
  ! grep -Eq '^(upgrade|sudo)' "$CALLS"
  [[ "$output" == *'ERROR AI Updates: cannot check outdated Homebrew cask clients'* ]]
  [[ "$output" == *'ERROR AI Updates: cannot check outdated Homebrew formula clients'* ]]
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
      'outdated --cask --greedy') printf 'codex\njan\n' ;;
      upgrade*) echo upgrade >> "$CALLS" ;;
    esac
  }
  ai_update_brew
  [ "$(head -1 "$CALLS")" = sudo ]
  [ "$(grep -c sudo "$CALLS")" = 1 ]
}

@test "AI Updates reuses launcher metadata but still verifies every client" {
  export CALLS="$BATS_TEST_TMPDIR/calls"
  MEISTER_BREW_UPDATE_PID=$$
  MEISTER_BREW_UPDATE_AT=$(date +%s)
  MEISTER_BREW_UPDATE_FRESH=true
  BREW_UPDATE_MAX_AGE_SEC=0
  brew() {
    echo "$*" >> "$CALLS"
    case "$*" in 'list --formula') echo ollama ;; esac
  }
  ai_update_brew
  ! grep -q '^update$' "$CALLS"
  ! grep -q '^upgrade' "$CALLS"
  grep -q '^outdated --formula$' "$CALLS"
  [ "$HOMEBREW_NO_AUTO_UPDATE" = 1 ]
}

@test "old PID and future timestamp cannot suppress a fresh metadata check" {
  export CALLS="$BATS_TEST_TMPDIR/calls"
  brew() { echo "$*" >> "$CALLS"; }
  MEISTER_BREW_UPDATE_PID=invalid
  MEISTER_BREW_UPDATE_AT=$(date +%s)
  MEISTER_BREW_UPDATE_FRESH=true
  ai_update_brew
  MEISTER_BREW_UPDATE_PID=$$
  MEISTER_BREW_UPDATE_AT=$(( $(date +%s) + 1000 ))
  ai_update_brew
  [ "$(grep -c '^update$' "$CALLS")" = 2 ]
}

@test "source runtime refreshes only once even in deep profile" {
  export CALLS="$BATS_TEST_TMPDIR/calls"
  MEISTER_DIR="$BATS_TEST_TMPDIR"
  BREW_UPDATE_MAX_AGE_SEC=0
  brew() { echo "$*" >> "$CALLS"; }
  ai_update_brew
  ai_update_brew
  [ "$(grep -c '^update$' "$CALLS")" = 1 ]
  [ -s "$MEISTER_DIR/brew_last_update" ]
  ai_brew_metadata_current
}

@test "failed updater logs operation and exact retry exit without raw output" {
  client() { echo 'PRIVATE_UPDATER_OUTPUT'; return 23; }
  run ai_update_attempt client update
  [ "$status" = 23 ]
  [[ "$output" == *'client update failed (exit 23); retrying once'* ]]
  [[ "$output" == *'failed after retry (exit 23)'* ]]
  [[ "$output" != *'PRIVATE_UPDATER_OUTPUT'* ]]
}
@test "client failure reaches AI-Heal log even when report ledger is silent" {
  REPORTS=""
  report_add() { REPORTS="$REPORTS $*"; }
  client() { return 1; }
  run ai_update_native specific-client client update
  [ "$status" = 1 ]
  [[ "$output" == *'ERROR AI Updates: specific-client update/verification failed'* ]]
}

@test "ownership follows installed artifact even when bundle suggests another cask" {
  mkdir -p "$BATS_TEST_TMPDIR/ChatGPT.app" "$BATS_TEST_TMPDIR/Other.app"
  ln -s "$BATS_TEST_TMPDIR/ChatGPT.app" "$BATS_TEST_TMPDIR/Managed.app"
  brew() {
    [ "$*" = 'list --cask chatgpt' ] || return 1
    echo "$BATS_TEST_TMPDIR/Managed.app"
  }
  ai_brew_owns_installed_app "$BATS_TEST_TMPDIR/ChatGPT.app" $'codex\nchatgpt'
  run ai_brew_owns_installed_app "$BATS_TEST_TMPDIR/Other.app" chatgpt
  [ "$status" = 1 ]
}

# Exercise the real JSON validation while replacing only platform/network tools.
claude_desktop_fixture() {
  CLAUDE_APP="$BATS_TEST_TMPDIR/Claude native.app"
  mkdir -p "$CLAUDE_APP/Contents"
  touch "$CLAUDE_APP/Contents/Info.plist"
  CLAUDE_INSTALLED=2.37337.1
  CLAUDE_FEED='{"currentRelease":"2.37337.1","releases":[{"version":"2.37337.1","updateTo":{"version":"2.37337.1"}}]}'
  CLAUDE_SIGNATURE_STATUS=0
  CLAUDE_NETWORK_STATUS=0
  export CALLS="$BATS_TEST_TMPDIR/claude-calls"
  touch "$CALLS"
  /usr/libexec/PlistBuddy() {
    [ "$3" = "$CLAUDE_APP/Contents/Info.plist" ] || return 1
    case "$2" in
      'Print :CFBundleIdentifier') echo com.anthropic.claudefordesktop ;;
      'Print :CFBundleShortVersionString') printf '%s\n' "$CLAUDE_INSTALLED" ;;
      *) return 1 ;;
    esac
  }
  /usr/bin/codesign() {
    printf 'codesign %s\n' "$*" >> "$CALLS"
    return "$CLAUDE_SIGNATURE_STATUS"
  }
  /usr/bin/curl() {
    printf 'curl %s\n' "$*" >> "$CALLS"
    printf '%s' "$CLAUDE_FEED"
    return "$CLAUDE_NETWORK_STATUS"
  }
  ai_update_attempt() { echo UNEXPECTED_MUTATING_UPDATER; return 1; }
  brew() { [ "$*" = 'list --cask' ]; }
}

@test "native Claude current version is signature verified and checked without an updater" {
  claude_desktop_fixture
  run ai_check_claude_desktop "$CLAUDE_APP"
  [ "$status" = 0 ]
  [[ "$output" == *'SUCCESS AI Updates: Claude native.app 2.37337.1 current (Anthropic release feed; signature verified)'* ]]
  [[ "$output" != *'UNEXPECTED_MUTATING_UPDATER'* ]]
  grep -q -- '--verify --deep --strict' "$CALLS"
  grep -Fq -- '=anchor apple generic and identifier "com.anthropic.claudefordesktop" and certificate leaf[subject.OU] = "Q6L2SF6YDW"' "$CALLS"
  grep -q -- '--connect-timeout 10 --max-time 20 --max-filesize 1048576' "$CALLS"
  grep -q '^curl --disable ' "$CALLS"
  grep -Fq 'https://downloads.claude.ai/releases/darwin/universal/RELEASES.json' "$CALLS"
  ! grep -Eq -- '--location|--insecure|--output|--upload-file|--data' "$CALLS"
}

@test "native Claude older or unrecognized newer versions require the app updater" {
  claude_desktop_fixture
  for CLAUDE_INSTALLED in 2.37336.0 2.37338.0; do
    run ai_check_claude_desktop "$CLAUDE_APP"
    [ "$status" = 1 ]
    [[ "$output" == *"WARN AI Updates: Claude native.app $CLAUDE_INSTALLED differs from Anthropic current 2.37337.1; check for updates in the app"* ]]
    [[ "$output" != *'SUCCESS'* ]]
    [[ "$output" != *'UNEXPECTED_MUTATING_UPDATER'* ]]
  done
}

@test "native Claude signature failure stops before network and never claims current" {
  claude_desktop_fixture
  CLAUDE_SIGNATURE_STATUS=1
  run ai_check_claude_desktop "$CLAUDE_APP"
  [ "$status" = 1 ]
  [[ "$output" == *'WARN'*'Anthropic signature verification failed'* ]]
  [[ "$output" != *'SUCCESS'* ]]
  ! grep -q '^curl ' "$CALLS"
}

@test "native Claude offline feed cannot turn a cached or partial response into success" {
  claude_desktop_fixture
  CLAUDE_NETWORK_STATUS=28
  run ai_check_claude_desktop "$CLAUDE_APP"
  [ "$status" = 1 ]
  [[ "$output" == *'WARN'*'Anthropic release feed unavailable'* ]]
  [[ "$output" != *'SUCCESS'* ]]
}

@test "native Claude rejects malformed missing inconsistent and invalid release versions" {
  claude_desktop_fixture
  for CLAUDE_FEED in \
    '<html>unavailable</html>' \
    '[]' \
    '{}' \
    '{"currentRelease":"2.37337.1","releases":[]}' \
    '{"currentRelease":"2.37337.1","releases":{}}' \
    '{"currentRelease":"2.37337.1","releases":[null]}' \
    '{"currentRelease":true,"releases":[]}' \
    '{"currentRelease":"2.0.0","currentRelease":"2.37337.1","releases":[{"version":"2.37337.1","updateTo":{"version":"2.37337.1"}}]}' \
    '{"currentRelease":"2.37337.1","releases":[{"version":"2.37336.1"}]}' \
    '{"currentRelease":"2.37337.1","releases":[{"version":"2.37337.1","updateTo":{"version":"2.0.0"}}]}' \
    '{"currentRelease":"2.37337.1<script>","releases":[{"version":"2.37337.1<script>"}]}' ; do
    run ai_check_claude_desktop "$CLAUDE_APP"
    [ "$status" = 1 ]
    [[ "$output" == *'WARN'*'Anthropic release feed invalid'* ]]
    [[ "$output" != *'SUCCESS'* ]]
  done
}

@test "native Claude unreadable or malformed installed version cannot claim current" {
  claude_desktop_fixture
  for CLAUDE_INSTALLED in '' 2.37337 2.37337.1suffix; do
    run ai_check_claude_desktop "$CLAUDE_APP"
    [ "$status" = 1 ]
    [[ "$output" == *'WARN'*'installed version unavailable or invalid'* ]]
    [[ "$output" != *'SUCCESS'* ]]
    ! grep -q '^curl ' "$CALLS"
  done
}

@test "unmanaged apps routes native Claude through verified check and preserves other warnings" {
  claude_desktop_fixture
  OTHER_APP="$BATS_TEST_TMPDIR/ChatGPT.app"
  mkdir -p "$OTHER_APP/Contents"
  touch "$OTHER_APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy() {
    if [ "$3" = "$CLAUDE_APP/Contents/Info.plist" ]; then
      case "$2" in
        'Print :CFBundleIdentifier') echo com.anthropic.claudefordesktop ;;
        'Print :CFBundleShortVersionString') echo "$CLAUDE_INSTALLED" ;;
      esac
    elif [ "$3" = "$OTHER_APP/Contents/Info.plist" ] && [ "$2" = 'Print :CFBundleIdentifier' ]; then
      echo com.openai.chat
    else
      return 1
    fi
  }
  run ai_update_unmanaged_app "$CLAUDE_APP" ''
  [ "$status" = 0 ]
  [[ "$output" == *'SUCCESS AI Updates: Claude native.app 2.37337.1 current'* ]]
  [[ "$output" != *'Claude native.app (com.anthropic.claudefordesktop) has no verified unattended updater'* ]]
  run ai_update_unmanaged_app "$OTHER_APP" ''
  [ "$status" = 1 ]
  [[ "$output" == *'WARN AI Updates: ChatGPT.app (com.openai.chat) has no verified unattended updater; update in the app'* ]]
}

@test "Homebrew managed Claude bypasses native release checks" {
  claude_desktop_fixture
  ai_brew_owns_installed_app() { [ "$1" = "$CLAUDE_APP" ]; }
  run ai_update_unmanaged_app "$CLAUDE_APP" claude
  [ "$status" = 0 ]
  [ ! -s "$CALLS" ]
  [[ "$output" != *'WARN'* ]]
}

@test "native Claude dry run neither verifies nor contacts the vendor" {
  claude_desktop_fixture
  DRY_RUN=true
  run ai_check_claude_desktop "$CLAUDE_APP"
  [ "$status" = 0 ]
  [ ! -s "$CALLS" ]
  [[ "$output" != *'SUCCESS'* ]]
}
