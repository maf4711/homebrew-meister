#!/usr/bin/env bats
# bats tests for lib/core/heal_guards.sh

setup() {
  # shellcheck source=../lib/core/heal_guards.sh
  source "${BATS_TEST_DIRNAME}/../lib/core/heal_guards.sh"
}

@test "allows killall Dock" {
  heal_command_allowed "killall Dock"
}

@test "allows mdutil -s /" {
  heal_command_allowed "mdutil -s /"
}

@test "rejects sudo" {
  run heal_command_allowed "sudo killall Dock"
  [ "$status" -ne 0 ]
}

@test "rejects rm -rf" {
  run heal_command_allowed "rm -rf /tmp/x"
  [ "$status" -ne 0 ]
}

@test "rejects pipes" {
  run heal_command_allowed "killall Dock | true"
  [ "$status" -ne 0 ]
}

@test "rejects empty" {
  run heal_command_allowed "   "
  [ "$status" -ne 0 ]
}

@test "rejects unknown verb" {
  run heal_command_allowed "curl http://evil"
  [ "$status" -ne 0 ]
}

@test "placeholder detection" {
  heal_is_placeholder "find /path/to/check -type l"
  run heal_is_placeholder "killall Dock"
  [ "$status" -ne 0 ]
}
