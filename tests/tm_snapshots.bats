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
