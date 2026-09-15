#!/usr/bin/env bats
setup() {
  ORIGINAL_TEST_PATH="$PATH"
  source "$BATS_TEST_DIRNAME/../lib/core/process_group.sh"
  fixture="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$fixture"
  printf '#!/bin/sh\nprintf "%%s\\n" "$@"\n' > "$fixture/timeout"
  chmod +x "$fixture/timeout"
}

@test "GUI timeout keeps child commands in the inherited process group" {
  PATH="$fixture:/bin:/usr/bin"
  MEISTER_GUI_PROCESS_GROUP=1
  meister_configure_timeout
  run timeout 30 'a command' 'one argument'
  [ "$status" -eq 0 ]
  [ "$output" = $'--foreground\n30\na command\none argument' ]
}

@test "normal CLI timeout retains its original arguments" {
  PATH="$fixture:/bin:/usr/bin"
  MEISTER_GUI_PROCESS_GROUP=0
  meister_configure_timeout
  run timeout 30 'a command'
  [ "$output" = $'30\na command' ]
}

@test "missing timeout remains missing for dependency checks" {
  PATH="$BATS_TEST_TMPDIR/missing"
  MEISTER_GUI_PROCESS_GROUP=1
  meister_configure_timeout
  run command -v timeout
  [ "$status" -ne 0 ]
}

teardown() { PATH="$ORIGINAL_TEST_PATH"; }
