#!/usr/bin/env bash
# sync-twins.sh — meisterSiri.sh (Apple Intelligence) → meister.sh (Ollama)
#
# MERKREGEL: Feature-Quelle ist IMMER meisterSiri.sh.
#   ./scripts/sync-twins.sh && ./release.sh
# release.sh ruft dies automatisch.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/meisterSiri.sh"
DST="$ROOT/meister.sh"
[ -f "$SRC" ] || { echo "missing $SRC" >&2; exit 1; }

python3 - "$SRC" "$DST" <<'PY'
import re
import sys
from pathlib import Path

src, dst = Path(sys.argv[1]), Path(sys.argv[2])
t = src.read_text()
if "log() {" not in t:
    raise SystemExit("source missing log() — refuse to sync")

# Branding
t = t.replace("# meisterSiri.sh\n", "# meister.sh\n", 1)
t = t.replace("# Usage: ./meisterSiri.sh [flags]", "# Usage: ./meister.sh [flags]", 1)
t = re.sub(
    r"# Twin of[^\n]*\n(?:# [^\n]*\n){0,8}",
    "# Twin of meisterSiri.sh — same modules/autofix/profiles/keep-current.\n"
    "# AI backend = Ollama (localhost:11434). meisterSiri = Apple Intelligence.\n"
    "# Shares ~/.meister/. KEEP IN SYNC: edit meisterSiri.sh → scripts/sync-twins.sh\n",
    t,
    count=1,
)
t = t.replace("MeisterSiri", "Meister")
t = t.replace("meisterSiri", "meister")
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
    raise SystemExit("TWIN:META-AI missing in meisterSiri.sh")
t = re.sub(meta_pat, meta_new, t, count=1, flags=re.S)

# Function backend only (never match META)
backend_pat = (
    r"# ===== TWIN:AI-BACKEND \(Apple Intelligence — [Mm]eister\) =====.*?"
    r"# ===== /TWIN:AI-BACKEND =====\n*"
)
ollama = r"""# ===== TWIN:AI-BACKEND (Ollama — meister) =====
ensure_fm_helper() {
    if ! command -v jq >/dev/null 2>&1 && ! command -v python3 >/dev/null 2>&1; then
        return 1
    fi
    return 0
}
fm_available() {
    [ "${FM_ENABLED:-true}" = "true" ] || return 1
    curl -sf --max-time 2 "${MEISTER_OLLAMA_URL:-http://localhost:11434}/api/tags" >/dev/null 2>&1
}
fm_query() {
    local prompt="$1"
    local label="${2:-query}"
    local url="${MEISTER_OLLAMA_URL:-http://localhost:11434}"
    local model="${MEISTER_OLLAMA_MODEL:-qwen3-coder:30b}"
    if [ "${AI_TRACE:-true}" = "true" ]; then
        ai_trace_box "REQUEST → ${AI_BACKEND_LABEL} ($label / $model)" "$prompt"
        ai_trace_line "Warte auf Antwort (${AI_BACKEND_LABEL})…"
    fi
    local payload resp
    if command -v jq >/dev/null 2>&1; then
        payload=$(jq -n --arg m "$model" --arg p "$prompt" '{model:$m, prompt:$p, stream:false}')
    else
        payload=$(python3 -c 'import json,sys; print(json.dumps({"model":sys.argv[1],"prompt":sys.argv[2],"stream":False}))' "$model" "$prompt")
    fi
    resp=$(curl -sf --max-time 180 "$url/api/generate" \
        -H 'Content-Type: application/json' -d "$payload" 2>/dev/null \
        | if command -v jq >/dev/null 2>&1; then jq -r '.response // empty'
          else python3 -c 'import sys,json; print(json.load(sys.stdin).get("response") or "")'; fi) || true
    if [ "${AI_TRACE:-true}" = "true" ]; then
        if [ -n "$resp" ]; then
            ai_trace_box "RESPONSE ← ${AI_BACKEND_LABEL} ($label)" "$resp"
        else
            ai_trace_box "RESPONSE ← ${AI_BACKEND_LABEL} ($label)" "(leer — ollama serve / model pull?)"
        fi
    fi
    printf '%s' "$resp"
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

dst.write_text(t)
print(f"OK: {dst.name} {len(t)} bytes (Ollama twin)")
print("  log + autofix + ollama generate: OK")
PY

bash -n "$SRC"
bash -n "$DST"
if grep -E 'meisterSiri|MeisterSiri' "$DST" >/dev/null; then
  echo "FAIL residual branding" >&2
  grep -nE 'meisterSiri|MeisterSiri' "$DST" | head
  exit 1
fi
"$SRC" --version
"$DST" --version
echo "DONE: meisterSiri=Apple · meister=Ollama"
