#!/usr/bin/env bats

setup() {
  export MEISTER_DIR="$BATS_TEST_TMPDIR/meister"
  mkdir -p "$MEISTER_DIR"
  AI_HEAL_EXECUTE=false
  # shellcheck source=../lib/core/last_json.sh
  source "${BATS_TEST_DIRNAME}/../lib/core/last_json.sh"
}

@test "write_last_json creates valid-ish JSON" {
  write_last_json 87 10 3 2 0 1 120 quick 6.13
  [ -f "$MEISTER_DIR/last.json" ]
  grep -q '"schema": "meister.last/v1"' "$MEISTER_DIR/last.json"
  grep -q '"score": 87' "$MEISTER_DIR/last.json"
  grep -q '"role": "batch-maintain"' "$MEISTER_DIR/last.json"
  grep -q '"ai_heal_mode": "suggest-only"' "$MEISTER_DIR/last.json"
}

@test "write_last_json execute mode" {
  AI_HEAL_EXECUTE=true
  write_last_json 90 1 0 0 0 0 10 deep 6.13
  grep -q '"ai_heal_mode": "execute"' "$MEISTER_DIR/last.json"
}
