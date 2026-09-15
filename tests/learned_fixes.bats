#!/usr/bin/env bats

setup() {
  export MEISTER_DIR="$BATS_TEST_TMPDIR/meister"
  mkdir -p "$MEISTER_DIR"
  source "$BATS_TEST_DIRNAME/../lib/core/heal_guards.sh"
  source "$BATS_TEST_DIRNAME/../lib/core/run_lock.sh"
  log() { :; }
  source "$BATS_TEST_DIRNAME/../lib/core/learned_fixes.sh"
  DRY_RUN=false
  AI_HEAL_EXECUTE=true
  MEISTER_OS_VERSION=27.0-buildA-arm64
  heal_context_begin Network '2026-09-14 12:01:01 ERROR PID=123 Could not resolve host: apple.com'
}

@test "failure fingerprint ignores timestamps and PID but preserves error context" {
  a=$(heal_failure_fingerprint '2026-09-14 12:01:01 ERROR PID=123 Could not resolve host: apple.com')
  b=$(heal_failure_fingerprint '2026-09-15 13:02:02 ERROR pid=999 Could not resolve host: apple.com')
  c=$(heal_failure_fingerprint '2026-09-15 13:02:02 ERROR pid=999 Permission denied: apple.com')
  [ "$a" = "$b" ]
  [ "$a" != "$c" ]
}

@test "reuse requires verified success and exact module failure OS context" {
  run learned_fix_lookup Network
  [ "$status" -ne 0 ]
  learned_fix_record Network 'killall Dock' verified
  [ "$(learned_fix_lookup Network)" = 'killall Dock' ]
  HEAL_CONTEXT_OS=27.1-buildB-arm64
  run learned_fix_lookup Network
  [ "$status" -ne 0 ]
  HEAL_CONTEXT_OS=27.0-buildA-arm64
  HEAL_FAILURE_FINGERPRINT=different-error
  run learned_fix_lookup Network
  [ "$status" -ne 0 ]
  run learned_fix_lookup OtherModule
  [ "$status" -ne 0 ]
}

@test "three consecutive failures suspend candidate; verified recovery keeps totals" {
  learned_fix_record Network 'killall Dock' verified
  for _ in 1 2 3; do learned_fix_record Network 'killall Dock' failed; done
  learned_fix_suspended Network 'killall Dock'
  run learned_fix_lookup Network
  [ "$status" -ne 0 ]
  learned_fix_record Network 'killall Dock' verified
  [ "$(learned_fix_lookup Network)" = 'killall Dock' ]
  [ "$(cut -f5-8 "$MEISTER_DIR/learned_fixes.v2.tsv")" = $'2\t3\t0\t0' ]
}

@test "unverified failures are retained but never reused as successful repairs" {
  learned_fix_record Network 'killall Dock' failed
  run learned_fix_lookup Network
  [ "$status" -ne 0 ]
  [ "$(cut -f5-6 "$MEISTER_DIR/learned_fixes.v2.tsv")" = $'0\t1' ]
}

@test "legacy migration quarantines unscoped entries and preserves source" {
  printf 'Network\tkillall Dock\n' > "$MEISTER_DIR/learned_fixes"
  run learned_fix_lookup Network
  [ "$status" -ne 0 ]
  learned_fix_record Network 'mdutil -s /' verified
  grep -q $'legacy-unscoped\tunknown\tkillall Dock\t0\t0\t0\t1' "$MEISTER_DIR/learned_fixes.v2.tsv"
  [ "$(cat "$MEISTER_DIR/learned_fixes")" = $'Network\tkillall Dock' ]
  [ "$(learned_fix_lookup Network)" = 'mdutil -s /' ]
}

@test "dry runs and suggestion-only calls do not change learned evidence" {
  learned_fix_record Network 'killall Dock' verified
  cp "$MEISTER_DIR/learned_fixes.v2.tsv" "$MEISTER_DIR/before"
  DRY_RUN=true
  learned_fix_record Network 'killall Dock' failed
  cmp "$MEISTER_DIR/before" "$MEISTER_DIR/learned_fixes.v2.tsv"
  DRY_RUN=false
  AI_HEAL_EXECUTE=false
  learned_fix_record Network 'killall Dock' failed
  cmp "$MEISTER_DIR/before" "$MEISTER_DIR/learned_fixes.v2.tsv"
}

@test "malformed rows recover while allowlist and field boundaries stay enforced" {
  learned_fix_record Network 'killall Dock' verified
  printf 'broken\trow\n' >> "$MEISTER_DIR/learned_fixes.v2.tsv"
  learned_fix_record Network 'mdutil -s /' failed
  [ "$(wc -l < "$MEISTER_DIR/learned_fixes.v2.tsv" | tr -d ' ')" = 2 ]
  run learned_fix_record Network 'sudo killall Dock' verified
  [ "$status" -ne 0 ]
  run learned_fix_record Network $'killall Dock\nkillall Finder' verified
  [ "$status" -ne 0 ]
  [ "$(learned_fix_lookup Network)" = 'killall Dock' ]
}

@test "case-sensitive paths never share a failure fingerprint" {
  [ "$(heal_failure_fingerprint 'Missing /Volumes/Data/File')" != "$(heal_failure_fingerprint 'Missing /Volumes/Data/file')" ]
}

@test "learning recovers dead transaction owner without changing outer run token" {
  mkdir "$MEISTER_DIR/learned_fixes.v2.lock.d"
  printf '999999999:old\n' > "$MEISTER_DIR/learned_fixes.v2.lock.d/owner"
  RUN_LOCK_TOKEN=outer-token
  learned_fix_record Network 'killall Dock' verified
  [ "$RUN_LOCK_TOKEN" = outer-token ]
  [ ! -d "$MEISTER_DIR/learned_fixes.v2.lock.d" ]
  [ "$(learned_fix_lookup Network)" = 'killall Dock' ]
}
