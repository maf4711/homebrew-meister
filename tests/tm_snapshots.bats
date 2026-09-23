#!/usr/bin/env bats
# Time Machine local snapshot checks are retired.

SRC="${BATS_TEST_DIRNAME}/../MeisterAI.sh"

@test "MeisterAI does not enumerate or thin Time Machine local snapshots" {
  if grep -n 'listlocalsnapshots\|thinlocalsnapshots\|deletelocalsnapshots' "$SRC"; then
    echo "Time Machine snapshot check still present" >&2
    return 1
  fi
}

@test "APFS Snapshots module is not scheduled" {
  if grep -n 'module_apfs_snapshots' "$SRC"; then
    echo "module_apfs_snapshots still present" >&2
    return 1
  fi
}

@test "missing backup destination produces no warning or backup probe" {
  eval "$(awk '$0=="module_tm_health() {" {on=1} on {print} on && /^}$/ {exit}' "$SRC")"
  log() { :; }
  command_exists() { return 0; }
  report_add() { echo UNEXPECTED_REPORT; }
  tmutil() {
    [ "$1" = destinationinfo ] || { echo UNEXPECTED_PROBE; return 1; }
    echo 'No destinations configured.'
  }
  run module_tm_health
  [ "$status" = 0 ]
  [ "$output" = '' ]
}

@test "automatic backup destination nags and Settings opener are removed" {
  ! grep -E 'AUTOFIX_OPEN_TIMEMACHINE|single copy|SINGLE COPY|Time Machine NOT configured|Time Machine is not configured|not configured \(no backup' "$SRC"
}
