#!/usr/bin/env bats

setup() {
  source "$BATS_TEST_DIRNAME/../lib/core/cleanup_tally.sh"
  cache_root="$BATS_TEST_TMPDIR/caches"
  CALLS="$BATS_TEST_TMPDIR/calls"
  mkdir -p "$cache_root"
  touch "$CALLS"
  DRY_RUN=false
  unset HOMEBREW_CACHE CACHE_MIN_AGE_DAYS FIND_TIMEOUT_SEC VERIFIED_REPAIR_COUNT
  report_add() { printf '%s %s\n' "$1" "$2"; }
  # Keep timeout/privilege wrappers inside the fixture sandbox.
  timeout() { shift; "$@"; }
  log() { printf '%s\n' "$*"; }
  run_or_dry() {
    printf '%s\n' "$*" >> "$CALLS"
    [ "$DRY_RUN" = true ] || "$@"
  }
  # Never elevate or remove anything outside this test's temporary fixtures.
  sudo() { printf 'sudo %s\n' "$*" >> "$CALLS"; [ "$1" = -n ] || return 97; shift; "$@"; }
  rm() {
    printf 'rm %s\n' "$*" >> "$CALLS"
    [ "$1" = -rf ] && [ "$2" = -- ] || return 98
    case "$3" in "$BATS_TEST_TMPDIR"/*) command rm -rf -- "$3" ;; *) return 99 ;; esac
  }
}

teardown() { unset -f rm sudo realpath du stat find timeout; }

# Age every nested fixture; recent descendants must prevent whole-tree removal.
age_fixture() { command find "$cache_root" -exec touch -h -t 202001010000 {} +; }

@test "normal cleanup preserves configured cache ancestors and removes unrelated entries" {
  HOMEBREW_CACHE="$cache_root/vendor/downloads"
  mkdir -p "$HOMEBREW_CACHE" "$cache_root/vendor-other" "$cache_root/unrelated"
  touch "$HOMEBREW_CACHE/update.dmg" "$cache_root/unrelated/cache" "$cache_root/.hidden"
  age_fixture
  cleanup_cache_root "$cache_root"
  [ -f "$HOMEBREW_CACHE/update.dmg" ]
  [ ! -e "$cache_root/unrelated" ]
  [ ! -e "$cache_root/vendor-other" ]
  [ -f "$cache_root/.hidden" ]
}

@test "default Homebrew cache is protected independently of HOMEBREW_CACHE" {
  mkdir -p "$cache_root/Homebrew" "$cache_root/unrelated"
  touch "$cache_root/Homebrew/update.dmg"
  # Map only the default protected path into a fixture; never change HOME.
  realpath() {
    if [ "$1" = "$HOME/Library/Caches/Homebrew" ]; then
      command realpath "$cache_root/Homebrew"
    else
      command realpath "$@"
    fi
  }
  age_fixture
  cleanup_cache_root "$cache_root"
  [ -f "$cache_root/Homebrew/update.dmg" ]
  [ ! -e "$cache_root/unrelated" ]
}

@test "canonical cache target remains protected when HOMEBREW_CACHE is a symlink" {
  mkdir -p "$cache_root/downloads" "$cache_root/unrelated"
  touch "$cache_root/downloads/update.dmg"
  ln -s "$cache_root/downloads" "$BATS_TEST_TMPDIR/cache-alias"
  HOMEBREW_CACHE="$BATS_TEST_TMPDIR/cache-alias"
  age_fixture
  cleanup_cache_root "$cache_root"
  [ -f "$cache_root/downloads/update.dmg" ]
  [ ! -e "$cache_root/unrelated" ]
}

@test "configured symlink parents and aliased cleanup roots stay intact" {
  mkdir -p "$cache_root/vendor" "$BATS_TEST_TMPDIR/downloads" "$cache_root/unrelated"
  ln -s "$BATS_TEST_TMPDIR/downloads" "$cache_root/vendor/cache"
  ln -s "$cache_root" "$BATS_TEST_TMPDIR/root-alias"
  HOMEBREW_CACHE="$cache_root/vendor/cache"
  touch "$HOMEBREW_CACHE/update.dmg"
  age_fixture
  cleanup_cache_root "$cache_root"
  [ -L "$cache_root/vendor/cache" ]
  HOMEBREW_CACHE="$cache_root/vendor"
  cleanup_cache_root "$BATS_TEST_TMPDIR/root-alias"
  [ -f "$HOMEBREW_CACHE/cache/update.dmg" ]
  [ ! -e "$cache_root/unrelated" ]
}

@test "cleanup of the protected cache itself or a descendant deletes nothing" {
  HOMEBREW_CACHE="$cache_root"
  mkdir -p "$cache_root/downloads"
  touch "$cache_root/downloads/update.dmg"
  age_fixture
  cleanup_cache_root "$cache_root"
  cleanup_cache_root "$cache_root/downloads"
  [ -f "$cache_root/downloads/update.dmg" ]
  [ ! -s "$CALLS" ]
}

@test "dry run keeps all fixtures and sudo mode uses the same cache protection" {
  HOMEBREW_CACHE="$cache_root/downloads"
  mkdir -p "$HOMEBREW_CACHE" "$cache_root/unrelated"
  touch "$HOMEBREW_CACHE/update.dmg" "$cache_root/unrelated/cache"
  age_fixture
  DRY_RUN=true
  cleanup_cache_root "$cache_root" sudo
  [ -f "$cache_root/unrelated/cache" ]
  ! grep -Fq "rm -rf" "$CALLS"
  ! grep -Fq "$HOMEBREW_CACHE" "$CALLS"
  DRY_RUN=false
  cleanup_cache_root "$cache_root" sudo
  [ ! -e "$cache_root/unrelated" ]
  [ -f "$HOMEBREW_CACHE/update.dmg" ]
}

@test "cache cleanup module reports failed removals without a repair claim" {
  eval "$(awk '$0=="module_cleanup() {" {on=1} on {print} on && /^}$/ {exit}' "$BATS_TEST_DIRNAME/../MeisterAI.sh")"
  CLEAN_XCODE=false
  EMPTY_TRASH=false
  CLEAN_CACHES=true
  NEEDS_SUDO=true
  LIST_LARGE_FILES=false
  cleanup_cache_root() {
    CACHE_CLEANUP_ELIGIBLE=0 CACHE_CLEANUP_REMOVED=0 CACHE_CLEANUP_ACTIVE=0 CACHE_CLEANUP_PRESERVED=0 CACHE_CLEANUP_FAILED=1
    return 1
  }
  du() { printf '1M\tfixture\n'; }
  report_add() { printf '%s %s\n' "$1" "$2"; }
  run module_cleanup
  [ "$status" = 0 ]
  [[ "$output" == *'WARN User cache cleanup incomplete'* ]]
  [[ "$output" == *'WARN System cache cleanup incomplete'* ]]
  [[ "$output" != *'FIX '* ]]
}

@test "recent descendants protect a stale parent while unrelated stale cache is removed" {
  mkdir -p "$cache_root/active/nested" "$cache_root/old"
  touch "$cache_root/active/nested/read-cache" "$cache_root/old/old-cache"
  age_fixture
  touch "$cache_root/active/nested/read-cache"
  cleanup_cache_root "$cache_root"
  [ -f "$cache_root/active/nested/read-cache" ]
  [ ! -e "$cache_root/old" ]
  [ "$CACHE_CLEANUP_ACTIVE" = 1 ]
  [ "$CACHE_CLEANUP_REMOVED" = 1 ]
  [ "$VERIFIED_REPAIR_COUNT" = 1 ]
}

@test "macOS managed caches are preserved before denied metadata probes" {
  mkdir -p "$cache_root/com.apple.protected" "$cache_root/CloudKit"
  age_fixture
  stat() { echo UNEXPECTED_METADATA; return 1; }
  run cleanup_cache_report "$cache_root" sudo System
  [ "$status" = 0 ]
  [[ "$output" == *'2 managed/protected entries preserved'* ]]
  [[ "$output" != *WARN* && "$output" != *FIX* && "$output" != *UNEXPECTED* ]]
  [ -d "$cache_root/com.apple.protected" ]
  [ ! -s "$CALLS" ]
}

@test "sealed system and temporary roots including aliases are never inspected or removed" {
  mkdir -p "$cache_root/unrelated"
  age_fixture
  for TEST_PROTECTED_TARGET in /System/Library/Caches /private/var/tmp /var/tmp /System/Library/Caches/nested; do
    realpath() { printf '%s\n' "$TEST_PROTECTED_TARGET"; }
    run cleanup_cache_report "$cache_root" sudo System
    [ "$status" = 0 ]
    [[ "$output" == *'Preserved macOS-managed cache/temporary root'* ]]
    [[ "$output" != *WARN* && "$output" != *FIX* ]]
  done
  [ -d "$cache_root/unrelated" ]
  [ ! -s "$CALLS" ]
}

@test "protected BSD flags retain cache without a failure or repair" {
  mkdir -p "$cache_root/locked"
  age_fixture
  stat() { printf 'uchg\n'; }
  cleanup_cache_report "$cache_root" '' User > "$BATS_TEST_TMPDIR/report"
  [ "$CACHE_CLEANUP_PRESERVED" = 1 ]
  [ "$CACHE_CLEANUP_REMOVED" = 0 ]
  [ "$CACHE_CLEANUP_FAILED" = 0 ]
  [ -d "$cache_root/locked" ]
  ! grep -E '^(FIX|WARN)' "$BATS_TEST_TMPDIR/report"
}

@test "metadata failure preserves an unclassified cache and warns" {
  mkdir -p "$cache_root/unreadable"
  age_fixture
  stat() { return 1; }
  run cleanup_cache_report "$cache_root" '' User
  [[ "$output" == *'WARN User cache cleanup incomplete: 1 entries failed'* ]]
  [[ "$output" != *'FIX '* ]]
  [ -d "$cache_root/unreadable" ]
  [ ! -s "$CALLS" ]
}

@test "an unreadable cache root is not reported as empty or cleaned" {
  timeout() { return 1; }
  run cleanup_cache_report "$cache_root" '' User
  [[ "$output" == *'Cache root could not be listed; preserved'* ]]
  [[ "$output" == *'WARN User cache cleanup incomplete: 1 entries failed'* ]]
  [[ "$output" != *'FIX '* && "$output" != *'0 removed'* ]]
  [ ! -s "$CALLS" ]
}

@test "inspection failure and timeout preserve cache without false repair" {
  mkdir -p "$cache_root/unreadable"
  age_fixture
  find() { echo 'permission denied' >&2; return 1; }
  run cleanup_cache_report "$cache_root" '' User
  [[ "$output" == *'Cache inspection failed; preserved'* ]]
  [[ "$output" == *'WARN User cache cleanup incomplete: 1 entries failed'* ]]
  [[ "$output" != *'FIX '* ]]
  timeout() { return 124; }
  run cleanup_cache_report "$cache_root" '' User
  [[ "$output" == *'WARN User cache cleanup incomplete: 1 entries failed'* ]]
  [[ "$output" != *'FIX '* ]]
  [ -d "$cache_root/unreadable" ]
  [ ! -s "$CALLS" ]
}

@test "a successful remover exit without actual removal stays a warning" {
  mkdir -p "$cache_root/stuck"
  age_fixture
  rm() { return 0; }
  cleanup_cache_report "$cache_root" '' User > "$BATS_TEST_TMPDIR/report"
  [ "$CACHE_CLEANUP_REMOVED" = 0 ]
  [ "$CACHE_CLEANUP_FAILED" = 1 ]
  grep -Fq 'WARN User cache cleanup incomplete: 1 entries failed' "$BATS_TEST_TMPDIR/report"
  ! grep -q '^FIX ' "$BATS_TEST_TMPDIR/report"
  [ "${VERIFIED_REPAIR_COUNT:-0}" = 0 ]
}

@test "partial failures retain honest successful and failed entry counts" {
  mkdir -p "$cache_root/old" "$cache_root/stuck"
  age_fixture
  rm() {
    [ "$3" = "$cache_root/stuck" ] && return 1
    [ "$3" = "$cache_root/old" ] || return 99
    command rm -rf -- "$3"
  }
  cleanup_cache_report "$cache_root" '' User > "$BATS_TEST_TMPDIR/report"
  grep -Fq 'FIX User caches: removed 1 stale entries' "$BATS_TEST_TMPDIR/report"
  grep -Fq 'WARN User cache cleanup incomplete: 1 entries failed' "$BATS_TEST_TMPDIR/report"
  [ -d "$cache_root/stuck" ]
  [ ! -e "$cache_root/old" ]
}

@test "preview reports WOULD with no deletion and no verified repairs" {
  mkdir -p "$cache_root/old"
  age_fixture
  DRY_RUN=true
  cleanup_cache_report "$cache_root" sudo System > "$BATS_TEST_TMPDIR/report"
  grep -Fq 'WOULD System caches: remove 1 stale entries' "$BATS_TEST_TMPDIR/report"
  ! grep -q '^FIX ' "$BATS_TEST_TMPDIR/report"
  ! grep -q 'rm -rf' "$CALLS"
  [ -d "$cache_root/old" ]
  [ "$CACHE_CLEANUP_REMOVED" = 0 ]
  [ "${VERIFIED_REPAIR_COUNT:-0}" = 0 ]
}

@test "no eligible cache entries never become a FIX" {
  mkdir -p "$cache_root/recent"
  cleanup_cache_report "$cache_root" '' User > "$BATS_TEST_TMPDIR/report"
  [ "$CACHE_CLEANUP_ACTIVE" = 1 ]
  ! grep -E '^(FIX|WARN|WOULD)' "$BATS_TEST_TMPDIR/report"
  [ ! -s "$CALLS" ]
}

@test "invalid retention or timeout values fail closed" {
  mkdir -p "$cache_root/old"
  age_fixture
  for value in 0 -1 abc 999999999999999999999999999 00; do
    CACHE_MIN_AGE_DAYS="$value"
    run cleanup_cache_report "$cache_root" '' User
    [[ "$output" == *WARN* && "$output" != *'FIX '* ]]
  done
  CACHE_MIN_AGE_DAYS=7
  FIND_TIMEOUT_SEC=0
  run cleanup_cache_report "$cache_root" '' User
  [[ "$output" == *WARN* && "$output" != *'FIX '* ]]
  [ -d "$cache_root/old" ]
  [ ! -s "$CALLS" ]
}
