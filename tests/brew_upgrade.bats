#!/usr/bin/env bats
# brew upgrade policy — daily must not look frozen or hang on greedy GUI casks

setup() {
  # shellcheck source=../lib/core/brew_upgrade.sh
  source "${BATS_TEST_DIRNAME}/../lib/core/brew_upgrade.sh"
  unset BREW_CASK_GREEDY
  BREW_CASK_SKIP="whatsapp microsoft-word"
}

@test "auto/quick do not use --greedy" {
  run brew_cask_greedy_wanted auto
  [ "$status" -ne 0 ]
  run brew_cask_greedy_wanted quick
  [ "$status" -ne 0 ]
}

@test "deep/all use --greedy" {
  brew_cask_greedy_wanted deep
  brew_cask_greedy_wanted all
}

@test "BREW_CASK_GREEDY=false wins over deep" {
  BREW_CASK_GREEDY=false
  run brew_cask_greedy_wanted deep
  [ "$status" -ne 0 ]
}

@test "BREW_CASK_GREEDY=true wins over auto" {
  BREW_CASK_GREEDY=true
  brew_cask_greedy_wanted auto
}

@test "skips whatsapp and microsoft-word by default" {
  brew_cask_is_skipped whatsapp
  brew_cask_is_skipped microsoft-word
  run brew_cask_is_skipped slack
  [ "$status" -ne 0 ]
}

@test "filter drops skipped tokens from outdated listing" {
  run brew_filter_skipped_casks <<'EOF'
gcloud-cli
microsoft-word
stats
whatsapp
swiftbar
EOF
  [ "$status" -eq 0 ]
  [[ "$output" == *"gcloud-cli"* ]]
  [[ "$output" == *"stats"* ]]
  [[ "$output" == *"swiftbar"* ]]
  [[ "$output" != *"whatsapp"* ]]
  [[ "$output" != *"microsoft-word"* ]]
}

@test "meisterSiri uses brew upgrade --formula not bare brew upgrade" {
  src="${BATS_TEST_DIRNAME}/../meisterSiri.sh"
  grep -q 'brew upgrade --formula' "$src"
  # the unattended upgrade line must not be a bare `brew upgrade`
  ! grep -E 'timeout .* brew upgrade >' "$src"
  grep -q 'brew upgrade --cask' "$src"
}

@test "cask upgrade is wrapped in timeout" {
  src="${BATS_TEST_DIRNAME}/../meisterSiri.sh"
  grep -q 'BREW_CASK_TIMEOUT_SEC\|timeout .* brew upgrade --cask' "$src"
}

@test "upgrades one package at a time with START/DONE banners" {
  src="${BATS_TEST_DIRNAME}/../meisterSiri.sh"
  grep -q 'brew_upgrade_each' "$src"
  grep -q 'START \${name}' "$src"
  grep -q 'DONE  \${name}' "$src"
  grep -q 'still running' "$src"
}

@test "Fix #151: sudo is pre-authed before cask upgrade so root-owned apps don't hard-fail" {
  src="${BATS_TEST_DIRNAME}/../meisterSiri.sh"
  # ensure_sudo call must appear before brew_upgrade_each cask, not after
  before_line=$(grep -n 'ensure_sudo "brew cask upgrade"' "$src" | head -1 | cut -d: -f1)
  each_line=$(grep -n 'brew_upgrade_each cask' "$src" | head -1 | cut -d: -f1)
  [ -n "$before_line" ]
  [ -n "$each_line" ]
  [ "$before_line" -lt "$each_line" ]
}

@test "Fix #151: cask reinstall retry (auto-heal) also pre-auths sudo" {
  src="${BATS_TEST_DIRNAME}/../meisterSiri.sh"
  grep -q 'ensure_sudo "cask reinstall: \$name"' "$src"
}

@test "Fix #151: missing sudo ticket does not abort the run (warn + continue)" {
  src="${BATS_TEST_DIRNAME}/../meisterSiri.sh"
  grep -q 'No sudo ticket — casks needing admin rights' "$src"
}
