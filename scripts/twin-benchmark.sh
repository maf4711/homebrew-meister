#!/usr/bin/env bash
# twin-benchmark.sh — meister (Ollama) vs meisterSiri (Apple Intelligence)
# Usage: ./scripts/twin-benchmark.sh [--json] [--quick]
# Exit 0 always after writing report (winner printed on stdout).
set -euo pipefail

JSON_ONLY=false
QUICK=false
for a in "$@"; do
  case "$a" in
    --json) JSON_ONLY=true ;;
    --quick) QUICK=true ;;
    -h|--help)
      echo "Usage: twin-benchmark.sh [--json] [--quick]"
      echo "  --quick  skip full dry-run --quick (only version/doctor/AI/lib)"
      exit 0
      ;;
  esac
done

# When invoked from Cellar bin/, also find brew-installed twin on PATH
MEISTER_BIN="${MEISTER_BIN:-$(command -v meister 2>/dev/null || true)}"
SIRI_BIN="${SIRI_BIN:-$(command -v meisterSiri 2>/dev/null || true)}"
# Prefer Cellar-resolved realpaths for fair comparison
if command -v realpath >/dev/null 2>&1; then
  [ -n "$MEISTER_BIN" ] && MEISTER_BIN=$(realpath "$MEISTER_BIN" 2>/dev/null || echo "$MEISTER_BIN")
  [ -n "$SIRI_BIN" ] && SIRI_BIN=$(realpath "$SIRI_BIN" 2>/dev/null || echo "$SIRI_BIN")
fi
OUT_DIR="${MEISTER_DIR:-$HOME/.meister}/benchmarks"
mkdir -p "$OUT_DIR"
STAMP=$(date -u +"%Y%m%dT%H%M%SZ")
REPORT_JSON="$OUT_DIR/twins-${STAMP}.json"
LATEST_JSON="$OUT_DIR/twins-latest.json"
TMPDIR_B=$(mktemp -d)
trap 'rm -rf "$TMPDIR_B"' EXIT

ms_now() { python3 -c 'import time; print(int(time.time()*1000))'; }

# run_timed name bin args...
# sets: LAST_MS LAST_RC LAST_OUT_BYTES LAST_SNIP
run_timed() {
  local name="$1"; shift
  local start end out err
  out="$TMPDIR_B/${name//\//_}.out"
  err="$TMPDIR_B/${name//\//_}.err"
  start=$(ms_now)
  set +e
  "$@" >"$out" 2>"$err"
  LAST_RC=$?
  set -e
  end=$(ms_now)
  LAST_MS=$((end - start))
  LAST_OUT_BYTES=$(wc -c <"$out" | tr -d ' ')
  LAST_SNIP=$(head -c 200 "$out" | tr '\n' ' ' | sed 's/"/\\"/g')
  LAST_OUT_FILE="$out"
}

have_ollama() {
  curl -sf --max-time 2 http://localhost:11434/api/tags >/dev/null 2>&1
}

have_apple_ai() {
  # meister-fm helper or meisterSiri doctor-ish: try explain with short timeout
  [ -x "${HOME}/.meister/meister-fm" ] || return 1
  return 0
}

if [ -z "$MEISTER_BIN" ] || [ -z "$SIRI_BIN" ]; then
  echo "ERROR: need both meister and meisterSiri on PATH (brew install meister)" >&2
  exit 1
fi

# Results as parallel arrays via newline records: twin|metric|ms|rc|bytes
RESULTS=()

record() {
  local twin="$1" metric="$2" ms="$3" rc="$4" bytes="$5"
  RESULTS+=("${twin}|${metric}|${ms}|${rc}|${bytes}")
}

run_suite() {
  local twin="$1" bin="$2"
  # 1 version
  run_timed "${twin}_version" "$bin" --version
  record "$twin" "version" "$LAST_MS" "$LAST_RC" "$LAST_OUT_BYTES"

  # 2 doctor --json
  run_timed "${twin}_doctor_json" "$bin" doctor --json
  record "$twin" "doctor_json" "$LAST_MS" "$LAST_RC" "$LAST_OUT_BYTES"
  local doctor_ok=0
  grep -q '"schema"' "$LAST_OUT_FILE" 2>/dev/null && doctor_ok=1
  record "$twin" "doctor_schema_ok" "$doctor_ok" "$doctor_ok" "0"

  # 3 lib / why profile
  run_timed "${twin}_why_profile" "$bin" why profile
  record "$twin" "why_profile" "$LAST_MS" "$LAST_RC" "$LAST_OUT_BYTES"
  local lib_ok=0
  grep -qE 'RUN_PROFILE|Sample membership|Quick whitelist' "$LAST_OUT_FILE" 2>/dev/null && lib_ok=1
  # fail if lib missing message
  grep -q 'lib/commands/extras.sh not loaded' "$LAST_OUT_FILE" 2>/dev/null && lib_ok=0
  record "$twin" "lib_loaded" "$lib_ok" "$lib_ok" "0"

  # 4 AI explain (backend-specific cost)
  run_timed "${twin}_explain" "$bin" explain "Spotlight indexiert mit hoher CPU — was tun?"
  record "$twin" "ai_explain" "$LAST_MS" "$LAST_RC" "$LAST_OUT_BYTES"
  local ai_ok=0
  [ "$LAST_RC" -eq 0 ] && [ "${LAST_OUT_BYTES:-0}" -gt 40 ] && ai_ok=1
  record "$twin" "ai_explain_ok" "$ai_ok" "$ai_ok" "0"

  # 5 dry-run quick (optional heavy)
  if ! $QUICK; then
    run_timed "${twin}_quick_dry" "$bin" --quick -n -q
    record "$twin" "quick_dry" "$LAST_MS" "$LAST_RC" "$LAST_OUT_BYTES"
    local dry_ok=0
    if [ "$LAST_RC" -eq 0 ] || [ "$LAST_RC" -eq 1 ]; then dry_ok=1; fi
    # prefer exit 0; still credit completion if report produced
    grep -qiE 'DRY-RUN|profile:|Meister|Profile=' "$LAST_OUT_FILE" 2>/dev/null && dry_ok=1
    record "$twin" "quick_dry_ok" "$dry_ok" "$dry_ok" "0"
  fi
}

run_suite "meister" "$MEISTER_BIN"
run_suite "meisterSiri" "$SIRI_BIN"

# Backend availability
OLLAMA_UP=0; have_ollama && OLLAMA_UP=1
APPLE_UP=0; have_apple_ai && APPLE_UP=1

# Score: higher is better
# - lib_loaded * 25
# - doctor_schema_ok * 15
# - ai_explain_ok * 25
# - quick_dry_ok * 15 (or skip)
# - latency points: max(0, 20 - ms/1000) for explain, max(0, 10 - ms/500) for doctor
score_twin() {
  local twin="$1"
  local score=0
  local line metric ms rc bytes
  local explain_ms=999999 doctor_ms=999999 why_ms=999999 dry_ms=999999
  local lib=0 doc=0 ai=0 dry=1

  for line in "${RESULTS[@]}"; do
    IFS='|' read -r t metric ms rc bytes <<<"$line"
    [ "$t" = "$twin" ] || continue
    case "$metric" in
      lib_loaded) lib=$ms ;;
      doctor_schema_ok) doc=$ms ;;
      ai_explain_ok) ai=$ms ;;
      quick_dry_ok) dry=$ms ;;
      ai_explain) explain_ms=$ms ;;
      doctor_json) doctor_ms=$ms ;;
      why_profile) why_ms=$ms ;;
      quick_dry) dry_ms=$ms ;;
    esac
  done

  score=$((score + lib * 25 + doc * 15 + ai * 25))
  if ! $QUICK; then
    score=$((score + dry * 15))
  else
    score=$((score + 15)) # neutral if skipped
  fi

  # Latency: explain (weight 20), doctor (10), why (5)
  local lat=0
  # explain: 0ms=20pts, 20s=0
  if [ "$explain_ms" -lt 999999 ]; then
    lat=$((20 - explain_ms / 1000))
    [ "$lat" -lt 0 ] && lat=0
    [ "$lat" -gt 20 ] && lat=20
    score=$((score + lat))
  fi
  if [ "$doctor_ms" -lt 999999 ]; then
    lat=$((10 - doctor_ms / 500))
    [ "$lat" -lt 0 ] && lat=0
    score=$((score + lat))
  fi
  if [ "$why_ms" -lt 999999 ]; then
    lat=$((5 - why_ms / 200))
    [ "$lat" -lt 0 ] && lat=0
    score=$((score + lat))
  fi

  # Backend available bonus
  if [ "$twin" = "meister" ] && [ "$OLLAMA_UP" -eq 1 ]; then score=$((score + 5)); fi
  if [ "$twin" = "meisterSiri" ] && [ "$APPLE_UP" -eq 1 ]; then score=$((score + 5)); fi

  echo "$score"
}

SCORE_M=$(score_twin meister)
SCORE_S=$(score_twin meisterSiri)

WINNER="tie"
if [ "$SCORE_S" -gt "$SCORE_M" ]; then WINNER="meisterSiri"
elif [ "$SCORE_M" -gt "$SCORE_S" ]; then WINNER="meister"
fi

# Preferred maintain CLI for heald (prefer Apple twin if tie or win)
PREFERRED="meisterSiri"
[ "$WINNER" = "meister" ] && PREFERRED="meister"

# Persist preference for heald / humans
PREF_FILE="${MEISTER_DIR:-$HOME/.meister}/preferred_twin"
echo "$PREFERRED" > "$PREF_FILE"

# Metric helper for JSON
json_metrics_for() {
  local twin="$1"
  local first=1
  printf '"metrics":{'
  for line in "${RESULTS[@]}"; do
    IFS='|' read -r t metric ms rc bytes <<<"$line"
    [ "$t" = "$twin" ] || continue
    [ $first -eq 1 ] || printf ','
    first=0
    printf '"%s":{"ms":%s,"rc":%s,"bytes":%s}' "$metric" "$ms" "$rc" "$bytes"
  done
  printf '}'
}

# Write JSON report
{
  echo "{"
  echo "  \"schema\": \"meister.twins_bench/v1\","
  echo "  \"ts\": \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\","
  echo "  \"host\": \"$(scutil --get LocalHostName 2>/dev/null || hostname -s)\","
  echo "  \"quick_mode\": $($QUICK && echo true || echo false),"
  echo "  \"ollama_up\": $OLLAMA_UP,"
  echo "  \"apple_fm_helper\": $APPLE_UP,"
  echo "  \"meister_bin\": \"$MEISTER_BIN\","
  echo "  \"meisterSiri_bin\": \"$SIRI_BIN\","
  echo "  \"score_meister\": $SCORE_M,"
  echo "  \"score_meisterSiri\": $SCORE_S,"
  echo "  \"winner\": \"$WINNER\","
  echo "  \"preferred_maintain\": \"$PREFERRED\","
  echo "  \"twins\": {"
  echo -n "    \"meister\": {"; json_metrics_for meister; echo "},"
  echo -n "    \"meisterSiri\": {"; json_metrics_for meisterSiri; echo "}"
  echo "  }"
  echo "}"
} > "$REPORT_JSON"
cp "$REPORT_JSON" "$LATEST_JSON"

if $JSON_ONLY; then
  cat "$REPORT_JSON"
  exit 0
fi

# Human report
echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║  Meister Twin Benchmark — Ollama vs Apple Intelligence  ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
printf "  %-14s  %8s  %8s\n" "Metric" "meister" "meisterSiri"
printf "  ─%.0s" $(seq 1 44); echo ""

print_row() {
  local metric="$1" label="$2"
  local m_ms="—" s_ms="—"
  local line t met ms rc bytes
  for line in "${RESULTS[@]}"; do
    IFS='|' read -r t met ms rc bytes <<<"$line"
    [ "$met" = "$metric" ] || continue
    [ "$t" = "meister" ] && m_ms="${ms}ms"
    [ "$t" = "meisterSiri" ] && s_ms="${ms}ms"
  done
  # boolean metrics use 0/1 as ms field
  case "$metric" in
    *_ok|lib_loaded)
      m_ms="no"; s_ms="no"
      for line in "${RESULTS[@]}"; do
        IFS='|' read -r t met ms rc bytes <<<"$line"
        [ "$met" = "$metric" ] || continue
        [ "$t" = "meister" ] && { [ "$ms" = "1" ] && m_ms="yes" || m_ms="no"; }
        [ "$t" = "meisterSiri" ] && { [ "$ms" = "1" ] && s_ms="yes" || s_ms="no"; }
      done
      ;;
  esac
  printf "  %-14s  %8s  %8s\n" "$label" "$m_ms" "$s_ms"
}

print_row version "version"
print_row doctor_json "doctor --json"
print_row doctor_schema_ok "doctor schema"
print_row why_profile "why profile"
print_row lib_loaded "lib loaded"
print_row ai_explain "AI explain"
print_row ai_explain_ok "AI ok"
if ! $QUICK; then
  print_row quick_dry "--quick -n"
  print_row quick_dry_ok "dry-run ok"
fi

echo ""
echo "  Backend:  Ollama=$OLLAMA_UP  AppleFM-helper=$APPLE_UP"
echo "  Score:    meister=$SCORE_M   meisterSiri=$SCORE_S"
echo ""
if [ "$WINNER" = "tie" ]; then
  echo "  Winner:   TIE — preferred maintain: $PREFERRED"
else
  echo "  Winner:   $WINNER  (preferred maintain CLI for heald: $PREFERRED)"
fi
echo ""
echo "  Report:   $REPORT_JSON"
echo "  Pref:     $PREF_FILE → $PREFERRED"
echo ""

# Short recommendation
if [ "$WINNER" = "meisterSiri" ]; then
  echo "  Empfehlung: meisterSiri als Default (LaunchAgents / heald trigger)."
  echo "  meister behalten wenn Ollama offline-Apple / Server-Szenario."
elif [ "$WINNER" = "meister" ]; then
  echo "  Empfehlung: meister (Ollama) schlägt gerade Apple-Twin."
  echo "  Prüfe Apple Intelligence Settings / meister-fm helper."
else
  echo "  Empfehlung: Gleichstand — meisterSiri als keep-current Default behalten."
fi
echo ""
