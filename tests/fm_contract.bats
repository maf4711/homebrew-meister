#!/usr/bin/env bats
setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export MEISTER_LIB_DIR="$ROOT/lib" MEISTER_DIR="$BATS_TEST_TMPDIR/state"
  mkdir -p "$MEISTER_DIR"
  source "$ROOT/lib/core/fm_diagnosis.sh"
  source "$ROOT/lib/core/heal_guards.sh"
  ai_usage_record() { printf '%s\n' "$*" >> "$MEISTER_DIR/audit"; }
}
@test "valid catalog response maps to exact executable and never runs it" {
  fm_query() { printf '%s' '{"schema":"meister.diagnosis/v1","cause":"QuickLook cache failed","evidence":["E1"],"missing_information":[],"next_check":"Retest QuickLook","action":"quicklook_cache_reset","parameters":[]}'; }
  fm_diagnose QuickLook 'QuickLook cache failed'
  [ "$FM_DIAGNOSIS_COMMAND" = '/usr/bin/qlmanage -r cache' ]
  [ -f "$FM_DIAGNOSIS_FILE" ]
  grep -q diagnosis-valid "$MEISTER_DIR/audit"
}
@test "arbitrary model shell is not accepted as a diagnosis" {
  fm_query() { echo 'killall Finder'; }
  run fm_diagnose Finder 'Finder hangs'
  [ "$status" = 2 ]
  grep -q invalid-response "$MEISTER_DIR/audit"
}
@test "model transport failure is not recorded as no-fix or success" {
  fm_query() { return 124; }
  run fm_diagnose Finder 'Finder hangs'
  [ "$status" = 124 ]
  [ ! -f "$MEISTER_DIR/audit" ]
}
@test "context preserves module exit prior attempt and bounded ends without secrets" {
  python3 "$MEISTER_LIB_DIR/fm/contract.py" context --module Finder --previous '/usr/bin/killall Finder' --error "$(printf 'Exit: 1\n'; for n in {1..100}; do echo "event $n"; done; echo 'token=supersecret Finder failed')" --state-dir "$MEISTER_DIR" > "$MEISTER_DIR/context.json"
  python3 - "$MEISTER_DIR/context.json" <<'PY'
import json,sys
c=json.load(open(sys.argv[1]))
assert c['module']=='Finder' and c['previous_attempt']=='/usr/bin/killall Finder'
assert 'Exit: 1' in c['error'] and 'Finder failed' in c['error']
assert 'supersecret' not in json.dumps(c)
assert len(c['evidence']) <=20
PY
}
@test "catalog rejects learned free commands and absolute-path spoofing" {
  ! heal_catalog_command_allowed 'killall Finder'
  ! heal_catalog_command_allowed '/tmp/killall Finder'
  ! heal_catalog_command_allowed '/usr/bin/killall -9 Finder'
  heal_catalog_command_allowed '/usr/bin/killall Finder'
}
@test "report explicitly separates actions from verified repairs" {
  printf '%s' '{"run_id":"test","status":"partial","dry_run":false,"verified_repair_count":0,"fixes":["update triggered"],"warnings":["still outdated"]}' > "$MEISTER_DIR/last.json"
  run fm_report_summary
  [ "$status" = 0 ]
  [[ "$output" == *'Verifizierte Reparaturen: 0'* ]]
  [[ "$output" == *'Protokollierte Maßnahme [fixes/0]: update triggered'* ]]
  [[ "$output" == *'Offen [warnings/0]: still outdated'* ]]
}
@test "wrapper distinguishes timeout unavailable context guardrail and empty" {
  eval "$(awk '$0=="fm_query() {" {on=1} on {print} on && /^}$/ {exit}' "$ROOT/MeisterAI.sh")"
  ensure_fm_helper() { return 0; }
  ai_trace_line() { :; }
  FM_HELPER=unused
  timeout() { cat >/dev/null; echo 'fm-error kind=guardrail' >&2; return 70; }
  run fm_query data query
  [ "$status" = 70 ]; grep -q guardrail "$MEISTER_DIR/audit"
  timeout() { cat >/dev/null; return 124; }
  run fm_query data query
  [ "$status" = 124 ]; grep -q timeout "$MEISTER_DIR/audit"
  timeout() { cat >/dev/null; echo 'fm-error kind=unavailable' >&2; return 69; }
  run fm_query data query
  [ "$status" = 69 ]; grep -q unavailable "$MEISTER_DIR/audit"
  timeout() { cat >/dev/null; echo 'fm-error kind=context' >&2; return 70; }
  run fm_query data query
  [ "$status" = 70 ]; grep -q context "$MEISTER_DIR/audit"
  timeout() { cat >/dev/null; return 0; }
  run fm_query data query
  [ "$status" = 65 ]; grep -q response-empty "$MEISTER_DIR/audit"
}
@test "quoted JSON credentials basic auth and URL passwords are redacted" {
  python3 - "$MEISTER_LIB_DIR/fm/contract.py" <<'PY'
import importlib.util,sys
spec=importlib.util.spec_from_file_location('contract',sys.argv[1]); m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
for text in ['{"token": "synthetic-secret"}', '{"password":"synthetic-secret"}', "{'api_key':'synthetic-secret'}", 'Authorization: Basic c3ludGhldGlj', 'https://user:synthetic-secret@example.invalid/path', 'password=synthetic-secret']:
    clean=m.redact(text)
    assert 'synthetic-secret' not in clean and 'c3ludGhldGlj' not in clean, clean
PY
}
@test "legacy report does not invent verification or execution evidence" {
  printf '%s' '{"run_id":"legacy","fix":4}' > "$MEISTER_DIR/last.json"
  run fm_report_summary
  [ "$status" = 0 ]
  [[ "$output" == *'Ausführungsart unbekannt'* ]]
  [[ "$output" != *'Verifizierte Reparaturen: 0'* ]]
}
@test "configured PCC availability passes requested model to helper" {
  eval "$(awk '$0=="fm_available() {" {on=1} on {print} on && /^}$/ {exit}' "$ROOT/MeisterAI.sh")"
  ensure_fm_helper() { return 0; }
  FM_HELPER="$MEISTER_DIR/check"
  printf '#!/bin/bash\n[ "$*" = "--check --model pcc" ]\n' > "$FM_HELPER"
  chmod +x "$FM_HELPER"
  run fm_available pcc
  [ "$status" = 0 ]
}

load_ai_heal() {
  eval "$(awk '$0=="ai_heal() {" {on=1} on {print} on && /^}$/ {exit}' "$ROOT/MeisterAI.sh")"
  fm_available() { return 0; }
  ai_heal_emit() { :; }; ai_heal_box() { :; }; ai_trace_line() { :; }
  log() { :; }
  log_heal_event() { printf '%s\n' "$*" >> "$MEISTER_DIR/heals"; }
  report_add() { printf '%s\n' "$*" >> "$MEISTER_DIR/reports"; }
  learned_fix_suspended() { return 1; }
  heal_missing_path() { return 1; }
  learned_fix_record() { printf '%s\n' "$*" >> "$MEISTER_DIR/learned"; }
  fm_query() { printf '%s' '{"schema":"meister.diagnosis/v1","cause":"QuickLook cache failed","evidence":["E1"],"missing_information":[],"next_check":"Retest QuickLook","action":"quicklook_cache_reset","parameters":[]}'; }
  timeout() { printf '%s\n' "$*" >> "$MEISTER_DIR/execution"; }
  DRY_RUN=false
}
@test "actual AI heal suggests catalog action without executing when AI_HEAL_EXECUTE=false" {
  load_ai_heal
  AI_HEAL_EXECUTE=false
  run ai_heal QuickLook 'QuickLook cache failed'
  [ "$status" = 1 ]
  [ ! -e "$MEISTER_DIR/execution" ]
  [ ! -e "$MEISTER_DIR/learned" ]
  grep -q suggested "$MEISTER_DIR/heals"
  grep -q 'not executed' "$MEISTER_DIR/reports"
}
@test "AI-Heal default in MeisterAI.sh is execute" {
  grep -qE '^AI_HEAL_EXECUTE=true' "$ROOT/MeisterAI.sh"
}
@test "AI heal executes allowlisted command when execute gate is unset" {
  load_ai_heal
  unset AI_HEAL_EXECUTE
  run ai_heal QuickLook 'QuickLook cache failed'
  [ "$status" = 0 ]
  [ "$(cat "$MEISTER_DIR/execution")" = '30 /usr/bin/qlmanage -r cache' ]
  grep -q executed "$MEISTER_DIR/heals"
}
@test "opt-in executes only mapped argv and does not call it verified" {
  load_ai_heal
  AI_HEAL_EXECUTE=true
  run ai_heal QuickLook 'QuickLook cache failed'
  [ "$status" = 0 ]
  [ "$(cat "$MEISTER_DIR/execution")" = '30 /usr/bin/qlmanage -r cache' ]
  grep -q executed "$MEISTER_DIR/heals"
  ! grep -q verified "$MEISTER_DIR/heals"
  [ ! -e "$MEISTER_DIR/learned" ]
  [ ! -e "$MEISTER_DIR/reports" ]
}
@test "preview never executes validated action even with execution opt-in" {
  load_ai_heal
  AI_HEAL_EXECUTE=true
  DRY_RUN=true
  run ai_heal QuickLook 'QuickLook cache failed'
  [ "$status" = 1 ]
  [ ! -e "$MEISTER_DIR/execution" ]
  grep -q WOULD "$MEISTER_DIR/reports"
}

@test "Ollama twin counts bare ai-heal purpose as candidate rather than readonly" {
  eval "$(awk '$0=="fm_query() {" {on=1} on {print} on && /^}$/ {exit}' "$ROOT/meister.sh")"
  command_exists() { command -v "$1" >/dev/null 2>&1; }
  ensure_fm_helper() { return 0; }
  fm_ollama_client() { cat >/dev/null; printf fixture; }
  AI_TRACE=false
  AI_CALLS_THIS_RUN=0; AI_HEAL_CALLS_THIS_RUN=0; AI_READONLY_CALLS_THIS_RUN=0
  fm_query '{}' ai-heal > "$MEISTER_DIR/response"
  [ "$AI_HEAL_CALLS_THIS_RUN" = 1 ]
  [ "$AI_READONLY_CALLS_THIS_RUN" = 0 ]
  grep -q 'ai-heal heal-candidate request' "$MEISTER_DIR/audit"
}
