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

tm_fixture() {
  eval "$(awk '$0=="module_tm_health() {" {on=1} on {print} on && /^}$/ {exit}' "$SRC")"
  DRY_RUN=false
  log() { :; }
  command_exists() { return 0; }
  report_add() { echo "$1 $2"; }
  tmutil() {
    case "$1" in
      destinationinfo) printf 'Name : Backup\n'; [ -n "${TM_MOUNT:-}" ] && printf 'Mount Point : /Volumes/Backup\n' ;;
      latestbackup) : ;;
      startbackup) [ "${TM_START_OK:-true}" = true ] ;;
    esac
  }
}

@test "no backups on a disconnected destination is silent" {
  tm_fixture
  run module_tm_health
  [ "$status" = 0 ]
  [ "$output" = '' ]
}

@test "no backups on a connected destination starts the first backup" {
  tm_fixture
  TM_MOUNT=1 run module_tm_health
  [ "$output" = 'FIX Time Machine: first backup started' ]
  TM_MOUNT=1 TM_START_OK=false run module_tm_health
  [[ "$output" == 'WARN Time Machine: no backups and the backup could not be started'* ]]
  DRY_RUN=true TM_MOUNT=1 run module_tm_health
  [ "$output" = 'WOULD Time Machine: start first backup' ]
}
