#!/usr/bin/env bats

setup() {
  source "$BATS_TEST_DIRNAME/../lib/core/path.sh"
}

@test "bootstrap prepends /opt/homebrew/bin when it exists" {
  [ -d /opt/homebrew/bin ] || skip "no Homebrew prefix"
  PATH=/usr/bin:/bin
  meister_bootstrap_path
  [[ ":$PATH:" == *:/opt/homebrew/bin:* ]]
}

@test "find_brew locates brew even with a stripped PATH" {
  [ -x /opt/homebrew/bin/brew ] || skip "no /opt/homebrew/bin/brew"
  PATH=/usr/bin:/bin
  run meister_find_brew
  [ "$status" -eq 0 ]
  [ "$output" = "/opt/homebrew/bin/brew" ]
}

@test "bootstrap is idempotent" {
  PATH=/usr/bin:/bin
  meister_bootstrap_path
  first=$PATH
  meister_bootstrap_path
  [ "$PATH" = "$first" ]
}
