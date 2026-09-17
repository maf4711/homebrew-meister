#!/usr/bin/env bats
setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  MEISTER_LIB_DIR="$ROOT/lib"
  eval "$(sed -n '/^# ===== TWIN:AI-BACKEND (Ollama/,/^# ===== \/TWIN:AI-BACKEND =====/p' "$ROOT/meister.sh")"
  AI_TRACE=true
  ai_usage_record() { printf '%s\n' "$*" >> "$BATS_TEST_TMPDIR/audit"; }
  ai_call_banner() { printf '%s\n' "$*" >> "$BATS_TEST_TMPDIR/trace"; }
  ai_trace_line() { printf '%s\n' "$*" >> "$BATS_TEST_TMPDIR/trace"; }
}
@test "Ollama helper receives unexported user configuration" {
  MEISTER_OLLAMA_MODEL=fixture:latest
  MEISTER_OLLAMA_URL=http://127.0.0.1:12345
  MEISTER_OLLAMA_TIMEOUT=12
  MEISTER_OLLAMA_NUM_CTX=4096
  MEISTER_OLLAMA_NUM_PREDICT=512
  MEISTER_OLLAMA_KEEP_ALIVE=2m
  MEISTER_OLLAMA_THINK=low
  python3() { env > "$BATS_TEST_TMPDIR/env"; }
  fm_ollama_client --check
  for entry in 'MODEL=fixture:latest' 'URL=http://127.0.0.1:12345' 'TIMEOUT=12' 'NUM_CTX=4096' 'NUM_PREDICT=512' 'KEEP_ALIVE=2m' 'THINK=low'; do
    grep -qx "MEISTER_OLLAMA_$entry" "$BATS_TEST_TMPDIR/env"
  done
}
@test "Ollama disabled does not call transport" {
  FM_ENABLED=false
  fm_ollama_client() { touch "$BATS_TEST_TMPDIR/called"; }
  run fm_available
  [ "$status" -ne 0 ]
  run fm_query hello explain
  [ "$status" = 69 ]
  [ ! -e "$BATS_TEST_TMPDIR/called" ]
}
@test "Ollama errors propagate with counters and no raw prompt in trace or audit" {
  fm_ollama_client() { cat >/dev/null; printf '{"status":"timeout"}' >&2; return 75; }
  rc=0
  fm_query 'password=VERYSECRET' ai-heal > "$BATS_TEST_TMPDIR/response" 2>/dev/null || rc=$?
  [ "$rc" = 75 ]
  [ "$AI_CALLS_THIS_RUN" = 1 ]
  [ "$AI_HEAL_CALLS_THIS_RUN" = 1 ]
  [ ! -s "$BATS_TEST_TMPDIR/response" ]
  grep -q response-error "$BATS_TEST_TMPDIR/audit"
  ! grep -q VERYSECRET "$BATS_TEST_TMPDIR/audit" "$BATS_TEST_TMPDIR/trace"
}
@test "Ollama readonly response stays text and counters persist" {
  fm_ollama_client() { cat >/dev/null; printf 'Plain answer'; printf '{"eval_count":8}' >&2; }
  fm_query hello explain > "$BATS_TEST_TMPDIR/response"
  [ "$(cat "$BATS_TEST_TMPDIR/response")" = 'Plain answer' ]
  [ "$AI_READONLY_CALLS_THIS_RUN" = 1 ]
  grep -q eval_count "$BATS_TEST_TMPDIR/audit"
}

run_text_command() {
  fm_available() { return 0; }
  fm_query() { return 75; }
  local snippet
  snippet=$(awk -v target="$1" '$0 == "if [ \"${1:-}\" = \"" target "\" ]; then" {on=1} on {print} on && /^fi$/ {exit}' "$ROOT/meister.sh")
  set -- "$1" 'fixture warning'
  eval "$snippet"
}
@test "explain propagates generation failures through rendering pipeline" {
  run run_text_command explain
  [ "$status" = 75 ]
}
@test "suggest propagates generation failures through rendering pipeline" {
  run run_text_command suggest
  [ "$status" = 75 ]
}
