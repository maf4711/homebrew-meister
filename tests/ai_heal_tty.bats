#!/usr/bin/env bats

@test "ai_heal_emit never writes /dev/tty when stdout is not a TTY" {
  awk '$0=="ai_heal_emit() {" {on=1} on {print} on && /^}$/ {exit}' \
    "$BATS_TEST_DIRNAME/../MeisterAI.sh" | grep -q '\[ -t '
}
