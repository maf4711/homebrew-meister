#!/usr/bin/env bats
setup() {
  source "$BATS_TEST_DIRNAME/../lib/core/cleanup_tally.sh"
  dir="$BATS_TEST_TMPDIR/files"
  mkdir -p "$dir"
  DRY_RUN=false
  unset FREED_BYTES
}

@test "measures allocated bytes only after successful single-link deletion" {
  printf 'data to allocate a block\n' > "$dir/delete.me"
  blocks=$(stat -f %b "$dir/delete.me" 2>/dev/null || stat -c %b "$dir/delete.me")
  cleanup_find_delete '*.me' "$dir"
  [ "$CLEANUP_FOUND" = 1 ] && [ "$CLEANUP_REMOVED" = 1 ]
  [ "$FREED_BYTES" = "$((blocks * 512))" ]
  [ "$FREED_BYTES_SCOPE" = measured_file_removals ]
}

@test "hard-linked files and failed deletes never inflate freed bytes" {
  printf data > "$dir/delete.me"
  ln "$dir/delete.me" "$dir/keep.txt"
  cleanup_find_delete '*.me' "$dir"
  [ "$FREED_BYTES" = 0 ] && [ -f "$dir/keep.txt" ]
  printf data > "$dir/fail.me"
  rm() { return 1; }
  cleanup_find_delete '*.me' "$dir"
  [ "$FREED_BYTES" = 0 ] && [ "$CLEANUP_SKIPPED" = 1 ]
}

@test "preview retains files and produces no measured savings" {
  printf data > "$dir/delete.me"
  DRY_RUN=true
  cleanup_find_delete '*.me' "$dir"
  [ -f "$dir/delete.me" ]
  [ "$CLEANUP_FOUND" = 1 ] && [ "$CLEANUP_REMOVED" = 0 ]
  [ -z "${FREED_BYTES:-}" ]
}

teardown() { unset -f rm; }
