#!/usr/bin/env bash
# tests/test_twin_symmetry.sh — twins may differ ONLY inside TWIN regions.
set -u
DIR="$(cd "$(dirname "$0")/.." && pwd)"

[ -f "$DIR/meisterSiri.sh" ] || { echo "FAIL: meisterSiri.sh missing"; exit 1; }

strip_twin() {
    awk '
        /^# ===== TWIN:/      { skip=1; next }
        /^# ===== \/TWIN:/    { skip=0; next }
        !skip                 { print }
    ' "$1"
}

a="$(strip_twin "$DIR/meister.sh")"
b="$(strip_twin "$DIR/meisterSiri.sh")"
if [ "$a" = "$b" ]; then
    echo "ok: twins identical outside TWIN regions"
else
    echo "FAIL: twins diverge outside TWIN regions:"
    diff <(printf '%s' "$a") <(printf '%s' "$b") | head -40
    exit 1
fi
