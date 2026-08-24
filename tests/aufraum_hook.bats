#!/usr/bin/env bats
# bats tests for lib/core/aufraum_hook.sh

setup() {
  # shellcheck source=../lib/core/aufraum_hook.sh
  source "${BATS_TEST_DIRNAME}/../lib/core/aufraum_hook.sh"
}

@test "AUFRAUM_APPLY defaults off" {
  unset AUFRAUM_APPLY
  run aufraum_apply_enabled
  [ "$status" -eq 1 ]
}

@test "AUFRAUM_APPLY=true enables live" {
  AUFRAUM_APPLY=true
  run aufraum_apply_enabled
  [ "$status" -eq 0 ]
}

@test "operator prefers AUFRAUM_OPERATOR" {
  fake=$(mktemp)
  echo '#!/bin/sh' > "$fake"
  chmod +x "$fake"
  AUFRAUM_OPERATOR="$fake"
  run aufraum_operator
  [ "$status" -eq 0 ]
  [ "$output" = "$fake" ]
  rm -f "$fake"
}

@test "operator missing when AUFRAUM_OPERATOR points nowhere" {
  AUFRAUM_OPERATOR="/no/such/aufraum.py"
  # also hide default path by pointing HOME at empty tmp
  HOME=$(mktemp -d)
  run aufraum_operator
  [ "$status" -eq 1 ]
  rm -rf "$HOME"
}

@test "count_planned counts space-arrow-space lines" {
  body=$'keep\nfoo -> bar\nnope\nbaz -> qux\n'
  run aufraum_count_planned <<< "$body"
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]
}

@test "count_planned is zero on empty" {
  run aufraum_count_planned <<< ""
  [ "$output" = "0" ]
}
