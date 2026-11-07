#!/usr/bin/env bash
# sync-twins.sh — MeisterAI.sh (Apple Intelligence) → meister.sh (Ollama)
#
# MERKREGEL: Feature-Quelle ist IMMER MeisterAI.sh.
#   ./scripts/sync-twins.sh && ./release.sh
# release.sh ruft dies automatisch.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/MeisterAI.sh"
DST="$ROOT/meister.sh"
[ -f "$SRC" ] || { echo "missing $SRC" >&2; exit 1; }
MODE="${1:-write}"
case "$MODE" in
  write|--check) ;;
  *) echo "Usage: $0 [--check]" >&2; exit 2 ;;
esac

python3 - "$SRC" "$DST" "$MODE" <<'PY'
import re
import sys
from pathlib import Path

src, dst = Path(sys.argv[1]), Path(sys.argv[2])
check_only = sys.argv[3] == "--check"
t = src.read_text()
if "log() {" not in t:
    raise SystemExit("source missing log() — refuse to sync")

# Branding
t = t.replace("# MeisterAI.sh\n", "# meister.sh\n", 1)
t = t.replace("# Usage: ./MeisterAI.sh [flags]", "# Usage: ./meister.sh [flags]", 1)
t = re.sub(
    r"# Twin of[^\n]*\n(?:# [^\n]*\n){0,8}",
    "# Twin of MeisterAI.sh — same modules/autofix/profiles/keep-current.\n"
    "# AI backend = Ollama (localhost:11434). MeisterAI = Apple Intelligence.\n"
    "# Shares ~/.meister/. KEEP IN SYNC: edit MeisterAI.sh → scripts/sync-twins.sh\n",
    t,
    count=1,
)
t = t.replace("MeisterAI", "meister")
# Preserve the established Ollama display name independently of its executable.
t = t.replace("meister - macOS Maintenance", "Meister - macOS Maintenance")
t = re.sub(
    r'--version\) echo "meister v\$\{MEISTER_VERSION\}[^"]*"; exit 0 ;;',
    '--version) echo "meister v${MEISTER_VERSION} (Ollama)"; exit 0 ;;',
    t,
    count=1,
)
t = t.replace(
    "Meister - macOS Maintenance, Self-Healing & Dotfiles Sync (Apple Intelligence)",
    "Meister - macOS Maintenance, Self-Healing & Dotfiles Sync (Ollama AI)",
)

# META labels → Ollama
meta_pat = r"# ===== TWIN:META-AI.*?===== /TWIN:META-AI =====\n"
meta_new = """# ===== TWIN:META-AI (Ollama — meister) =====
AI_BACKEND_LABEL="Ollama"
AI_BACKEND_KIND="ollama"
MEISTER_OLLAMA_URL="${MEISTER_OLLAMA_URL:-http://localhost:11434}"
MEISTER_OLLAMA_MODEL="${MEISTER_OLLAMA_MODEL:-qwen3-coder:30b}"
# ===== /TWIN:META-AI =====
"""
if not re.search(meta_pat, t, re.S):
    raise SystemExit("TWIN:META-AI missing in MeisterAI.sh")
t = re.sub(meta_pat, meta_new, t, count=1, flags=re.S)

# Function backend only (never match META)
backend_pat = (
    r"# ===== TWIN:AI-BACKEND \(Apple Intelligence — [Mm]eister\) =====.*?"
    r"# ===== /TWIN:AI-BACKEND =====\n*"
)
ollama = r"""# ===== TWIN:AI-BACKEND (Ollama — meister) =====
ensure_fm_helper() {
    command -v python3 >/dev/null 2>&1 && command -v curl >/dev/null 2>&1 &&
        [ -f "${MEISTER_LIB_DIR}/ollama/client.py" ]
}
fm_ollama_client() {
    MEISTER_OLLAMA_URL="${MEISTER_OLLAMA_URL:-http://localhost:11434}" \
    MEISTER_OLLAMA_MODEL="${MEISTER_OLLAMA_MODEL:-qwen3-coder:30b}" \
    MEISTER_OLLAMA_TIMEOUT="${MEISTER_OLLAMA_TIMEOUT:-90}" \
    MEISTER_OLLAMA_THINK="${MEISTER_OLLAMA_THINK:-false}" \
    MEISTER_OLLAMA_KEEP_ALIVE="${MEISTER_OLLAMA_KEEP_ALIVE:-5m}" \
    MEISTER_OLLAMA_NUM_CTX="${MEISTER_OLLAMA_NUM_CTX:-8192}" \
    MEISTER_OLLAMA_NUM_PREDICT="${MEISTER_OLLAMA_NUM_PREDICT:-1024}" \
        python3 "${MEISTER_LIB_DIR}/ollama/client.py" "$@"
}
fm_available() {
    [ "${FM_ENABLED:-true}" = true ] || return 1
    ensure_fm_helper || return 1
    fm_ollama_client --check >/dev/null 2>&1
}
# Same validated diagnosis contract as Apple, with bounded Ollama transport.
fm_query() {
    local prompt="$1" label="${2:-query}" mode="${3:-readonly}"
    local purpose="$label" work rc=0 meta
    case "$label" in
        AI-Heal:*|ai-heal*|heal:*) purpose=ai-heal; mode=heal-candidate ;;
        explain*) purpose=explain; mode=readonly ;;
        ai-diagnose*|diagnose*) purpose=ai-diagnose; mode=readonly ;;
        today*) purpose=today; mode=readonly ;;
        suggest*) purpose=suggest; mode=readonly ;;
    esac
    [ "${FM_ENABLED:-true}" = true ] && ensure_fm_helper || return 69
    AI_CALLS_THIS_RUN=$(( ${AI_CALLS_THIS_RUN:-0} + 1 ))
    if [ "$mode" = heal-candidate ]; then
        AI_HEAL_CALLS_THIS_RUN=$(( ${AI_HEAL_CALLS_THIS_RUN:-0} + 1 ))
    else
        AI_READONLY_CALLS_THIS_RUN=$(( ${AI_READONLY_CALLS_THIS_RUN:-0} + 1 ))
    fi
    ai_usage_record "$purpose" "$mode" request "backend=ollama"
    if [ "${AI_TRACE:-true}" = true ]; then
        ai_call_banner "$purpose" "$mode" "Ollama"
        ai_trace_line "Ollama: Anfrage läuft (Call #${AI_CALLS_THIS_RUN})"
    fi
    work=$(mktemp -d "${TMPDIR:-/tmp}/meister-ollama.XXXXXX") || return 1
    chmod 700 "$work"
    printf '%s' "$prompt" | fm_ollama_client --purpose "$purpose" > "$work/response" 2> "$work/metadata" || rc=$?
    # The helper emits fixed status labels and numeric timing/token metadata only.
    meta=$(cat "$work/metadata")
    if [ "$rc" = 0 ]; then
        ai_usage_record "$purpose" "$mode" response-ok "$meta"
        cat "$work/response"
    else
        ai_usage_record "$purpose" "$mode" response-error "$meta"
        printf 'Ollama: Anfrage fehlgeschlagen (Exit %s). %s\n' "$rc" "$meta" >&2
    fi
    rm -rf "$work"
    return "$rc"
}
# ===== /TWIN:AI-BACKEND =====

"""
m = re.search(backend_pat, t, flags=re.S)
if not m:
    raise SystemExit("Apple AI-BACKEND block not found after branding")
if "log() {" in m.group() or "rotate_logs()" in m.group():
    raise SystemExit("SAFETY: backend match would delete log()")
t = t[: m.start()] + ollama + t[m.end() :]
if "log() {" not in t:
    raise SystemExit("log() missing after inject")

if check_only:
    if not dst.exists() or dst.read_text() != t:
        raise SystemExit("FAIL: twins differ; run bash scripts/sync-twins.sh")
else:
    dst.write_text(t)
print(f"OK: {dst.name} {len(t)} bytes (Ollama twin)")
print("  log + autofix + ollama generate: OK")
PY

bash -n "$SRC"
bash -n "$DST"
if grep -E 'MeisterAI' "$DST" >/dev/null; then
  echo "FAIL residual branding" >&2
  grep -nE 'MeisterAI' "$DST" | head
  exit 1
fi
# Do not execute either maintenance CLI during synchronization or CI.
# Syntax and generated-source equality are sufficient and have no host side effects.
echo "DONE: MeisterAI=Apple · meister=Ollama"
