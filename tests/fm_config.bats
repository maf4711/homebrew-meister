#!/usr/bin/env bats
# Exercise the real config parser through model routing, without model access.
setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SOURCE="${FM_CONFIG_SOURCE:-$ROOT/MeisterAI.sh}"
  export MEISTER_DIR="$BATS_TEST_TMPDIR/state"
  mkdir -p "$MEISTER_DIR"
  HARNESS="$BATS_TEST_TMPDIR/query.sh"
  cat > "$HARNESS" <<'SH'
ensure_fm_helper() { return 0; }
ai_usage_record() { :; }
ai_trace_line() { :; }
timeout() { cat >/dev/null; printf '%s\n' "$*"; }
FM_HELPER=mock-helper
SH
  # Keep declare assignments at script scope, just as in the production CLI.
  awk '/^# Load config file / {on=1} /^# Side-effect-free capability probe/ {exit} on {print}' "$SOURCE" >> "$HARNESS"
  awk '$0=="fm_query() {" {on=1} on {print} on && /^}$/ {exit}' "$SOURCE" >> "$HARNESS"
  printf '\nfm_query fixture "$1"\n' >> "$HARNESS"
  unset FM_HEAL_MODEL FM_DIAGNOSE_MODEL
}

@test "system in config prevents AI-Heal auto routing" {
  printf 'FM_HEAL_MODEL=system\n' > "$MEISTER_DIR/config"
  run bash "$HARNESS" ai-heal
  [ "$status" = 0 ]
  [ "$output" = '35 mock-helper --purpose ai-heal --model system' ]
}

@test "quoted config routes diagnosis to the explicitly selected model" {
  printf 'FM_DIAGNOSE_MODEL="pcc"\n' > "$MEISTER_DIR/config"
  run bash "$HARNESS" ai-diagnose
  [ "$status" = 0 ]
  [ "$output" = '80 mock-helper --purpose ai-diagnose --model pcc' ]
}

@test "model config overrides inherited routing" {
  printf "FM_HEAL_MODEL='system'\nFM_DIAGNOSE_MODEL=system\n" > "$MEISTER_DIR/config"
  run env FM_HEAL_MODEL=pcc FM_DIAGNOSE_MODEL=pcc bash "$HARNESS" ai-heal
  [ "$status" = 0 ]
  [ "$output" = '35 mock-helper --purpose ai-heal --model system' ]
  run env FM_HEAL_MODEL=pcc FM_DIAGNOSE_MODEL=pcc bash "$HARNESS" ai-diagnose
  [ "$status" = 0 ]
  [ "$output" = '35 mock-helper --purpose ai-diagnose --model system' ]
}

@test "invalid configured model fails closed before invoking a model" {
  printf 'FM_HEAL_MODEL=$(touch "%s")\n' "$MEISTER_DIR/unexpected" > "$MEISTER_DIR/config"
  run bash "$HARNESS" ai-heal
  [ "$status" = 64 ]
  [ -z "$output" ]
  [ ! -e "$MEISTER_DIR/unexpected" ]
}

@test "absent model settings preserve auto heal and local diagnosis defaults" {
  run bash "$HARNESS" ai-heal
  [ "$status" = 0 ]
  [ "$output" = '80 mock-helper --purpose ai-heal --model auto' ]
  run bash "$HARNESS" ai-diagnose
  [ "$status" = 0 ]
  [ "$output" = '35 mock-helper --purpose ai-diagnose --model system' ]
}

@test "absent model settings preserve explicit environment routing" {
  run env FM_HEAL_MODEL=system bash "$HARNESS" ai-heal
  [ "$status" = 0 ]
  [ "$output" = '35 mock-helper --purpose ai-heal --model system' ]
  run env FM_DIAGNOSE_MODEL=pcc bash "$HARNESS" ai-diagnose
  [ "$status" = 0 ]
  [ "$output" = '80 mock-helper --purpose ai-diagnose --model pcc' ]
}

@test "diagnostic model settings leave text queries on device" {
  printf 'FM_HEAL_MODEL=pcc\nFM_DIAGNOSE_MODEL=pcc\n' > "$MEISTER_DIR/config"
  for purpose in explain today suggest; do
    run bash "$HARNESS" "$purpose"
    [ "$status" = 0 ]
    [ "$output" = "35 mock-helper --purpose $purpose --model system" ]
  done
}
