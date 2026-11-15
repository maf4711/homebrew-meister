#!/usr/bin/env bats
# module_spotlight_fix with every system probe stubbed as a shell function.

setup() {
  MEISTER_DIR="$BATS_TEST_TMPDIR/meister"
  mkdir -p "$MEISTER_DIR"
  DRY_RUN=false
  SPOTLIGHT_FIX_ENABLED=true
  SPOTLIGHT_REINDEX_ON_ERROR=true
  NEEDS_SUDO=true
  SPOTLIGHT_MDS_CPU_THRESHOLD=999
  log() { printf '%s %s\n' "$1" "$2"; }
  report_add() { printf '%s %s\n' "$1" "$2" >> "$MEISTER_DIR/report"; }
  run_or_dry() { "$@"; }
  ps() { :; }
  df() {
    printf 'Filesystem Size Used Avail Capacity iused ifree %%iused Mounted on\n'
    printf '/dev/disk9s1 10G 9G 1G 90%% 1 1 1%% /private/var/run/com.apple.security.cryptexd/mnt/iOS_24A5370g\n'
    printf '/dev/disk7s1 100G 50G 50G 50%% 1 1 1%% /Volumes/Data\n'
  }
  mdutil() { printf '%s:\n\tError: unexpected indexing state.\n' "${*: -1}"; }
  du() { :; }
  find() { :; }
  defaults() { :; }
  sudo() { printf '%s\n' "$*" >> "$MEISTER_DIR/sudo-calls"; }
  eval "$(awk '$0=="module_spotlight_fix() {" {on=1} on {print} on && /^}$/ {exit}' "$BATS_TEST_DIRNAME/../MeisterAI.sh")"
}

@test "cryptex mounts are skipped and real volumes still repaired" {
  run module_spotlight_fix
  [ "$status" -eq 0 ]
  [[ "$output" != *cryptexd* ]]
  [ "$(grep -c cryptexd "$MEISTER_DIR/sudo-calls")" -eq 0 ]
  [ "$(grep -c 'mdutil -E /Volumes/Data' "$MEISTER_DIR/sudo-calls")" -eq 1 ]
  [ "$(grep -c cryptexd "$MEISTER_DIR/report")" -eq 0 ]
}
