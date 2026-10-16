#!/usr/bin/env bats

setup() {
  source "$BATS_TEST_DIRNAME/../lib/core/cleanup_tally.sh"
  cache_root="$BATS_TEST_TMPDIR/caches"
  CALLS="$BATS_TEST_TMPDIR/calls"
  mkdir -p "$cache_root"
  touch "$CALLS"
  DRY_RUN=false
  unset HOMEBREW_CACHE
  log() { printf '%s\n' "$*"; }
  run_or_dry() {
    printf '%s\n' "$*" >> "$CALLS"
    [ "$DRY_RUN" = true ] || "$@"
  }
  # Never elevate or remove anything outside this test's temporary fixtures.
  sudo() { [ "$1" = -n ] || return 97; shift; "$@"; }
  rm() {
    [ "$1" = -rf ] && [ "$2" = -- ] || return 98
    case "$3" in "$BATS_TEST_TMPDIR"/*) command rm -rf -- "$3" ;; *) return 99 ;; esac
  }
}

teardown() { unset -f rm sudo realpath du; }

@test "normal cleanup preserves configured cache ancestors and removes unrelated entries" {
  HOMEBREW_CACHE="$cache_root/vendor/downloads"
  mkdir -p "$HOMEBREW_CACHE" "$cache_root/vendor-other" "$cache_root/unrelated"
  touch "$HOMEBREW_CACHE/update.dmg" "$cache_root/unrelated/cache" "$cache_root/.hidden"
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
  cleanup_cache_root "$cache_root"
  [ -f "$cache_root/Homebrew/update.dmg" ]
  [ ! -e "$cache_root/unrelated" ]
}

@test "canonical cache target remains protected when HOMEBREW_CACHE is a symlink" {
  mkdir -p "$cache_root/downloads" "$cache_root/unrelated"
  touch "$cache_root/downloads/update.dmg"
  ln -s "$cache_root/downloads" "$BATS_TEST_TMPDIR/cache-alias"
  HOMEBREW_CACHE="$BATS_TEST_TMPDIR/cache-alias"
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
  cleanup_cache_root "$cache_root"
  cleanup_cache_root "$cache_root/downloads"
  [ -f "$cache_root/downloads/update.dmg" ]
  [ ! -s "$CALLS" ]
}

@test "dry run keeps all fixtures and sudo mode uses the same cache protection" {
  HOMEBREW_CACHE="$cache_root/downloads"
  mkdir -p "$HOMEBREW_CACHE" "$cache_root/unrelated"
  touch "$HOMEBREW_CACHE/update.dmg" "$cache_root/unrelated/cache"
  DRY_RUN=true
  cleanup_cache_root "$cache_root" sudo
  [ -f "$cache_root/unrelated/cache" ]
  grep -Fq "sudo -n rm -rf -- $cache_root/unrelated" "$CALLS"
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
  cleanup_cache_root() { return 1; }
  du() { printf '1M\tfixture\n'; }
  report_add() { printf '%s %s\n' "$1" "$2"; }
  run module_cleanup
  [ "$status" = 0 ]
  [[ "$output" == *'WARN User cache cleanup incomplete'* ]]
  [[ "$output" == *'WARN System cache cleanup incomplete'* ]]
  [[ "$output" != *'FIX '* ]]
}
