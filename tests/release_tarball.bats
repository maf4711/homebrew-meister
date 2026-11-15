#!/usr/bin/env bats
# release.sh helpers for the source tarball (issue #6). curl, git and gh are stubbed.

setup() {
  source "$BATS_TEST_DIRNAME/../scripts/release-lib.sh"
  export RELEASE_RETRY_SLEEP=0
  LOG="$BATS_TEST_TMPDIR/calls"; : > "$LOG"
  OUT="$BATS_TEST_TMPDIR/out.tar.gz"
}

@test "tarball URLs are the GitHub archive URL first and codeload as fallback" {
  run release_tarball_urls owner/repo 1.2
  [ "${lines[0]}" = "https://github.com/owner/repo/archive/refs/tags/v1.2.tar.gz" ]
  [ "${lines[1]}" = "https://codeload.github.com/owner/repo/tar.gz/refs/tags/v1.2" ]
}

@test "fetch falls back to codeload when the archive URL keeps failing" {
  curl() {
    local out="" url="${*: -1}"
    while [ $# -gt 0 ]; do [ "$1" = -o ] && out="$2"; shift; done
    echo "$url" >> "$LOG"
    case "$url" in *codeload*) echo tarball > "$out" ;; *) return 56 ;; esac
  }
  run release_fetch_tarball "$OUT" https://github.com/a/archive https://codeload.github.com/a
  [ "$status" = 0 ]
  [ "$(cat "$OUT")" = tarball ]
  grep -q codeload "$LOG"
}

@test "fetch retries over several rounds before giving up" {
  curl() { echo try >> "$LOG"; return 56; }
  RELEASE_FETCH_ROUNDS=3 run release_fetch_tarball "$OUT" u1 u2
  [ "$status" = 1 ]
  [ "$(wc -l < "$LOG" | tr -d ' ')" = 6 ]
  [ ! -s "$OUT" ]
}

@test "existing release on the same commit resumes, on another commit aborts" {
  git() { case "$*" in "fetch -q origin tag v1.2"*) return 0 ;; "rev-parse v1.2^{commit}") echo abc ;; esac; }
  gh() { [ "$1 $2" = "release view" ]; }
  run release_existing_state o/r 1.2 abc
  [ "$output" = resume ]
  run release_existing_state o/r 1.2 def
  [ "$output" = conflict ]
  gh() { return 1; }
  run release_existing_state o/r 1.2 abc
  [ "$output" = new ]
}

@test "brew cache is seeded under Homebrew's name for the formula URL" {
  export HOMEBREW_CACHE="$BATS_TEST_TMPDIR/cache"
  echo data > "$OUT"
  url=https://github.com/o/homebrew-meister/archive/refs/tags/v1.2.tar.gz
  run release_seed_brew_cache "$OUT" "$url" 1.2
  [ "$status" = 0 ]
  h=$(printf %s "$url" | shasum -a 256 | awk '{print $1}')
  [ "$(cat "$HOMEBREW_CACHE/downloads/$h--homebrew-meister-1.2.tar.gz")" = data ]
}

@test "release.sh uses the helpers instead of a single-URL fetch" {
  grep -q 'release-lib.sh' "$BATS_TEST_DIRNAME/../release.sh"
  grep -q 'release_fetch_tarball' "$BATS_TEST_DIRNAME/../release.sh"
  grep -q 'release_existing_state' "$BATS_TEST_DIRNAME/../release.sh"
  grep -q 'release_seed_brew_cache' "$BATS_TEST_DIRNAME/../release.sh"
}
